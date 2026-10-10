import Foundation
import Testing
@testable import TripSplit

/// Loaded activity rows, including a deleted trip and a soft-deleted payment, formatted by the statement function.
struct ActivityLoadTests {
    static let you = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let alex = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let connor = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let tyler = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    static let sammy = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    static let jordan = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    static let taylor = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    static let trip = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    static let lyft = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

    static let stamp = #"{"shape":"ticket","glyph":"road","ink":"blue","rotation":-6,"offsetX":0.02,"offsetY":-0.015}"#

    struct Sample: Sendable, CustomTestStringConvertible {
        var note: String
        var json: String
        var statement: String
        var dollar: String? = nil
        var viewerName: String = ""
        var testDescription: String { note }
    }

    static func json(id: String, kind: String, actor: UUID, actorName: String, tripName: String,
                      subject: String? = nil, deltas: String = "{}", expenseId: UUID? = nil,
                      expensePayer: UUID? = nil, expenseAmount: Int? = nil, expensePayerShare: Int? = nil,
                      payment: String? = nil, tripDeletedAt: String? = nil,
                      createdAt: String = "2026-10-10T15:00:00Z") -> String {
        func quoted(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
        func cents(_ value: Int?) -> String { value.map(String.init) ?? "null" }
        return [
            "{\"id\":\"\(id)\"",
            "\"trip_id\":\"\(trip.uuidString.lowercased())\"",
            "\"kind\":\"\(kind)\"",
            "\"actor_id\":\"\(actor.uuidString.lowercased())\"",
            "\"subject\":\(quoted(subject))",
            "\"deltas\":\(deltas)",
            "\"expense_id\":\(quoted(expenseId?.uuidString.lowercased()))",
            "\"expense_payer_id\":\(quoted(expensePayer?.uuidString.lowercased()))",
            "\"expense_amount_cents\":\(cents(expenseAmount))",
            "\"expense_payer_share_cents\":\(cents(expensePayerShare))",
            "\"created_at\":\"\(createdAt)\"",
            "\"actor\":{\"display_name\":\"\(actorName)\"}",
            "\"trips\":{\"name\":\"\(tripName)\",\"stamp\":\(stamp),\"deleted_at\":\(quoted(tripDeletedAt))}",
            "\"payments\":\(payment ?? "null")",
        ].joined(separator: ",") + "}"
    }

    static func payment(payer: UUID, payerName: String, payee: UUID, payeeName: String, cents: Int,
                        deletedAt: String? = nil) -> String {
        let deleted = deletedAt.map { "\"\($0)\"" } ?? "null"
        return [
            "{\"payer_id\":\"\(payer.uuidString.lowercased())\"",
            "\"payee_id\":\"\(payee.uuidString.lowercased())\"",
            "\"amount_cents\":\(cents)",
            "\"deleted_at\":\(deleted)",
            "\"payer\":{\"display_name\":\"\(payerName)\"}",
            "\"payee\":{\"display_name\":\"\(payeeName)\"}",
        ].joined(separator: ",") + "}"
    }

    static func delta(_ pairs: [UUID: Int]) -> String {
        let body = pairs.map { "\"\($0.key.uuidString.lowercased())\":\($0.value)" }.joined(separator: ",")
        return "{\(body)}"
    }

    /// A kind from a newer build decodes as `.unknown` instead of failing the whole load (PR #32 review).
    @Test func anUnknownKindStillDecodes() throws {
        let row = try decode(Self.json(id: "00000000-0000-0000-0000-000000000199", kind: "expense_archived",
                                       actor: Self.alex, actorName: "Alex", tripName: "Coast Road"))
        #expect(row.kind == .unknown)
    }

    func decode(_ json: String) throws -> ActivityEvent {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ActivityEvent.self, from: Data(json.utf8))
    }

