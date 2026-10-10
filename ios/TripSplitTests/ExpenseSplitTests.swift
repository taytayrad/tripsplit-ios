import Foundation
import Testing
@testable import TripSplit

/// Expense details › split rows (Figma Expense details D1, D2).
struct ExpenseSplitTests {
    static let you = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let atish = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let tyler = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let order = [tyler, you, atish]

    static func expense(_ kind: SplitKind, payer: UUID, amount: Int, _ shares: [(UUID, Int, Decimal?)]) -> Expense {
        Expense(id: UUID(), tripId: UUID(), description: "Stay", icon: .lodging, amountCents: amount, payerId: payer,
                splitKind: kind, spentOn: "2026-10-03", createdBy: payer, createdAt: .now,
                expenseShares: shares.map { ExpenseShare(userId: $0.0, shareCents: $0.1, splitInput: $0.2) })
    }

    @Test func equalSplitOthersPaid() {
        let e = Self.expense(.equal, payer: Self.tyler, amount: 6000, [(Self.you, 2000, nil), (Self.atish, 2000, nil), (Self.tyler, 2000, nil)])
        #expect(ExpenseSplit.header(e) == "SPLIT EQUALLY · 3 PEOPLE")
        #expect(ExpenseSplit.rows(e, me: Self.you, order: Self.order) == [
            .init(userId: Self.you, label: "You owe", cents: 2000, tone: .owe, caption: nil),
            .init(userId: Self.tyler, label: "Gets back", cents: 4000, tone: .owed, caption: "Paid $60"),
            .init(userId: Self.atish, label: "Owes", cents: 2000, tone: .owe, caption: nil),
        ])
    }

    @Test func equalSplitYouPaid() {
        let e = Self.expense(.equal, payer: Self.you, amount: 6000, [(Self.you, 2000, nil), (Self.atish, 2000, nil), (Self.tyler, 2000, nil)])
        let rows = ExpenseSplit.rows(e, me: Self.you, order: Self.order)
        #expect(rows.first == .init(userId: Self.you, label: "You lent", cents: 4000, tone: .owed, caption: "Paid $60"))
        #expect(rows.dropFirst().map(\.label) == ["Owes", "Owes"])
    }

    @Test func payerOutsideAnExactSplit() {
        let e = Self.expense(.exact, payer: Self.tyler, amount: 6000, [(Self.you, 4000, nil), (Self.atish, 2000, nil)])
        #expect(ExpenseSplit.header(e) == "SPLIT EXACTLY · 2 PEOPLE")
        #expect(ExpenseSplit.rows(e, me: Self.you, order: Self.order) == [
            .init(userId: Self.you, label: "You owe", cents: 4000, tone: .owe, caption: nil),
            .init(userId: Self.tyler, label: "Gets back", cents: 6000, tone: .owed, caption: "Paid $60 · not in the split"),
            .init(userId: Self.atish, label: "Owes", cents: 2000, tone: .owe, caption: nil),
        ])
    }

    @Test func percentAndSharesCaptions() {
        let p = Self.expense(.percent, payer: Self.atish, amount: 5000, [(Self.you, 2000, 40), (Self.atish, 3000, 60)])
        #expect(ExpenseSplit.rows(p, me: Self.you, order: Self.order).map(\.caption) == ["40%", "Paid $50 · 60%"])
        let s = Self.expense(.shares, payer: Self.atish, amount: 3000, [(Self.you, 1000, 1), (Self.atish, 2000, 2)])
        #expect(ExpenseSplit.header(s) == "SPLIT BY SHARES · 2 PEOPLE")
        #expect(ExpenseSplit.rows(s, me: Self.you, order: Self.order).map(\.caption) == ["1 share", "Paid $30 · 2 shares"])
    }

    @Test func yourOwnCost() {
        let e = Self.expense(.equal, payer: Self.you, amount: 1200, [(Self.you, 1200, nil)])
        #expect(ExpenseSplit.header(e) == "SPLIT EQUALLY · 1 PERSON")
        #expect(ExpenseSplit.rows(e, me: Self.you, order: Self.order) == [
            .init(userId: Self.you, label: "You paid", cents: 1200, tone: .neutral, caption: "Paid $12"),
        ])
    }
}
