import AppKit
import OptikCore

/// The user's default browser (Dia, Safari…), for opening the page a reply came from.
@MainActor
enum DefaultBrowser {
    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
    }

    static var name: String {
        guard let url = applicationURL else { return String(localized: "tarayıcı") }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    static var icon: NSImage? {
        applicationURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// "Sayfayı Dia’da açayım mı?"
    static var offer: String {
        let browser = applicationURL == nil ? String(localized: "tarayıcında") : TurkishSuffix.locative(name)
        return String(localized: "Sayfayı \(browser) açayım mı?")
    }

    /// Opens web pages only, never files or other schemes a reply might carry.
    static func open(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return }
        NSWorkspace.shared.open(url)
    }
}
