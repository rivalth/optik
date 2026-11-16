import Foundation
import Testing
@testable import OptikCore

/// Keeps `DesignTokens` in sync with `assets/tasarim-tokenlari.json`.
@Suite("Design tokens match tasarim-tokenlari.json")
struct DesignTokensTests {
    let json: [String: Any]

    init() throws {
        // Tests/OptikCoreTests/ -> Tests -> OptikCore -> Packages -> repo root
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appending(path: "assets/tasarim-tokenlari.json")
        let data = try Data(contentsOf: url)
        json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func group(_ key: String) throws -> [String: Any] {
        try #require(json[key] as? [String: Any], "missing group \(key)")
    }

    private func color(_ group: String, _ key: String) throws -> RGBA {
        let value = try #require(try self.group(group)[key] as? String, "missing \(group).\(key)")
        return try #require(RGBA(css: value), "unparseable color \(value)")
    }

    private func number(_ dict: [String: Any], _ key: String) throws -> Double {
        try #require((dict[key] as? NSNumber)?.doubleValue, "missing number \(key)")
    }

    @Test func palette() throws {
        let p = DesignTokens.Palette.self
        let expected: [(String, RGBA)] = [
            ("zemin", p.background), ("yuzey", p.surface), ("yuzey2", p.surfaceSecondary),
            ("metin", p.text), ("metinSoluk", p.textMuted), ("cizgi", p.line),
            ("cizgiGuclu", p.lineStrong), ("vurgu", p.accent), ("vurguUstuMetin", p.onAccent),
            ("nane", p.mint), ("uyari", p.warning), ("adacik", p.island),
            ("naneIz", p.mintTrack), ("uyariIz", p.warningTrack),
        ]
        for (key, value) in expected {
            #expect(try color("renk", key) == value, "renk.\(key)")
        }
        let options = try #require(try group("renk")["vurguSecenekleri"] as? [String])
        #expect(options.compactMap(RGBA.init(css:)) == p.accentOptions)
    }

    @Test func characterAndCoop() throws {
        let c = DesignTokens.CharacterPalette.self
        let character: [(String, RGBA)] = [
            ("kabuk", c.shell), ("kabukGolge", c.shellShade), ("benek", c.speck),
            ("catlak", c.crack), ("icDuvar", c.innerWall), ("delik", c.hole), ("goz", c.eye),
        ]
        for (key, value) in character {
            #expect(try color("karakter", key) == value, "karakter.\(key)")
        }
        #expect(try group("karakter")["bacakVeGaga"] as? String == "vurgu")

        let k = DesignTokens.CoopPalette.self
        let coop: [(String, RGBA)] = [
            ("cerceve", k.frame), ("ic", k.inside), ("kanat", k.door), ("saman", k.straw),
        ]
        for (key, value) in coop {
            #expect(try color("kumes", key) == value, "kumes.\(key)")
        }
    }

    @Test func typography() throws {
        let t = DesignTokens.Typography.self
        let yazi = try group("yazi")
        let heading = try #require(yazi["baslik"] as? [String: Any])
        let body = try #require(yazi["metin"] as? [String: Any])
        let sizes = try #require(yazi["boyut"] as? [String: Any])
        #expect(heading["aile"] as? String == t.headingFamily)
        #expect(heading["agirlik"] as? Int == t.headingWeight)
        #expect(body["aile"] as? String == t.bodyFamily)
        #expect(body["agirliklar"] as? [Int] == t.bodyWeights)
        #expect(try number(sizes, "ekranBasligi") == t.screenTitleSize)
        #expect(try number(sizes, "bolumBasligi") == t.sectionTitleSize)
        #expect(try number(sizes, "kartBasligi") == t.cardTitleSize)
        #expect(try number(sizes, "govde") == t.bodySize)
        #expect(try number(sizes, "ikincil") == t.secondarySize)
        #expect(try number(sizes, "etiket") == t.labelSize)
    }

    @Test func radiusSpacingTapTarget() throws {
        let r = try group("kose")
        #expect(try number(r, "kart") == DesignTokens.Radius.card)
        #expect(try number(r, "dugme") == DesignTokens.Radius.button)
        #expect(try number(r, "konusmaBalonu") == DesignTokens.Radius.speechBubble)
        #expect(try number(r, "altCubuk") == DesignTokens.Radius.bottomBar)
        #expect(try number(r, "ilerlemeCubugu") == DesignTokens.Radius.progressBar)

        let s = try group("bosluk")
        #expect(try number(s, "ekranKenari") == DesignTokens.Spacing.screenEdge)
        #expect(try number(s, "kartIci") == DesignTokens.Spacing.cardInner)
        #expect(try number(s, "kartlarArasi") == DesignTokens.Spacing.betweenCards)
        #expect(try number(s, "bolumlerArasi") == DesignTokens.Spacing.betweenSections)

        #expect(try number(json, "dokunmaHedefi") == DesignTokens.minimumTapTarget)
    }

    @Test func island() throws {
        let a = try group("adacik")
        let sizes: [(String, DesignTokens.Island.Size)] = [
            ("bekliyor", DesignTokens.Island.idle),
            ("acik", DesignTokens.Island.open),
            ("yanit", DesignTokens.Island.reply),
        ]
        for (key, size) in sizes {
            let dict = try #require(a[key] as? [String: Any], "adacik.\(key)")
            #expect(try number(dict, "genislik") == size.width, "adacik.\(key).genislik")
            #expect(try number(dict, "yukseklik") == size.height, "adacik.\(key).yukseklik")
            #expect(try number(dict, "altKose") == size.bottomCornerRadius, "adacik.\(key).altKose")
        }
        #expect(try number(a, "gecisSuresiMs") == Double(DesignTokens.Island.transitionMilliseconds))
        #expect(CubicBezier(css: a["gecisEgrisi"] as? String ?? "") == DesignTokens.Island.transitionCurve)
    }

    @Test func motion() throws {
        let h = try group("hareket")
        let m = DesignTokens.Motion.self
        #expect(try number(h, "bicimGecisiMs") == Double(m.shapeTransitionMilliseconds))
        #expect(CubicBezier(css: h["tasanEgri"] as? String ?? "") == m.overshootCurve)
        #expect(try number(h, "dokunmaZiplamasiMs") == Double(m.tapBounceMilliseconds))
        #expect(h["geciciRuhHaliMs"] as? [Int] == [m.transientMoodMilliseconds.lowerBound, m.transientMoodMilliseconds.upperBound])
    }
}

// MARK: - CSS parsing helpers (test-only)

extension RGBA {
    /// Parses `#RRGGBB` or `rgba(r,g,b,a)`.
    init?(css: String) {
        let s = css.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#"), s.count == 7, let hex = UInt32(s.dropFirst(), radix: 16) {
            self.init(hex: hex)
            return
        }
        guard s.hasPrefix("rgba("), s.hasSuffix(")") else { return nil }
        let parts = s.dropFirst(5).dropLast().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4,
              let r = UInt8(parts[0]), let g = UInt8(parts[1]), let b = UInt8(parts[2]),
              let a = Double(parts[3]) else { return nil }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

extension CubicBezier {
    /// Parses `cubic-bezier(.3,1.5,.5,1)`.
    init?(css: String) {
        guard css.hasPrefix("cubic-bezier("), css.hasSuffix(")") else { return nil }
        let values = css.dropFirst(13).dropLast().split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4 else { return nil }
        self.init(values[0], values[1], values[2], values[3])
    }
}