    static let samples: [Sample] = [
        .init(note: "trip_created",
              json: json(id: "00000000-0000-0000-0000-000000000101", kind: "trip_created",
                         actor: you, actorName: "Alex Kim", tripName: "Coast Road", subject: "Coast Road"),
              statement: "You created the trip \"Coast Road\""),
        .init(note: "member_joined",
              json: json(id: "00000000-0000-0000-0000-000000000102", kind: "member_joined",
                         actor: alex, actorName: "Alex", tripName: "Coast Road", subject: "Coast Road"),
              statement: "Alex joined \"Coast Road\""),
        .init(note: "expense_added",
              json: json(id: "00000000-0000-0000-0000-000000000103", kind: "expense_added",
                         actor: connor, actorName: "Connor", tripName: "Coast Road", subject: "Airbnb",
                         deltas: delta([you: -3600]), expenseId: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!),
              statement: "Connor added \"Airbnb\" in \"Coast Road\"", dollar: "You owe $36"),
        .init(note: "expense_updated",
              json: json(id: "00000000-0000-0000-0000-000000000104", kind: "expense_updated",
                         actor: tyler, actorName: "Tyler", tripName: "Lake House", subject: "Costco",
                         deltas: delta([you: 11740])),
              statement: "Tyler updated \"Costco\" in \"Lake House\"", dollar: "You get back $117.40"),
        .init(note: "expense_deleted",
              json: json(id: "00000000-0000-0000-0000-000000000105", kind: "expense_deleted",
                         actor: tyler, actorName: "Tyler", tripName: "Lake House", subject: "Costco",
                         deltas: delta([you: 5000]), expenseId: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!),
              statement: "Tyler deleted \"Costco\" in \"Lake House\"", dollar: "You get back $50"),
        .init(note: "payment_logged someone paid you",
              json: json(id: "00000000-0000-0000-0000-000000000106", kind: "payment_logged",
                         actor: sammy, actorName: "Sammy", tripName: "Orlando 2027",
                         deltas: delta([sammy: 51844, you: -51844]),
                         payment: payment(payer: sammy, payerName: "Sammy", payee: you, payeeName: "Alex Kim", cents: 51844)),
              statement: "Sammy paid you in \"Orlando 2027\"", dollar: "You received $518.44"),
        .init(note: "payment_logged you paid",
              json: json(id: "00000000-0000-0000-0000-000000000107", kind: "payment_logged",
                         actor: you, actorName: "Alex Kim", tripName: "Coast Road",
                         deltas: delta([you: 3000, connor: -3000]),
                         payment: payment(payer: you, payerName: "Alex Kim", payee: connor, payeeName: "Connor", cents: 3000)),
              statement: "You paid Connor $30 in \"Coast Road\""),
        .init(note: "payment_logged between others",
              json: json(id: "00000000-0000-0000-0000-000000000108", kind: "payment_logged",
                         actor: tyler, actorName: "Tyler", tripName: "Lake House",
                         deltas: delta([tyler: 3000, connor: -3000]),
                         payment: payment(payer: tyler, payerName: "Tyler", payee: connor, payeeName: "Connor", cents: 3000)),
              statement: "Tyler paid Connor in \"Lake House\""),
        .init(note: "payment_deleted",
              json: json(id: "00000000-0000-0000-0000-000000000109", kind: "payment_deleted",
                         actor: sammy, actorName: "Sammy", tripName: "Orlando 2027",
                         deltas: delta([sammy: -51844, you: 51844]),
                         payment: payment(payer: sammy, payerName: "Sammy", payee: you, payeeName: "Alex Kim", cents: 51844)),
              statement: "Sammy removed a payment in \"Orlando 2027\"", dollar: "You get back $518.44"),
        .init(note: "trip_deleted",
              json: json(id: "00000000-0000-0000-0000-000000000110", kind: "trip_deleted",
                         actor: sammy, actorName: "Sammy", tripName: "Orlando 2027", subject: "Orlando 2027",
                         tripDeletedAt: "2026-10-09T12:00:00Z"),
              statement: "Sammy deleted the trip \"Orlando 2027\""),
        .init(note: "trip_undeleted",
              json: json(id: "00000000-0000-0000-0000-000000000111", kind: "trip_undeleted",
                         actor: sammy, actorName: "Sammy", tripName: "Orlando 2027", subject: "Orlando 2027"),
              statement: "Sammy restored the trip \"Orlando 2027\""),
        .init(note: "member_removed",
              json: json(id: "00000000-0000-0000-0000-000000000112", kind: "member_removed",
                         actor: taylor, actorName: "Taylor", tripName: "Coast Road", subject: "Jordan"),
              statement: "Taylor removed Jordan from \"Coast Road\""),
        .init(note: "member_removed leave",
              json: json(id: "00000000-0000-0000-0000-000000000113", kind: "member_removed",
                         actor: jordan, actorName: "Jordan", tripName: "Coast Road", subject: "Jordan"),
              statement: "Jordan left \"Coast Road\""),
    ]

    @Test(arguments: ActivityLoadTests.samples)
    func formatsTheLoadedRow(_ sample: Sample) throws {
        let event = try decode(sample.json)
        let line = event.statement(viewer: Self.you, viewerName: sample.viewerName, expenses: [])
        #expect(line.statement == sample.statement)
        #expect(line.dollarLine == sample.dollar)
        if sample.note == "trip_deleted" {
            #expect(event.tripDeleted)
            #expect(event.stamp.shape == .ticket)
        }
    }

    @Test func deletedTripRowStillFormats() throws {
        let event = try decode(Self.samples.first { $0.note == "trip_deleted" }!.json)
        #expect(event.tripDeletedAt != nil)
        #expect(event.statement(viewer: Self.you, viewerName: "", expenses: []).statement == "Sammy deleted the trip \"Orlando 2027\"")
    }

