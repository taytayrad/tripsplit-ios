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
    ])
    func shownNameIsFirstNameAndLastInitial(_ stored: String, _ shown: String) {
        #expect(PersonName.shown(stored) == shown)
    }
}
