import Foundation
import Testing
@testable import TripSplit

/// What tapping an Activity row opens (TRIP-20).
struct ActivityTargetTests {
    typealias L = ActivityLoadTests
    let t = ActivityLoadTests()
    static let expense = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!

    func event(_ kind: String, expense: UUID? = nil) throws -> ActivityEvent {
        try t.decode(L.json(id: "00000000-0000-0000-0000-000000000301", kind: kind, actor: L.alex, actorName: "Alex",
                            tripName: "Coast Road", subject: "Stay", expenseId: expense))
    }

    @Test(arguments: ["expense_added", "expense_updated", "expense_deleted", "expense_restored"])
    func expenseRowsOpenTheExpense(_ kind: String) throws {
        #expect(try event(kind, expense: Self.expense).target(expenses: [Self.expense], trips: [L.trip]) == .expense(Self.expense))
    }

    @Test func anExpenseDeletedBeforeRestoreExistedOpensNothing() throws {
        #expect(try event("expense_deleted", expense: Self.expense).target(expenses: [], trips: [L.trip]) == nil)
    }

    @Test(arguments: ["trip_created", "trip_undeleted", "member_joined", "member_removed"])
    func tripRowsOpenTheTrip(_ kind: String) throws {
        #expect(try event(kind).target(expenses: [], trips: [L.trip]) == .trip(L.trip))
        #expect(try event(kind).target(expenses: [], trips: []) == nil)  // a trip you can't see now
    }

    /// TRIP-21: a deleted trip's row asks to undelete it; once it's back, the same row opens it.
    @Test func aDeletedTripRowAsksToUndelete() throws {
        let row = try t.decode(L.json(id: "00000000-0000-0000-0000-000000000302", kind: "trip_deleted", actor: L.sammy,
                                      actorName: "Sammy", tripName: "Orlando 2027", tripDeletedAt: "2026-10-09T12:00:00Z"))
        #expect(row.target(expenses: [], trips: []) == .undelete(L.trip))
        let back = try event("trip_deleted")  // the trip's deleted_at is clear again
        #expect(back.target(expenses: [], trips: [L.trip]) == .trip(L.trip))
    }

    @Test(arguments: ["payment_logged", "payment_deleted", "something_new"])
    func otherRowsOpenNothing(_ kind: String) throws {
        #expect(try event(kind, expense: Self.expense).target(expenses: [Self.expense], trips: [L.trip]) == nil)
    }
}
