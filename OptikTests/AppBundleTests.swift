import AppKit
import Testing
@testable import Optik

/// Runs inside the host app, so it sees the real bundle and registered fonts.
struct AppBundleTests {
    @Test func runsAsMenuBarAgent() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    }

    @Test func developmentLanguageIsTurkish() {
        #expect(Bundle.main.developmentLocalization == "tr")
    }

    @Test(arguments: ["Space Grotesk", "Inter"])
    func bundledFontIsRegistered(family: String) {
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family)
        #expect(members?.isEmpty == false, "\(family) is not registered")
    }

    @Test func menuBarIconIsTemplate() throws {
        let image = try #require(NSImage(named: "MenuBarIcon"))
        #expect(image.isTemplate)
    }
}
