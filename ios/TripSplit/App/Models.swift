import Foundation

// Rows as the database returns them (docs/data-model.md).

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var venmoUsername: String?
    var hasZelle: Bool
    var hasAppleCash: Bool

    enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", venmoUsername = "venmo_username"
        case hasZelle = "has_zelle", hasAppleCash = "has_apple_cash"
    }
}

struct PersonName: Codable, Hashable {
    let id: UUID
    let displayName: String
    enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }
}

struct Member: Codable, Hashable {
    let userId: UUID
    let position: Int
    let removedAt: Date?
    let profiles: PersonName
    enum CodingKeys: String, CodingKey { case userId = "user_id", position, removedAt = "removed_at", profiles }
}

struct Trip: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var stamp: StampSpec
    var startDate: String?
    var endDate: String?
    let inviteToken: String
    let createdBy: UUID
    var tripMembers: [Member]

    enum CodingKeys: String, CodingKey {
        case id, name, stamp, startDate = "start_date", endDate = "end_date"
        case inviteToken = "invite_token", createdBy = "created_by", tripMembers = "trip_members"
    }

    /// Active members in member order.
    var members: [Member] { tripMembers.filter { $0.removedAt == nil }.sorted { $0.position < $1.position } }
    var start: Date? { startDate.flatMap(DayFormat.parse) }
    var end: Date? { endDate.flatMap(DayFormat.parse) }
}

struct TripNet: Codable { let tripId: UUID; let cents: Int; enum CodingKeys: String, CodingKey { case tripId = "trip_id", cents } }

struct InvitePreview: Codable, Hashable {
    let tripName: String
    let inviterName: String
    let stamp: StampSpec
    enum CodingKeys: String, CodingKey { case tripName = "trip_name", inviterName = "inviter_name", stamp }
}

/// Database `date` columns travel as "yyyy-MM-dd".
enum DayFormat {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func parse(_ s: String) -> Date? { formatter.date(from: s) }
    static func string(_ d: Date) -> String { formatter.string(from: d) }

    /// "Oct 3 – 6", or "Oct 28 – Nov 2".
    static func range(_ start: Date, _ end: Date) -> String {
        let sameMonth = Calendar.current.isDate(start, equalTo: end, toGranularity: .month)
        let s = start.formatted(.dateTime.month(.abbreviated).day())
        let e = sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day())
        return "\(s) – \(e)"
    }
}

enum Money {
    /// "$56.14", "$90", "$0". No sign; callers decide words or signs.
    static func string(_ cents: Int) -> String {
        let value = Decimal(abs(cents)) / 100
        return value.formatted(.currency(code: "USD").precision(.fractionLength(cents % 100 == 0 ? 0 : 2)))
    }
    /// Signed, for the balance chip only: "-$128", "$64", "$0".
    static func signed(_ cents: Int) -> String { (cents < 0 ? "-" : "") + string(cents) }
}
