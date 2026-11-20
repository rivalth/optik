import AppKit
import ApplicationServices

/// Reads an app's front window through Accessibility into a numbered list Claude
/// can act on ("[12] link "Bayern – Köln""), and keeps the elements behind the
/// numbers for the next click. Works for any app; browsers built on Chromium
/// show their page once asked (`AXManualAccessibility`).
///
/// Not thread-safe; `ComputerControl` calls it from one task at a time, off the
/// main thread.
final class ScreenReader: @unchecked Sendable {
    struct Item {
        let element: AXUIElement
        let role: String
        let frame: CGRect
    }

    /// The elements of the last snapshot, by number.
    private(set) var items: [Int: Item] = [:]
    /// Elements just past the bottom and top of the window, for scrolling a page.
    private var belowPage: AXUIElement?
    private var abovePage: AXUIElement?
    private(set) var window: CGRect = .zero
    private(set) var pid: pid_t = 0

    static let maxItems = 260
    static let maxLabel = 140

    private static let interactive: Set<String> = [
        "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
        "AXComboBox", "AXMenuButton", "AXSlider", "AXMenuItem", "AXDisclosureTriangle", "AXIncrementor",
        "AXSegmentedControl", "AXTab",
    ]
    private static let textual: Set<String> = ["AXStaticText", "AXHeading", "AXImage", "AXCell", "AXRow"]
    private static let roleNames: [String: String] = [
        "AXButton": "button", "AXLink": "link", "AXTextField": "text field", "AXTextArea": "text area",
        "AXCheckBox": "checkbox", "AXRadioButton": "radio", "AXPopUpButton": "menu", "AXComboBox": "combo box",
        "AXMenuButton": "menu button", "AXSlider": "slider", "AXMenuItem": "menu item", "AXHeading": "heading",
        "AXStaticText": "text", "AXImage": "image", "AXCell": "cell", "AXRow": "row", "AXTab": "tab",
        "AXDisclosureTriangle": "disclosure", "AXIncrementor": "stepper", "AXSegmentedControl": "segments",
    ]

