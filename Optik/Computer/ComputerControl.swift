import AppKit
import ApplicationServices
import OptikCore
import os

/// Runs the computer tools (`llm/bilgisayar-araclari.json`) for Claude: reads the
/// front window, clicks and types with Optik's pointer, opens pages and apps, and
/// finds and arranges files. One tool at a time.
actor ComputerControl: ToolRunner {
    static let shared = ComputerControl()

    private let reader = ScreenReader()
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "computer")

    /// The tools, from the app bundle.
    static let tools: [ToolDefinition] = {
        guard let url = Bundle.main.url(forResource: "bilgisayar-araclari", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tools = try? ToolDefinition.decodeList(from: data) else { return [] }
        return tools
    }()

    func run(_ name: String, input: Data) async -> ToolOutput {
        let arguments = (try? JSONSerialization.jsonObject(with: input) as? [String: Any]) ?? [:]
        log.info("tool \(name, privacy: .public)")
        guard await MainActor.run(body: { AccessibilityControl.isTrusted }) || FileTools.handles(name) else {
            await MainActor.run { AccessibilityControl.requestTrust() }
            return ToolOutput("Optik'in Erişilebilirlik izni yok. Kullanıcıdan Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik'te Optik'i açmasını iste.", isError: true)
        }
        switch name {
        case "look_at_screen":
            return await look(appName: arguments["app"] as? String)
        case "click":
            guard let id = arguments["id"] as? Int else { return ToolOutput("id gerekli.", isError: true) }
            return await click(id, double: arguments["double"] as? Bool ?? false)
        case "type_text":
            guard let text = arguments["text"] as? String else { return ToolOutput("text gerekli.", isError: true) }
            return await type(text, into: arguments["id"] as? Int, replace: arguments["replace"] as? Bool ?? false,
                              submit: arguments["submit"] as? Bool ?? false)
        case "press_keys":
            guard let keys = arguments["keys"] as? String else { return ToolOutput("keys gerekli.", isError: true) }
            return await press(keys)
        case "scroll":
            return await scroll(down: (arguments["direction"] as? String) != "up")
        case "open_url":
            guard let text = arguments["url"] as? String, let url = URL(string: text),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                return ToolOutput("Geçerli bir https adresi ver.", isError: true)
            }
            return await openURL(url, browser: arguments["browser"] as? String)
        case "open_app":
            guard let app = arguments["name"] as? String else { return ToolOutput("name gerekli.", isError: true) }
            return await openApp(app)
        default:
            return FileTools.run(name, arguments: arguments)
        }
    }

    // MARK: Screen

    private func look(appName: String? = nil) async -> ToolOutput {
        guard let app = await targetApp(named: appName) else {
            return ToolOutput(appName.map { "\($0) açık değil." } ?? "Öndeki uygulama bulunamadı.", isError: true)
        }
        return ToolOutput(reader.snapshot(of: app))
    }

    /// The app named, or the one in front (not Optik).
    private func targetApp(named name: String?) async -> NSRunningApplication? {
        await MainActor.run {
            let own = Bundle.main.bundleIdentifier
            if let name {
                let wanted = name.lowercased(with: Locale(identifier: "tr_TR"))
                return NSWorkspace.shared.runningApplications.first {
                    $0.bundleIdentifier != own && $0.localizedName?.lowercased(with: Locale(identifier: "tr_TR")) == wanted
                }
            }
            if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != own { return front }
            return NSWorkspace.shared.menuBarOwningApplication
        }
    }

    /// What the window shows after an action, once it has had a moment to change.
    private func after(_ done: String, wait: Duration = .milliseconds(800)) async -> ToolOutput {
        try? await Task.sleep(for: wait)
        guard let app = await targetApp(named: nil) else { return ToolOutput(done) }
        return ToolOutput(done + "\n\n" + reader.snapshot(of: app))
    }

    private func activateTarget() async {
        let pid = reader.pid
        await MainActor.run {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        try? await Task.sleep(for: .milliseconds(150))
    }

    // MARK: Mouse

    private func click(_ id: Int, double: Bool) async -> ToolOutput {
        guard let item = reader.items[id] else {
            return ToolOutput("[\(id)] yok. Önce look_at_screen ile yeniden bak.", isError: true)
        }
        await activateTarget()
        let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
        await OptikPointer.shared.click(at: point)
        if double {
            RealMouse.click(at: point, count: 2)
        } else if !Self.press(item) {
            RealMouse.click(at: point, count: 1)
        }
        return await after("Tıklandı: [\(id)].")
    }

    /// Presses through Accessibility; false when the element can't be pressed that way.
    private static func press(_ item: ScreenReader.Item) -> Bool {
        if ["AXTextField", "AXTextArea", "AXComboBox"].contains(item.role) {
            return AXUIElementSetAttributeValue(item.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
        }
        let actions = ScreenReader.actions(of: item.element)
        guard actions.contains(kAXPressAction as String) else { return false }
        return AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success
    }

    private func scroll(down: Bool) async -> ToolOutput {
        if let target = reader.scrollTarget(down: down),
           AXUIElementPerformAction(target, "AXScrollToVisible" as CFString) == .success {
            return await after(down ? "Aşağı kaydırıldı." : "Yukarı kaydırıldı.", wait: .milliseconds(400))
        }
        let window = reader.window
        guard window != .zero else { return ToolOutput("Kaydırılacak pencere yok. Önce look_at_screen.", isError: true) }
        let point = CGPoint(x: window.midX, y: window.midY)
        await OptikPointer.shared.move(to: point)
        RealMouse.scroll(at: point, lines: down ? -12 : 12, pid: reader.pid)
        return await after(down ? "Aşağı kaydırıldı." : "Yukarı kaydırıldı.", wait: .milliseconds(400))
    }

    // MARK: Keyboard

    private func type(_ text: String, into id: Int?, replace: Bool, submit: Bool) async -> ToolOutput {
        if let id {
            guard let item = reader.items[id] else {
                return ToolOutput("[\(id)] yok. Önce look_at_screen ile yeniden bak.", isError: true)
            }
            if Self.isSecure(item.element) { return ToolOutput("Bu bir şifre alanı, Optik şifre yazmaz.", isError: true) }
            await activateTarget()
            let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
            await OptikPointer.shared.click(at: point)
            if !Self.press(item) { RealMouse.click(at: point, count: 1) }
            try? await Task.sleep(for: .milliseconds(200))
        } else {
            await activateTarget()
        }
        if let focused = Self.focusedElement(), Self.isSecure(focused) {
            return ToolOutput("Odaktaki alan bir şifre alanı, Optik şifre yazmaz.", isError: true)
        }
        if replace { Keyboard.press("cmd+a") }
        Keyboard.type(text)
        if submit { Keyboard.press("enter") }
        return await after(submit ? "Yazıldı ve gönderildi." : "Yazıldı.", wait: .milliseconds(submit ? 1200 : 300))
    }

    private func press(_ keys: String) async -> ToolOutput {
        await activateTarget()
        guard Keyboard.press(keys) else { return ToolOutput("Bu tuşu tanımıyorum: \(keys)", isError: true) }
        return await after("Basıldı: \(keys).")
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        ScreenReader.attribute("AXSubrole", of: element) as? String == "AXSecureTextField"
    }

    private static func focusedElement() -> AXUIElement? {
        ScreenReader.element(kAXFocusedUIElementAttribute, of: AXUIElementCreateSystemWide())
    }

    // MARK: Apps and pages

    private func openURL(_ url: URL, browser: String?) async -> ToolOutput {
        let name = await MainActor.run {
            browser.flatMap { LocalActionRunner.shared.parser.appName($0.lowercased(with: Locale(identifier: "tr_TR"))) }
        }
        _ = await LocalActionRunner.shared.run(.openSite(url, browser: name))
        return await after("Açıldı: \(url.host() ?? url.absoluteString).", wait: .milliseconds(1800))
    }

    private func openApp(_ name: String) async -> ToolOutput {
        let app = await MainActor.run {
            LocalActionRunner.shared.parser.appName(name.lowercased(with: Locale(identifier: "tr_TR")))
        }
        guard let app else { return ToolOutput("\(name) adında bir uygulama bulamadım.", isError: true) }
        let outcome = await LocalActionRunner.shared.run(.openApp(app))
        guard outcome.succeeded else { return ToolOutput(outcome.text, isError: true) }
        return await after(outcome.text + ".", wait: .milliseconds(1500))
    }
}

/// The user's own mouse, only when Accessibility can't do the job: it jumps there,
/// clicks, and goes straight back to where the user left it.
enum RealMouse {
    static func click(at point: CGPoint, count: Int) {
        let saved = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        CGWarpMouseCursorPosition(point)
        for click in 1...count {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                event?.post(tap: .cghidEventTap)
            }
            usleep(60_000)
        }
        if let saved {
            usleep(30_000)
            CGWarpMouseCursorPosition(saved)
        }
    }

    /// A scroll wheel event sent to the app itself, at a point in its window.
    static func scroll(at point: CGPoint, lines: Int32, pid: pid_t) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
        else { return }
        event.location = point
        event.postToPid(pid)
    }
}

