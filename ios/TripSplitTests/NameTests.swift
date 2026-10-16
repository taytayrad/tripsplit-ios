import Foundation
import Testing
@testable import TripSplit

/// Shown names (PRD › Prototype decisions): first name and last initial. The stored display name is unchanged.
struct NameTests {
    @Test(arguments: [
        ("Atish Dey", "Atish D."),
        ("Atish", "Atish"),
        ("Atish D", "Atish D."),
        ("Atish D.", "Atish D."),
        ("Mary Ann Smith", "Mary S."),
        ("  Atish   Dey  ", "Atish D."),
        ("Deleted account", "Deleted account"),  // TRIP-28: never "Deleted a."
        ("", "Someone"),
        (" \n\t ", "Someone"),
    ])
    func shownNameIsFirstNameAndLastInitial(_ stored: String, _ shown: String) {
        #expect(PersonName.shown(stored) == shown)
    }

    @Test func deletionStatusIsIndependentOfTheName() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fields = #""id":"00000000-0000-0000-0000-000000000028","display_name":"Deleted account","has_zelle":false,"has_apple_cash":false"#
        let alive = try decoder.decode(Profile.self, from: Data(("{" + fields + "}").utf8))
        let deleted = try decoder.decode(Profile.self, from: Data(("{" + fields + #","deleted_at":"2026-10-15T00:00:00Z"}"#).utf8))
        #expect(alive.deletedAt == nil)
        #expect(deleted.deletedAt != nil)
    }
}
