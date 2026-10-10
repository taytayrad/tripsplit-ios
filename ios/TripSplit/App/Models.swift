import Foundation

// Rows as the database returns them (docs/data-model.md).

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var venmoUsername: String?
    var hasZelle: Bool
    var hasAppleCash: Bool
    /// Push preferences; only loaded for your own profile (nil reads as on, the column default).
    var notifyPaid: Bool? = nil
    var notifyExpense: Bool? = nil
    var notifyJoin: Bool? = nil
    var notifyTripDeleted: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", venmoUsername = "venmo_username"
        case hasZelle = "has_zelle", hasAppleCash = "has_apple_cash"
        case notifyPaid = "notify_paid", notifyExpense = "notify_expense", notifyJoin = "notify_join"
        case notifyTripDeleted = "notify_trip_deleted"
    }
}

/// A Venmo username as people type it: "@Taylor-R " is "Taylor-R". Valid is 5–30 letters, numbers, - or _.
enum VenmoName {
    static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .filter { !$0.isWhitespace }
    }

    static func isValid(_ name: String) -> Bool {
        (5...30).contains(name.count) && name.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" }
    }
}

struct PersonName: Codable, Hashable {
    let id: UUID
    let displayName: String
    enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }

    /// How a stored display name is shown: the first word, then the last word's initial.
    /// "Atish Dey" → "Atish D."; "Atish" stays "Atish". The stored name is unchanged.
    static func shown(_ displayName: String) -> String {
        let words = displayName.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return "" }
        guard let last = words.dropFirst().last, let initial = last.first else { return first }
        return "\(first) \(initial)."
    }
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
    let createdAt: Date
    var tripMembers: [Member]

    enum CodingKeys: String, CodingKey {
        case id, name, stamp, startDate = "start_date", endDate = "end_date"
        case inviteToken = "invite_token", createdBy = "created_by", createdAt = "created_at", tripMembers = "trip_members"
    }

    /// Active members in member order.
    var members: [Member] { tripMembers.filter { $0.removedAt == nil }.sorted { $0.position < $1.position } }
    var start: Date? { startDate.flatMap(DayFormat.parse) }
    var end: Date? { endDate.flatMap(DayFormat.parse) }
}

/// One suggested payment on a trip (`my_trip_settlements`, docs/money-rules.md › Suggested payments). Every member's
/// net follows from these: what they're paid minus what they pay.
struct Settlement: Codable, Hashable, Sendable {
    let tripId: UUID
    let seq: Int
    let payerId: UUID
    let payeeId: UUID
    let cents: Int
    enum CodingKeys: String, CodingKey { case tripId = "trip_id", seq, payerId = "payer_id", payeeId = "payee_id", cents }
}

/// Your net on one trip (`my_trip_nets`); positive means you're owed. $0 trips are omitted.
struct TripNet: Codable, Hashable, Sendable {
    let tripId: UUID
    let cents: Int
    enum CodingKeys: String, CodingKey { case tripId = "trip_id", cents }
}

enum PayMethod: String, Codable, Sendable {
    case venmo, zelle, appleCash = "apple_cash", cash, recorded

    /// The method on a payment line's caption ("Venmo · Today"); a recorded payment has none.
    var title: String? {
        switch self {
        case .venmo: "Venmo"
        case .zelle: "Zelle"
        case .appleCash: "Apple Cash"
        case .cash: "Cash"
        case .recorded: nil
        }
    }
}

/// A row `log_payment` returns: one per trip in the payment.
struct LoggedPayment: Decodable, Sendable {
    let paymentId: UUID
    let tripId: UUID
    let amountCents: Int
    enum CodingKeys: String, CodingKey { case paymentId = "payment_id", tripId = "trip_id", amountCents = "amount_cents" }
}

struct Payment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let tripId: UUID
    let payerId: UUID
    let payeeId: UUID
    let amountCents: Int
    let method: PayMethod
    /// The day it happened ("yyyy-MM-dd"), set on the Payment page.
    let paidOn: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, method, tripId = "trip_id", payerId = "payer_id", payeeId = "payee_id", amountCents = "amount_cents"
        case paidOn = "paid_on", createdAt = "created_at"
    }
    var date: Date { DayFormat.parse(paidOn) ?? createdAt }
}

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

    private static let utc: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    /// The day a timestamp falls on in UTC, the way Postgres casts `created_at::date` on Supabase.
    static func utcString(_ d: Date) -> String { utc.string(from: d) }

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
}

struct ExpenseShare: Codable, Hashable {
    let userId: UUID
    let shareCents: Int
    let splitInput: Decimal?
    enum CodingKeys: String, CodingKey { case userId = "user_id", shareCents = "share_cents", splitInput = "split_input" }
}

struct Expense: Codable, Identifiable, Hashable {
    let id: UUID
    let tripId: UUID
    var description: String
    var icon: ExpenseIcon
    var amountCents: Int
    var payerId: UUID
    var splitKind: SplitKind
    var spentOn: String
    let createdBy: UUID
    let createdAt: Date
    var expenseShares: [ExpenseShare]
    /// Set when the expense is deleted. It's out of every balance and the trip's list, and can be restored.
    var deletedAt: Date? = nil
    var deletedBy: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id, description, icon, tripId = "trip_id", amountCents = "amount_cents", payerId = "payer_id"
        case splitKind = "split_kind", spentOn = "spent_on", createdBy = "created_by", createdAt = "created_at"
        case expenseShares = "expense_shares", deletedAt = "deleted_at", deletedBy = "deleted_by"
    }

    func share(of user: UUID?) -> Int? { expenseShares.first { $0.userId == user }?.shareCents }
    var date: Date { DayFormat.parse(spentOn) ?? createdAt }
}