/// Typing and shortcuts, sent to the app in front.
enum Keyboard {
    private static let codes: [String: CGKeyCode] = [
        "enter": 36, "return": 36, "tab": 48, "space": 49, "backspace": 51, "delete": 117, "esc": 53, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126, "pageup": 116, "pagedown": 121, "home": 115, "end": 119,
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
        "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        ",": 43, ".": 47, "/": 44, "-": 27, "=": 24, "[": 33, "]": 30, ";": 41, "'": 39,
    ]
    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "shift": .maskShift, "alt": .maskAlternate,
        "option": .maskAlternate, "opt": .maskAlternate, "ctrl": .maskControl, "control": .maskControl, "fn": .maskSecondaryFn,
    ]

    /// "cmd+shift+g", "enter". False for a key it doesn't know.
    @discardableResult
    static func press(_ combination: String) -> Bool {
        let parts = combination.lowercased().replacingOccurrences(of: " ", with: "").split(separator: "+").map(String.init)
        guard let keyName = parts.last, let code = codes[keyName] else { return false }
        var flags: CGEventFlags = []
        for part in parts.dropLast() {
            guard let flag = modifiers[part] else { return false }
            flags.insert(flag)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        usleep(20_000)
        return true
    }

    /// Types text as it is, whatever the keyboard layout, a few letters per event.
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.offset > 0 { press("shift+enter") }
            var units = Array(String(line.element).utf16)[...]
            while !units.isEmpty {
                let chunk = Array(units.prefix(12))
                units = units.dropFirst(12)
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                    event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                    event?.post(tap: .cghidEventTap)
                }
                usleep(12_000)
            }
        }
    }
}
