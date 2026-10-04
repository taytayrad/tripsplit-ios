import Foundation
import Testing
@testable import TripSplit

/// The expense form's pure rules: the keyword icon, your line on an expense row, the split footer, the default trip.
struct ExpenseLogicTests {
    static func day(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }
    // PRD › Build decisions › Expense icon: keyword match to the starter icons; anything else is general.
    @Test(arguments: [
        ("Costco", ExpenseIcon.groceries), ("Dinner at Nobu", .restaurant), ("Morning coffee", .coffee),
        ("Beers at the brewery", .drinks), ("Gas", .gas), ("Uber to the airport", .rideshare),
        ("Flight home", .flight), ("Airbnb", .lodging), ("Concert tickets", .tickets), ("Souvenirs", .shopping),
        ("Misc", .general), ("", .general), ("Barbecue supplies", .restaurant), ("Bargain bin", .general), ("Bar tab", .drinks),
    ])
    func keywordPicksTheIcon(_ description: String, _ expected: ExpenseIcon) {
        #expect(ExpenseIcon.pick(for: description) == expected)
    }

    @Test func addedLineUsesTodayOrTheDate() {
        let cal = Calendar(identifier: .gregorian)
        let now = Self.day("2026-10-04")
        #expect(ExpenseLine.when(now, now: now, calendar: cal).hasPrefix("Today, "))
        #expect(ExpenseLine.when(Self.day("2026-10-03"), now: now, calendar: cal).hasPrefix("Oct 3, "))
    }

    // PRD › Trips: each expense shows only your part, no leading minus.
    @Test func someoneElsePaidShowsWhatYouOwe() {
        #expect(ExpenseLine.text(amountCents: 8420, youPaid: false, yourShareCents: 2806) == "You owe $28.06")
    }
    @Test func youPaidShowsWhatYouLent() {
        #expect(ExpenseLine.text(amountCents: 8420, youPaid: true, yourShareCents: 2806) == "You lent $56.14")
    }
    @Test func youPaidForOnlyYourself() {
        #expect(ExpenseLine.text(amountCents: 8420, youPaid: true, yourShareCents: 8420) == "You paid $84.20")
    }
    @Test func notInTheSplitAndDidntPay() {
        #expect(ExpenseLine.text(amountCents: 8420, youPaid: false, yourShareCents: nil) == nil)
    }

    // PRD › Prototype decisions › Splits: the running total footer, and when Save is allowed.
    @Test func equalFooterIsTheRoundedAverage() {
        let f = SplitFooter.evaluate(kind: .equal, amountCents: 8420, inputs: [1, 1, 1])
        #expect(f.text == "$28.07 per person" && f.isValid)
    }
    @Test func exactFooterCountsDown() {   // S12
        let f = SplitFooter.evaluate(kind: .exact, amountCents: 8420, inputs: [4000, 4000, 0])
        #expect(f.text == "$4.20 left" && !f.isValid)
    }
    @Test func exactFooterWhenItAddsUp() {  // S11
        let f = SplitFooter.evaluate(kind: .exact, amountCents: 8420, inputs: [4000, 4000, 420])
        #expect(f.text == "$0 left" && f.isValid)
    }
    @Test func exactFooterWhenOver() {
        let f = SplitFooter.evaluate(kind: .exact, amountCents: 8420, inputs: [5000, 5000, 0])
        #expect(f.text == "$15.80 over" && !f.isValid)
    }
    @Test func percentFooter() {            // S7
        let f = SplitFooter.evaluate(kind: .percent, amountCents: 10000, inputs: [50, 49, 0])
        #expect(f.text == "1% left" && !f.isValid)
    }
    @Test func sharesFooterLocksAtZero() {  // S10
        let f = SplitFooter.evaluate(kind: .shares, amountCents: 5000, inputs: [0, 0, 0])
        #expect(f.text == "0 shares" && !f.isValid)
        #expect(SplitFooter.evaluate(kind: .shares, amountCents: 8420, inputs: [2, 1, 1]).text == "4 shares")
    }

    // PRD › Expenses: the trip you just joined, else the last trip you added an expense to, else the newest trip.
    @Test func defaultTripOrder() {
        let a = UUID(), b = UUID(), c = UUID()
        let newestFirst = [c, b, a]
        #expect(DefaultTrip.choose(justJoined: a, lastUsed: b, tripsNewestFirst: newestFirst) == a)
        #expect(DefaultTrip.choose(justJoined: nil, lastUsed: b, tripsNewestFirst: newestFirst) == b)
        #expect(DefaultTrip.choose(justJoined: nil, lastUsed: UUID(), tripsNewestFirst: newestFirst) == c)
        #expect(DefaultTrip.choose(justJoined: nil, lastUsed: nil, tripsNewestFirst: []) == nil)
    }
}
