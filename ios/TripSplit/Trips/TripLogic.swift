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
        URL(string: page.absoluteString + "#" + token)!
    }

    /// The app URL the invite page opens.
    static func appURL(token: String) -> URL { URL(string: "tripsplit://join/\(token)")! }

    /// The invite token from either link form, or nil for anything else.
    static func token(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let token: String?
        if url.scheme == "tripsplit" {
            token = url.host() == "join" ? parts.first : nil
        } else if parts.last == "join" {
            token = url.fragment
        } else {
            token = nil
        }
        guard let token, token.count == 32, token.allSatisfy(\.isHexDigit) else { return nil }
        return token
    }
}
