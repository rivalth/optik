import Foundation
import Testing
@testable import OptikCore

struct MoodTests {
    /// `Packages/OptikCore/Tests/OptikCoreTests/<file>` -> repo root.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func sevenMoodsInDesignOrder() {
        #expect(Mood.allCases.map(\.rawValue) == [
            "bekliyor", "mutlu", "dinliyor", "dusunceli", "uyari", "kutlama", "uykulu",
        ])
    }

    @Test(arguments: Mood.allCases)
    func everyMoodHasAPoseFile(mood: Mood) {
        let url = Self.repoRoot.appending(path: "assets/karakter/svg/optik-\(mood.rawValue).svg")
        #expect(FileManager.default.fileExists(atPath: url.path), "missing \(url.lastPathComponent)")
    }

    @Test(arguments: Mood.allCases)
    func everyMoodClassExistsInCSS(mood: Mood) throws {
        let css = try String(contentsOf: Self.repoRoot.appending(path: "assets/animasyon/optik.css"), encoding: .utf8)
        // bekliyor is the class-less default.
        if mood != .waiting {
            #expect(css.contains(".optik.\(mood.rawValue) "), "no CSS rules for \(mood.rawValue)")
        }
    }

    @Test func soundsMatchDesignTable() {
        #expect(Mood.waiting.sound == .tik)
        #expect(Mood.alert.sound == .uyari)
        #expect(Mood.allCases.filter { $0 != .waiting }.allSatisfy { $0.sound.rawValue == $0.rawValue })
    }

    @Test func onlyCelebratingIsTransient() {
        #expect(Mood.allCases.filter(\.isTransient) == [.celebrating])
    }
}

struct SoundEffectTests {
    @Test func effectsMatchFilesOnDisk() throws {
        let folder = MoodTests.repoRoot.appending(path: "assets/sesler")
        let wavs = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".wav") }
            .sorted()
        #expect(wavs == SoundEffect.allCases.map(\.fileName).sorted())
    }

    /// Reads the `data` chunk of each 44.1 kHz, 16 bit, mono WAV.
    @Test(arguments: SoundEffect.allCases)
    func durationMatchesFile(effect: SoundEffect) throws {
        let url = MoodTests.repoRoot.appending(path: "assets/sesler/\(effect.fileName)")
        let bytes = [UInt8](try Data(contentsOf: url))
        func uint32(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 }
        var offset = 12
        var dataSize: Int?
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
            let size = uint32(offset + 4)
            if id == "data" { dataSize = size; break }
            offset += 8 + size + (size & 1)
        }
        let seconds = Double(try #require(dataSize)) / (44_100 * 2)
        #expect(abs(seconds - effect.duration) < 0.006, "\(effect): \(seconds) s")
    }
}

struct RGBAHexStringTests {
    @Test func parsesWithAndWithoutHash() {
        #expect(RGBA(hexString: "#7C9BFF") == RGBA(hex: 0x7C9BFF))
        #expect(RGBA(hexString: "f25f8b") == RGBA(hex: 0xF25F8B))
    }

    @Test(arguments: ["", "#12345", "#1234567", "#GGGGGG", "rgba(0,0,0,1)"])
    func rejectsMalformed(input: String) {
        #expect(RGBA(hexString: input) == nil)
    }

    @Test func roundTripsAccentOptions() {
        for option in DesignTokens.Palette.accentOptions {
            #expect(RGBA(hexString: option.hexString) == option)
        }
    }
}
