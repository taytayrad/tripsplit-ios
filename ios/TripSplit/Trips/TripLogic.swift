import Foundation

enum TripVisibility {
    /// A trip hides from the trips list only when it has dates, its end date has passed, and your net is $0.
    /// A trip without dates never hides. (PRD › Decisions › Hiding settled trips)
    static func isHidden(endDate: Date?, netCents: Int, today: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let endDate, netCents == 0 else { return false }
        return calendar.startOfDay(for: endDate) < calendar.startOfDay(for: today)
    }
}

enum InviteLink {
    /// The link people text each other: the invite page, which opens the app (or the App Store).
    /// A static page (`site/join/`), because Supabase's functions domain won't serve HTML. The token is in the
    /// fragment so it never reaches the host.
    static let page = URL(string: "https://taytayrad.github.io/tripsplit-invite/join/")!

    static func shareURL(token: String, page: URL = page) -> URL {
        var c = URLComponents(url: page, resolvingAgainstBaseURL: false)!
        c.fragment = token
        return c.url!
    }

    /// The app URL the invite page opens.
    static func appURL(token: String) -> URL { URL(string: "tripsplit://join/\(token)")! }

    /// The invite token from either link form, or nil for anything else.
    static func token(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let token: String?
        if url.scheme == "tripsplit" {
            token = url.host() == "join" ? parts.first : nil
        } else if url.scheme == "https", url.host() == page.host(), parts == page.pathComponents.filter({ $0 != "/" }) {
            token = url.fragment
        } else {
            token = nil
        }
        guard let token, token.count == 32, token.allSatisfy(\.isHexDigit) else { return nil }
        return token
    }
}

/// A trip's expenses and payments as one list, newest first (PRD › Net model › Trip detail).
enum TripLedger {
    enum Item: Identifiable, Equatable {
        case expense(Expense), payment(Payment)

        var id: UUID {
            switch self { case .expense(let e): e.id; case .payment(let p): p.id }
        }
        /// "yyyy-MM-dd": the day it happened.
        fileprivate var day: String {
            switch self { case .expense(let e): e.spentOn; case .payment(let p): p.paidOn }
        }
        fileprivate var createdAt: Date {
            switch self { case .expense(let e): e.createdAt; case .payment(let p): p.createdAt }
        }
    }

    /// Newest day first; on the same day, the most recently added first.
    static func items(expenses: [Expense], payments: [Payment]) -> [Item] {
        (expenses.map(Item.expense) + payments.map(Item.payment)).sorted { ($0.day, $0.createdAt) > ($1.day, $1.createdAt) }
    }
}

/// A member's amount on Edit trip, in words: "You owe" / "You’re owed" for you, "Owes" / "Gets back" for others,
/// "Settled" at $0. `cents` is their net (positive = owed).
struct MemberAmount: Equatable {
    let cents: Int
    let isYou: Bool

    var label: String {
        if cents == 0 { return "Settled" }
        if isYou { return cents < 0 ? "You owe" : "You’re owed" }
        return cents < 0 ? "Owes" : "Gets back"
    }
}
