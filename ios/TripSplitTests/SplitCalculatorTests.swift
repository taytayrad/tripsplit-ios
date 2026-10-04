import Foundation
import Testing
@testable import TripSplit

/// Split golden cases S1–S12 (docs/money-rules.md). The server's save_expense must produce the same shares;
/// supabase/tests/database/001_splits.test.sql checks the same cases there.
struct SplitCalculatorTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let kind: SplitKind
        let cents: Int
        let inputs: [Decimal]
        let expected: [Int?]
        var testDescription: String { name }
    }

    static let valid: [Case] = [
        Case(name: "S1 equal $84.20 in thirds", kind: .equal, cents: 8420, inputs: [1, 1, 1], expected: [2806, 2806, 2808]),
        Case(name: "S2 equal $10.00 in thirds", kind: .equal, cents: 1000, inputs: [1, 1, 1], expected: [333, 333, 334]),
        Case(name: "S3 equal, Jordan unchecked", kind: .equal, cents: 8420, inputs: [1, 1, 0], expected: [4210, 4210, nil]),
        Case(name: "S4 equal $0.01 between two", kind: .equal, cents: 1, inputs: [1, 1, 0], expected: [0, 1, nil]),
        Case(name: "S5 percent 33.33/33.33/33.34", kind: .percent, cents: 10000,
             inputs: [Decimal(string: "33.33")!, Decimal(string: "33.33")!, Decimal(string: "33.34")!], expected: [3333, 3333, 3334]),
        Case(name: "S6 percent 50/50/0", kind: .percent, cents: 1000, inputs: [50, 50, 0], expected: [500, 500, nil]),
        Case(name: "S8 shares 2/1/1", kind: .shares, cents: 8420, inputs: [2, 1, 1], expected: [4210, 2105, 2105]),
        Case(name: "S9 shares 1/1/1", kind: .shares, cents: 10000, inputs: [1, 1, 1], expected: [3333, 3333, 3334]),
        Case(name: "S11 exact amounts", kind: .exact, cents: 8420, inputs: [4000, 4000, 420], expected: [4000, 4000, 420]),
    ]

    @Test(arguments: valid)
    func validSplit(_ c: Case) throws {
        #expect(try SplitCalculator.shares(amountCents: c.cents, kind: c.kind, inputs: c.inputs) == c.expected)
    }

    @Test func s7PercentNot100() {
        #expect(throws: SplitError.percentagesNot100) {
            try SplitCalculator.shares(amountCents: 10000, kind: .percent, inputs: [50, 49, 0])
        }
    }

    @Test func s10SharesTotalZero() {
        #expect(throws: SplitError.nobodyIncluded) {
            try SplitCalculator.shares(amountCents: 5000, kind: .shares, inputs: [0, 0, 0])
        }
    }

    @Test func s12ExactShort() {
        #expect(throws: SplitError.amountsDontAddUp(remainingCents: 420)) {
            try SplitCalculator.shares(amountCents: 8420, kind: .exact, inputs: [4000, 4000, 0])
        }
    }

    @Test func equalNobodyChecked() {
        #expect(throws: SplitError.nobodyIncluded) {
            try SplitCalculator.shares(amountCents: 8420, kind: .equal, inputs: [0, 0, 0])
        }
    }

    @Test func sharesMustBeWhole() {
        #expect(throws: SplitError.sharesNotWhole) {
            try SplitCalculator.shares(amountCents: 1000, kind: .shares, inputs: [Decimal(string: "1.5")!, 1])
        }
    }
}
