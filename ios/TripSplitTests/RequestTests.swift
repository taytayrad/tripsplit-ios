import Foundation
import Testing
@testable import TripSplit

/// Empty optional fields must reach the server as null (dropped keys break RPC calls and stop clears).
struct RequestTests {
    func json(_ value: some Encodable) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }

    @Test func tripWithoutDatesSendsNullDates() throws {
        let j = try json(CreateTripArgs(p_name: "Coast Road", p_stamp: .random(), p_start_date: nil, p_end_date: nil))
        #expect(j["p_start_date"] is NSNull)
        #expect(j["p_end_date"] is NSNull)
    }

    @Test func removingDatesSendsNull() throws {
        let j = try json(TripDetailsUpdate(name: "Coast Road", start_date: nil, end_date: nil))
        #expect(j["start_date"] is NSNull)
        #expect(j["end_date"] is NSNull)
    }

    @Test func turningOffVenmoClearsTheUsername() throws {
        let j = try json(PayMethodsUpdate(venmo_username: nil, has_zelle: false, has_apple_cash: true))
        #expect(j["venmo_username"] is NSNull)
    }
}
