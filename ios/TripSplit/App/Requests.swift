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
