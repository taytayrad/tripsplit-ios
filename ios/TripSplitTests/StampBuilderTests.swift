import Testing
@testable import TripSplit

/// The stamp builder's names and edits (TRIP-39).
struct StampBuilderTests {
    @Test func spokenNames() {
        #expect(StampGlyph.allCases.map(\.spokenName) == ["Road", "House", "Shopping", "Plane", "Beach", "Mountains", "Tent", "Sailboat", "Sun"])
        #expect(StampShape.allCases.map(\.spokenName) == ["Ticket", "Circle", "Octagon", "Rounded", "Hexagon", "Postage"])
        #expect(StampInk.allCases.map(\.spokenName) == ["Blue", "Green", "Red", "Purple", "Orange", "Teal"])
        #expect(StampSpec(shape: .circle, glyph: .boat, ink: .teal, rotation: 3, offsetX: 0, offsetY: 0).spokenName == "Sailboat, circle, teal")
    }

    @Test func pickingKeepsTheTiltAndCountsAsAChange() {
        let original = StampSpec(shape: .ticket, glyph: .road, ink: .blue, rotation: -5, offsetX: 0.01, offsetY: -0.02)
        var picked = original
        picked.glyph = .boat
        #expect(picked != original)  // Cancel asks before discarding
        #expect((picked.rotation, picked.offsetX, picked.offsetY) == (original.rotation, original.offsetX, original.offsetY))
    }
}
