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
    static func shareURL(token: String, backend: URL = Backend.url) -> URL {
        backend.appending(path: "functions/v1/invite/\(token)")
    }

    /// The app URL the invite page opens.
    static func appURL(token: String) -> URL { URL(string: "tripsplit://join/\(token)")! }

    /// The invite token from either link form, or nil for anything else.
    static func token(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let token: String?
        if url.scheme == "tripsplit" {
            token = url.host() == "join" ? parts.first : nil
        } else if let i = parts.firstIndex(of: "invite"), i >= 1, parts[i - 1] == "v1", i + 1 < parts.count {
            token = parts[i + 1]
        } else {
            token = nil
        }
        guard let token, token.count == 32, token.allSatisfy(\.isHexDigit) else { return nil }
        return token
    }
}