    /// A text snapshot of the app's front window.
    func snapshot(of app: NSRunningApplication) -> String {
        pid = app.processIdentifier
        let root = AXUIElementCreateApplication(pid)
        // Chromium apps (browsers, Spotify, Slack) build their page tree on request.
        if AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success,
           !Self.hasWebContent(root) {
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let windowElement = Self.element(kAXFocusedWindowAttribute, of: root)
            ?? (Self.attribute(kAXWindowsAttribute, of: root) as? [AXUIElement])?.first else {
            items = [:]
            return "\(app.localizedName ?? "Uygulama"): açık pencere yok."
        }
        window = Self.frame(of: windowElement) ?? .zero
        items = [:]
        belowPage = nil
        abovePage = nil

        var lines: [String] = []
        let title = Self.attribute(kAXTitleAttribute, of: windowElement) as? String ?? ""
        lines.append("Uygulama: \(app.localizedName ?? "?") · Pencere: \"\(title)\"")
        if let url = Self.pageURL(in: windowElement) { lines.append("Adres: \(url)") }
        if let focused = Self.element(kAXFocusedUIElementAttribute, of: root),
           let role = Self.role(of: focused), Self.interactive.contains(role) {
            lines.append("Odak: \(Self.roleNames[role] ?? role) \"\(Self.label(of: focused) ?? "")\"")
        }

        var count = 0
        var hidden = 0
        var lastText = ""
        /// The last line was plain text at this depth: the next text joins it,
        /// since pages split one sentence into several pieces.
        var textDepth: Int?
        // Depth first, in reading order.
        var stack: [(AXUIElement, Int)] = [(windowElement, 0)]
        var visited = 0
        while let (element, depth) = stack.popLast(), visited < 30_000 {
            visited += 1
            let role = Self.role(of: element) ?? ""
            let frame = Self.frame(of: element)
            let isListed = Self.interactive.contains(role) || Self.textual.contains(role)
            if isListed, let frame, frame.width > 1, frame.height > 1 {
                if frame.minY >= window.maxY - 4 {
                    if belowPage == nil || frame.minY < window.maxY + window.height * 0.85 { belowPage = element }
                    hidden += 1
                } else if frame.maxY <= window.minY + 4 {
                    abovePage = element
                    hidden += 1
                } else if frame.intersects(window), count < Self.maxItems {
                    if role == "AXStaticText", textDepth == depth, let piece = Self.plainText(of: element), let last = lines.indices.last,
                       lines[last].count < 400 {
                        // Inside the quotes of the previous text line.
                        lines[last].removeLast()
                        lines[last] += Self.clip(piece) + "\""
                    } else if let line = describe(element, role: role, frame: frame, number: count + 1),
                              line.text != lastText || Self.interactive.contains(role) {
                        count += 1
                        lines.append(String(repeating: " ", count: min(depth / 3, 4)) + line.line)
                        lastText = line.text
                        textDepth = role == "AXStaticText" && line.line.hasSuffix("\"") ? depth : nil
                    }
                }
            }
            // A button or link names itself from its children; their texts are not listed again.
            if Self.interactive.contains(role), role != "AXRow" { continue }
            let children = Self.children(of: element)
            for child in children.reversed() { stack.append((child, depth + 1)) }
        }
        if count == 0 { lines.append("(Pencerede okunabilen öğe yok.)") }
        if count >= Self.maxItems { lines.append("(Liste kısaltıldı.)") }
        if hidden > 0 { lines.append("(Pencerenin dışında \(hidden) öğe daha var, scroll ile görülebilir.)") }
        return lines.joined(separator: "\n")
    }

    private func describe(_ element: AXUIElement, role: String, frame: CGRect, number: Int) -> (line: String, text: String)? {
        var label = Self.label(of: element) ?? ""
        if label.isEmpty, Self.interactive.contains(role) { label = Self.childText(of: element) }
        let value = (Self.attribute(kAXValueAttribute, of: element) as? String) ?? ""
        let placeholder = (Self.attribute("AXPlaceholderValue", of: element) as? String) ?? ""
        let isTextual = Self.textual.contains(role)
        if isTextual, label.isEmpty, value.isEmpty { return nil }
        if role == "AXRow" || role == "AXCell", label.isEmpty, value.isEmpty { return nil }

        items[number] = Item(element: element, role: role, frame: frame)
        var line = "[\(number)] \(Self.roleNames[role] ?? role)"
        let text = Self.clip(label.isEmpty && role == "AXStaticText" ? value : label)
        if !text.isEmpty { line += " \"\(text)\"" }
        if !isTextual || role == "AXCell" {
            if !value.isEmpty, value != label { line += " = \"\(Self.clip(value))\"" }
            if !placeholder.isEmpty, value.isEmpty { line += " (ipucu: \"\(Self.clip(placeholder))\")" }
        }
        if Self.attribute("AXSubrole", of: element) as? String == "AXSecureTextField" { line += " (şifre)" }
        if Self.attribute(kAXEnabledAttribute, of: element) as? Bool == false { line += " (pasif)" }
        if role == "AXCheckBox" || role == "AXRadioButton", let on = Self.attribute(kAXValueAttribute, of: element) as? Int {
            line += on == 1 ? " (seçili)" : ""
        }
        return (line, text)
    }

    /// The element `ScrollToVisible` brings in for about a page of scrolling.
    func scrollTarget(down: Bool) -> AXUIElement? {
        down ? belowPage : abovePage
    }

    // MARK: Accessibility helpers

    static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ name: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func role(of element: AXUIElement) -> String? {
        attribute(kAXRoleAttribute, of: element) as? String
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(kAXChildrenAttribute, of: element) as? [AXUIElement]) ?? []
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: element),
              let size = attribute(kAXSizeAttribute, of: element),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    static func label(of element: AXUIElement) -> String? {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, "AXLabel", kAXHelpAttribute] {
            if let text = attribute(name, of: element) as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        // A text field's label sits in another element.
        if let title = Self.element(kAXTitleUIElementAttribute, of: element),
           let text = attribute(kAXValueAttribute, of: title) as? String, !text.isEmpty {
            return text
        }
        return nil
    }

    static func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    /// The texts inside a link or button without a name of its own.
    private static func childText(of element: AXUIElement) -> String {
        var parts: [String] = []
        var stack = children(of: element).reversed().map { $0 }
        var visited = 0
        while let node = stack.popLast(), visited < 60, parts.joined().count < maxLabel {
            visited += 1
            if let text = (attribute(kAXValueAttribute, of: node) as? String) ?? label(of: node),
               !text.isEmpty, role(of: node) == "AXStaticText" || role(of: node) == "AXHeading" || role(of: node) == "AXImage" {
                parts.append(text)
            }
            stack.append(contentsOf: children(of: node).reversed())
        }
        return parts.joined(separator: " ")
    }

    private static func pageURL(in window: AXUIElement) -> String? {
        var stack = [window]
        var visited = 0
        while let node = stack.popLast(), visited < 400 {
            visited += 1
            if role(of: node) == "AXWebArea" {
                if let url = attribute("AXURL", of: node) as? URL { return url.absoluteString }
                return nil
            }
            stack.append(contentsOf: children(of: node))
        }
        return nil
    }

    private static func hasWebContent(_ root: AXUIElement) -> Bool {
        var stack = [root]
        var visited = 0
        while let node = stack.popLast(), visited < 300 {
            visited += 1
            if role(of: node) == "AXWebArea" { return !children(of: node).isEmpty }
            stack.append(contentsOf: children(of: node))
        }
        return true
    }

    private static func plainText(of element: AXUIElement) -> String? {
        let text = (attribute(kAXValueAttribute, of: element) as? String) ?? label(of: element) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func clip(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\"", with: "'")
        return flat.count > maxLabel ? String(flat.prefix(maxLabel)) + "…" : flat
    }
}
