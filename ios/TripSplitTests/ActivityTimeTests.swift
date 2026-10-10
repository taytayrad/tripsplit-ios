import Foundation
import Testing
@testable import TripSplit

/// Activity timestamps (docs/events.md › Timestamps).
struct ActivityTimeTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    static let locale = Locale(identifier: "en_US")
    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    static func shown(_ date: Date) -> String {
        ActivityTime.string(date, now: Self.date(2026, 10, 10, 15, 0), calendar: calendar, locale: locale)
            .replacingOccurrences(of: "\u{202F}", with: " ")  // the narrow space before AM/PM
    }

    @Test func todayShowsTheTimeOnly() {
        #expect(Self.shown(Self.date(2026, 10, 10, 9, 12)) == "9:12 AM")
        #expect(Self.shown(Self.date(2026, 10, 10, 0, 5)) == "12:05 AM")
    }

    @Test func anEarlierDayShowsAShortDateAndTime() {
        #expect(Self.shown(Self.date(2026, 10, 9, 23, 59)) == "Oct 9, 11:59 PM")
        #expect(Self.shown(Self.date(2026, 10, 1, 18, 40)) == "Oct 1, 6:40 PM")
    }

    @Test func anEarlierYearAddsTheYear() {
        #expect(Self.shown(Self.date(2025, 12, 31, 20, 18)) == "Dec 31, 2025, 8:18 PM")
    }
}
