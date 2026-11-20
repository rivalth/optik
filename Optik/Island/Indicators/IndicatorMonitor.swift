import AppKit
import Carbon.HIToolbox
import IOKit.ps
import OptikCore

/// Watches the Mac for what the island's indicators show and turns each change into
/// an `IslandIndicator`. Every source starts only while its switch in Settings is on,
/// and none of them polls except the clipboard (a counter read twice a second).
@MainActor
final class IndicatorMonitor {
    var onIndicator: ((IslandIndicator) -> Void)?

    private let audio = AudioWatcher()
    private var keyMonitors: [Any] = []
    private var batterySource: CFRunLoopSource?
    private var battery = BatteryNotices()
    private var notificationObservers: [NSObjectProtocol] = []
    private var clipboardTimer: Timer?
    private var clipboardCount = NSPasteboard.general.changeCount
    private var captureWatcher: DispatchSourceFileSystemObject?
    private var captureFolderFiles: Set<String> = []
    private var lastTrack: String?
    private var started: Set<IndicatorKind> = []

    private func isOn(_ kind: IndicatorKind) -> Bool {
        kind.isEnabled(in: .standard)
    }

    /// Starts what is switched on and stops what is off. Called at launch and when
    /// a switch changes.
    func refresh() {
        let wanted = Set(IndicatorKind.allCases.filter(isOn))
        let audioKinds: Set<IndicatorKind> = [.volume, .microphone, .accessory]
        if !wanted.isDisjoint(with: audioKinds) { startAudio() } else { audio.stop() }
        if !wanted.isDisjoint(with: [.brightness, .keyboardLight]) { startKeys() } else { stopKeys() }
        wanted.contains(.battery) ? startBattery() : stopBattery()
        refreshNotifications(track: wanted.contains(.track), input: wanted.contains(.inputSource))
        wanted.contains(.clipboard) ? startClipboard() : stopClipboard()
        wanted.contains(.capture) ? startCaptures() : stopCaptures()
        started = wanted
    }

    private func show(_ indicator: IslandIndicator) {
        guard isOn(indicator.kind) else { return }
        onIndicator?(indicator)
    }

    // MARK: Volume, microphone, headphones

    private func startAudio() {
        audio.onVolume = { [weak self] level, muted in
            self?.show(IslandIndicator(kind: .volume, symbol: IslandIndicator.volumeSymbol(level: level, muted: muted),
                                       level: muted ? 0 : level))
        }
        audio.onMicrophone = { [weak self] on in
            self?.show(IslandIndicator(kind: .microphone, symbol: on ? "mic.fill" : "mic.slash.fill",
                                       trailing: on ? String(localized: "Açık") : String(localized: "Kapalı"), isWarning: !on))
        }
        audio.onAccessory = { [weak self] name, connected in
            let detail = connected ? String(localized: "\(name) bağlandı") : String(localized: "\(name) ayrıldı")
            self?.show(IslandIndicator(kind: .accessory, symbol: Self.accessorySymbol(for: name), detail: detail))
        }
        audio.start()
    }

    private static func accessorySymbol(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("beats") { return "beats.headphones" }
        if lowered.contains("tv") || lowered.contains("homepod") { return "hifispeaker.fill" }
        return "headphones"
    }

    // MARK: Brightness and keyboard light keys

