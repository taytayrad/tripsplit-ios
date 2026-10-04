import Supabase
import Foundation

// Request bodies. Optional fields are always sent, as null when empty: the database functions need every
// parameter, and clearing a field (dates, a Venmo username) only works if null is sent. Synthesized Encodable
// would silently drop nils.

struct CreateTripArgs: Encodable {
    let p_name: String
    let p_stamp: StampSpec
    let p_start_date: String?
    let p_end_date: String?
    enum CodingKeys: String, CodingKey { case p_name, p_stamp, p_start_date, p_end_date }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_name, forKey: .p_name)
        try c.encode(p_stamp, forKey: .p_stamp)
        try c.encode(p_start_date, forKey: .p_start_date)
        try c.encode(p_end_date, forKey: .p_end_date)
    }
}

struct TripDetailsUpdate: Encodable {
    let name: String
    let start_date: String?
    let end_date: String?
    enum CodingKeys: String, CodingKey { case name, start_date, end_date }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(start_date, forKey: .start_date)
        try c.encode(end_date, forKey: .end_date)
    }
}

struct PayMethodsUpdate: Encodable {
    let venmo_username: String?
    let has_zelle: Bool
    let has_apple_cash: Bool
    enum CodingKeys: String, CodingKey { case venmo_username, has_zelle, has_apple_cash }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(venmo_username, forKey: .venmo_username)
        try c.encode(has_zelle, forKey: .has_zelle)
        try c.encode(has_apple_cash, forKey: .has_apple_cash)
    }
}

struct RemoveMemberArgs: Encodable, Sendable {
    let p_trip: UUID
    let p_user: UUID
    let p_mode: String
}

// supabase-swift's PostgrestResponse isn't Sendable, so AppModel (main actor) can't receive it.
// These run the query off the main actor and hand back only the decoded, Sendable value.
extension PostgrestBuilder {
    func run() async throws { _ = try await execute() }
    func value<T: Decodable & Sendable>() async throws -> T { try await execute().value }
}

struct SplitInput: Encodable, Sendable {
    let user_id: UUID
    let value: Decimal
}

struct SaveExpenseArgs: Encodable, Sendable {
    let p_trip: UUID
    let p_expense_id: UUID?
    let p_description: String
    let p_icon: String
    let p_amount_cents: Int
    let p_payer: UUID
    let p_split_kind: String
    let p_inputs: [SplitInput]
    let p_spent_on: String
    enum CodingKeys: String, CodingKey {
        case p_trip, p_expense_id, p_description, p_icon, p_amount_cents, p_payer, p_split_kind, p_inputs, p_spent_on
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_trip, forKey: .p_trip)
        try c.encode(p_expense_id, forKey: .p_expense_id)  // null for a new expense
        try c.encode(p_description, forKey: .p_description)
        try c.encode(p_icon, forKey: .p_icon)
        try c.encode(p_amount_cents, forKey: .p_amount_cents)
        try c.encode(p_payer, forKey: .p_payer)
        try c.encode(p_split_kind, forKey: .p_split_kind)
        try c.encode(p_inputs, forKey: .p_inputs)
        try c.encode(p_spent_on, forKey: .p_spent_on)
    }
}

struct LogPaymentArgs: Encodable, Sendable {
    let p_other: UUID
    let p_amount_cents: Int
    let p_direction: String
    let p_method: String
    let p_request_id: UUID
}
