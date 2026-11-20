import Foundation
import os

/// Optik ran in the App Sandbox until 2026-11-20, so its settings and downloaded
/// models live in `~/Library/Containers/<bundle id>/Data`. Without the sandbox the
/// app reads `~/Library`. On the first launch after the change this moves them over
/// once: the settings are copied key by key, the folders are moved (the speech model
/// alone is over a gigabyte, so nothing is downloaded again).
enum ContainerMigration {
    private static let doneKey = "migratedFromSandboxContainer"
    /// Folders under Application Support that Optik and its packages write.
    private static let supportFolders = ["Optik", "FluidAudio"]

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey),
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let log = Logger(subsystem: bundleID, category: "migration")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let container = home.appending(path: "Library/Containers/\(bundleID)/Data/Library", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: container.path) else {
            defaults.set(true, forKey: doneKey)
            return
        }

        // Settings: only keys this launch doesn't have yet.
        let preferences = container.appending(path: "Preferences/\(bundleID).plist")
        if let old = NSDictionary(contentsOf: preferences) as? [String: Any] {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            log.info("copied \(old.count, privacy: .public) settings from the sandbox container")
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for folder in supportFolders {
            let from = container.appending(path: "Application Support/\(folder)", directoryHint: .isDirectory)
            let to = support.appending(path: folder, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) else { continue }
            do {
                try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: from, to: to)
                log.info("moved \(folder, privacy: .public) out of the sandbox container")
            } catch {
                log.error("could not move \(folder, privacy: .public)")
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