    /// The brightness and keyboard light keys arrive as "system defined" events;
    /// the value is read right after the system has applied it.
    private func startKeys() {
        guard keyMonitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let code = (event.data1 & 0xFFFF_0000) >> 16
            let isDown = ((event.data1 & 0xFF00) >> 8) == 0x0A
            guard isDown else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(70))
                self?.mediaKeyPressed(code)
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined, handler: handler) { keyMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .systemDefined, handler: { handler($0); return $0 }) {
            keyMonitors.append(local)
        }
    }

    private func stopKeys() {
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors = []
    }

    /// NX_KEYTYPE_BRIGHTNESS_UP/DOWN (2, 3) and NX_KEYTYPE_ILLUMINATION_UP/DOWN (21, 22).
    private func mediaKeyPressed(_ code: Int) {
        switch code {
        case 2, 3:
            guard let level = SystemLevels.displayBrightness() else { return }
            show(IslandIndicator(kind: .brightness, symbol: level < 0.5 ? "sun.min.fill" : "sun.max.fill", level: level))
        case 21, 22:
            let level = SystemLevels.keyboardBrightness()
            show(IslandIndicator(kind: .keyboardLight, symbol: (level ?? 1) > 0.01 ? "light.max" : "light.min", level: level))
        default:
            break
        }
    }

    // MARK: Battery

    private func startBattery() {
        guard batterySource == nil else { return }
        _ = battery.update(Self.batteryReading() ?? .init(level: 1, isOnPower: true, isCharging: false))
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<IndicatorMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.batteryChanged() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        batterySource = source
    }

    private func stopBattery() {
        guard let batterySource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .defaultMode)
        self.batterySource = nil
    }

    private func batteryChanged() {
        guard let reading = Self.batteryReading(), let notice = battery.update(reading) else { return }
        let percent = IslandIndicator.percent(reading.level)
        switch notice {
        case .pluggedIn(let level):
            show(IslandIndicator(kind: .battery, symbol: "battery.100percent.bolt", level: level, trailing: percent))
        case .unplugged(let level):
            show(IslandIndicator(kind: .battery, symbol: IslandIndicator.batterySymbol(level: level, charging: false),
                                 level: level, trailing: percent))
        case .low(let level):
            show(IslandIndicator(kind: .battery, symbol: IslandIndicator.batterySymbol(level: level, charging: false),
                                 level: level, trailing: percent, detail: String(localized: "Pil azaldı, şarja tak"), isWarning: true))
        case .full:
            show(IslandIndicator(kind: .battery, symbol: "battery.100percent", level: 1, trailing: percent,
                                 detail: String(localized: "Pil doldu")))
        }
    }

    private static func batteryReading() -> BatteryNotices.Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let onPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            return .init(level: Double(current) / Double(maximum), isOnPower: onPower, isCharging: charging)
        }
        return nil
    }

    // MARK: Songs and keyboard language

    private func refreshNotifications(track: Bool, input: Bool) {
        let center = DistributedNotificationCenter.default()
        notificationObservers.forEach(center.removeObserver)
        notificationObservers = []
        if track {
            // Spotify and Music announce every change of song to the whole system.
            for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
                notificationObservers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                    let info = note.userInfo ?? [:]
                    let state = info["Player State"] as? String
                    let title = info["Name"] as? String
                    let artist = info["Artist"] as? String
                    let id = (info["Track ID"] as? String) ?? (info["PersistentID"].map { "\($0)" })
                    MainActor.assumeIsolated { self?.trackChanged(title: title, artist: artist, id: id, playing: state == "Playing") }
                })
            }
        }
        if input {
            let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
            notificationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.inputSourceChanged() }
            })
        }
    }

    private func trackChanged(title: String?, artist: String?, id: String?, playing: Bool) {
        guard playing, let title, !title.isEmpty else { return }
        let key = id ?? title + (artist ?? "")
        guard key != lastTrack else { return }
        lastTrack = key
        let detail = [title, artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        show(IslandIndicator(kind: .track, symbol: "music.note", detail: detail))
    }

    private func inputSourceChanged() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        func property(_ key: CFString) -> AnyObject? {
            guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        }
        let name = property(kTISPropertyLocalizedName) as? String ?? ""
        let language = (property(kTISPropertyInputSourceLanguages) as? [String])?.first ?? ""
        show(IslandIndicator(kind: .inputSource, symbol: "keyboard", trailing: language.uppercased().prefix(3).description,
                             detail: name))
    }

    // MARK: Clipboard

    private func startClipboard() {
        guard clipboardTimer == nil else { return }
        clipboardCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkClipboard() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        clipboardTimer = timer
    }

    private func stopClipboard() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    /// Password managers mark what they copy; that is never shown.
    private static let privateTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
    ]

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != clipboardCount else { return }
        clipboardCount = pasteboard.changeCount
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: Self.privateTypes) else { return }
        let detail: String
        let symbol: String
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first {
            symbol = "doc.on.doc.fill"
            detail = url.lastPathComponent
        } else if types.contains(NSPasteboard.PasteboardType.png.rawValue) || types.contains(NSPasteboard.PasteboardType.tiff.rawValue) {
            symbol = "photo.on.rectangle"
            detail = String(localized: "Görsel")
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            symbol = "doc.on.clipboard.fill"
            detail = IslandIndicator.clipboardPreview(text)
        } else {
            return
        }
        show(IslandIndicator(kind: .clipboard, symbol: symbol, trailing: String(localized: "Kopyalandı"), detail: detail))
    }

    // MARK: Screenshots

    /// Where screenshots go: the user's choice in the Screenshot app, or the Desktop.
    private static var captureFolder: URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop")
    }

    private func startCaptures() {
        guard captureWatcher == nil else { return }
        let folder = Self.captureFolder
        captureFolderFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.captureFolderChanged(folder) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        captureWatcher = source
    }

    private func stopCaptures() {
        captureWatcher?.cancel()
        captureWatcher = nil
    }

    private func captureFolderChanged(_ folder: URL) {
        let files = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let added = files.subtracting(captureFolderFiles)
        captureFolderFiles = files
        // Screenshots start with the system's own name for them, in Turkish or English.
        let prefixes = ["Ekran Resmi", "Ekran Görüntüsü", "Ekran Kaydı", "Screenshot", "Screen Shot", "Screen Recording"]
        guard let file = added.first(where: { name in !name.hasPrefix(".") && prefixes.contains { name.hasPrefix($0) } }) else { return }
        let isVideo = file.hasSuffix(".mov") || file.hasSuffix(".mp4")
        show(IslandIndicator(kind: .capture, symbol: isVideo ? "record.circle" : "camera.viewfinder",
                             trailing: String(localized: "Kaydedildi")))
    }
}
