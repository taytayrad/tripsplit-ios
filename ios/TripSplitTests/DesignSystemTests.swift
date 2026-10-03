import Testing
import UIKit
@testable import TripSplit

struct DesignSystemTests {
    @Test func everyColorTokenLoads() {
        let names = ["AccentColor", "tsTintFill", "tsDestructive", "tsDestructiveFill", "tsOwe", "tsOwed",
                     "tsOweFill", "tsOwedFill", "tsSecondary"]
            + StampInk.allCases.flatMap { ink in
                let n = "stamp" + ink.rawValue.prefix(1).uppercased() + ink.rawValue.dropFirst()
                return [n, n + "Tint"]
            }
        for name in names { #expect(UIColor(named: name) != nil, "missing color \(name)") }
    }

    @Test(arguments: StampGlyph.allCases)
    func glyphSymbolExists(_ glyph: StampGlyph) {
        #expect(UIImage(systemName: glyph.systemImage) != nil, "missing SF Symbol \(glyph.systemImage)")
    }

    @Test func randomStampsAreNeverCropped() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2_000 { #expect(StampSpec.random(using: &rng).fitsFrame) }
    }

    @Test func worstCaseStampFits() {
        let s = StampSpec(shape: .rounded, glyph: .sun, ink: .blue,
                          rotation: StampSpec.maxRotation, offsetX: StampSpec.maxOffset, offsetY: StampSpec.maxOffset)
        #expect(s.fitsFrame)
    }

    @Test func stampRoundTripsThroughJSON() throws {
        let s = StampSpec.random()
        let decoded = try JSONDecoder().decode(StampSpec.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }
}
