import Foundation
import Testing
@testable import TripSplit

/// The words on a Trips boarding pass (TRIP-38).
struct TripCardTextTests {
    @Test func subtitle() {
        let start = DayFormat.parse("2026-10-03")!, end = DayFormat.parse("2026-10-06")!
        #expect(TripCardText.subtitle(start: start, end: end, memberCount: 3) == "Oct 3 – 6 · 3 members")
        #expect(TripCardText.subtitle(start: nil, end: nil, memberCount: 3) == "3 members")
        #expect(TripCardText.subtitle(start: nil, end: nil, memberCount: 1) == "1 member")
    }

    @Test func stubLabel() {
        #expect(TripCardText.label(netCents: -3000) == "You owe")
        #expect(TripCardText.label(netCents: 800) == "You’re owed")
        #expect(TripCardText.label(netCents: 0) == nil)  // $0 shows the amount alone
    }
}