    @Test func softDeletedPaymentStillSuppliesTheParties() throws {
        let json = Self.json(id: "00000000-0000-0000-0000-000000000120", kind: "payment_logged",
                             actor: Self.sammy, actorName: "Sammy", tripName: "Orlando 2027",
                             deltas: Self.delta([Self.sammy: 51844, Self.you: -51844]),
                             payment: Self.payment(payer: Self.sammy, payerName: "Sammy", payee: Self.you, payeeName: "Alex Kim",
                                                   cents: 51844, deletedAt: "2026-10-09T12:00:00Z"))
        let event = try decode(json)
        #expect(event.payment?.deletedAt != nil)
        #expect(event.payment?.payerId == Self.sammy)
        #expect(event.payment?.payeeId == Self.you)
        #expect(event.payment?.amountCents == 51844)
        let line = event.statement(viewer: Self.you, viewerName: "", expenses: [])
        #expect(line.statement == "Sammy paid you in \"Orlando 2027\"")
        #expect(line.dollarLine == "You received $518.44")
    }

    @Test func hardDeletedExpenseKeepsTheTitle() throws {
        // No snapshot on this row, so there is no own-cost line. The title is still the event's subject.
        let json = Self.json(id: "00000000-0000-0000-0000-000000000121", kind: "expense_added",
                             actor: Self.you, actorName: "Alex Kim", tripName: "Night Market", subject: "Lyft",
                             expenseId: Self.lyft)
        let event = try decode(json)
        #expect(event.expenseId == Self.lyft)
        let line = event.statement(viewer: Self.you, viewerName: "", expenses: [])
        #expect(line.statement == "You added \"Lyft\" in \"Night Market\"")
        #expect(line.dollarLine == nil)
    }

    /// Adding a $100 expense you paid entirely yourself, then editing it to $200, must leave the original
    /// row at "You paid $100". Both rows are formatted against the expense's current $200 version.
    @Test func laterEditDoesNotRewriteAnEarlierOwnCostLine() throws {
        let live = Expense(id: Self.lyft, tripId: Self.trip, description: "Lyft", icon: .rideshare,
                           amountCents: 20000, payerId: Self.you, splitKind: .equal, spentOn: "2026-10-10",
                           createdBy: Self.you, createdAt: Date(timeIntervalSince1970: 0),
                           expenseShares: [ExpenseShare(userId: Self.you, shareCents: 20000, splitInput: nil)])
        let added = try decode(Self.json(id: "00000000-0000-0000-0000-000000000122", kind: "expense_added",
                                         actor: Self.you, actorName: "Alex Kim", tripName: "Night Market", subject: "Lyft",
                                         expenseId: Self.lyft, expensePayer: Self.you, expenseAmount: 10000, expensePayerShare: 10000))
        let updated = try decode(Self.json(id: "00000000-0000-0000-0000-000000000123", kind: "expense_updated",
                                           actor: Self.you, actorName: "Alex Kim", tripName: "Night Market", subject: "Lyft",
                                           expenseId: Self.lyft, expensePayer: Self.you, expenseAmount: 20000, expensePayerShare: 20000))
        let addedLine = added.statement(viewer: Self.you, viewerName: "", expenses: [live])
        let updatedLine = updated.statement(viewer: Self.you, viewerName: "", expenses: [live])
        #expect(addedLine.statement == "You added \"Lyft\" in \"Night Market\"")
        #expect(addedLine.dollarLine == "You paid $100")
        #expect(updatedLine.dollarLine == "You paid $200")
    }

    @Test func ownCostWithoutASnapshotDoesNotUseTheLiveExpense() throws {
        let json = Self.json(id: "00000000-0000-0000-0000-000000000124", kind: "expense_added",
                             actor: Self.you, actorName: "Alex Kim", tripName: "Night Market", subject: "Lyft",
                             expenseId: Self.lyft)
        let live = Expense(id: Self.lyft, tripId: Self.trip, description: "Lyft", icon: .rideshare,
                           amountCents: 10000, payerId: Self.you, splitKind: .equal, spentOn: "2026-10-10",
                           createdBy: Self.you, createdAt: Date(timeIntervalSince1970: 0),
                           expenseShares: [ExpenseShare(userId: Self.you, shareCents: 10000, splitInput: nil)])
        let line = try decode(json).statement(viewer: Self.you, viewerName: "", expenses: [live])
        #expect(line.statement == "You added \"Lyft\" in \"Night Market\"")
        #expect(line.dollarLine == nil)
    }

    @Test func columnsKeepTheFieldsAStatementNeeds() {
        let columns = ActivityQuery.columns
        for field in ["kind", "actor_id", "subject", "deltas", "expense_id", "expense_payer_id", "expense_amount_cents",
                      "expense_payer_share_cents", "stamp", "payer_id", "payee_id", "amount_cents", "deleted_at"] {
            #expect(columns.contains(field))
        }
        #expect(!columns.contains("is.null"))
    }
}
