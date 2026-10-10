import Foundation
import Testing
@testable import TripSplit

/// Activity search (docs/events.md › Search): a person, an expense title, or a trip name.
struct ActivitySearchTests {
    typealias L = ActivityLoadTests
    let t = ActivityLoadTests()

    // "Connor Reyes added "Airbnb" in "Coast Road"", and "Tyler paid Connor in "Lake House"".
    func airbnb() throws -> ActivityEvent {
        try t.decode(L.json(id: "00000000-0000-0000-0000-000000000201", kind: "expense_added", actor: L.connor,
                            actorName: "Connor Reyes", tripName: "Coast Road", subject: "Airbnb"))
    }
    func payment() throws -> ActivityEvent {
        try t.decode(L.json(id: "00000000-0000-0000-0000-000000000202", kind: "payment_logged", actor: L.tyler,
                            actorName: "Tyler", tripName: "Lake House",
                            payment: L.payment(payer: L.tyler, payerName: "Tyler", payee: L.connor, payeeName: "Connor Reyes", cents: 3000)))
    }

    @Test func matchesTheTripName() throws {
        #expect(try airbnb().matches("coast"))
        #expect(try !payment().matches("coast"))
    }

    @Test func matchesTheExpenseTitle() throws {
        #expect(try airbnb().matches("AIRB"))
    }

    @Test func matchesAPersonAsStoredOrShown() throws {
        #expect(try airbnb().matches("reyes"))
        #expect(try airbnb().matches("Connor R."))
        #expect(try payment().matches("connor"))  // the payee, not the actor
    }

    @Test func hidesARowThatMatchesNothing() throws {
        #expect(try !airbnb().matches("Orlando"))
    }

    @Test func anEmptyQueryShowsEverything() throws {
        #expect(try airbnb().matches(""))
        #expect(try payment().matches("  "))
    }
}
