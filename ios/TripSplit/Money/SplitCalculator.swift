import Foundation

// The expense form's live preview. The server (save_expense) computes the saved shares with the same rule;
// both are tested against the split golden cases in docs/money-rules.md.

enum SplitKind: String, Codable, Sendable { case equal, exact, percent, shares }

enum SplitError: Error, Equatable {
    case nobodyIncluded
    case percentagesNot100
    case amountsDontAddUp(remainingCents: Int)
    case notWholeCents
    case sharesNotWhole
}

enum SplitCalculator {
    /// Shares in cents, in member order; `nil` for people not in the split (input 0).
    /// Inputs per kind: equal 1/0, exact cents, percent (two decimals), shares whole counts.
    /// Remainder rule: floor each share, leftover cents to the last included person.
    static func shares(amountCents: Int, kind: SplitKind, inputs: [Decimal]) throws -> [Int?] {
        let included = inputs.indices.filter { inputs[$0] > 0 }
        guard let last = included.last else { throw SplitError.nobodyIncluded }
        let amount = Decimal(amountCents)
        var raw = [Int: Int]()

        switch kind {
        case .equal:
            for i in included { raw[i] = amountCents / included.count }
        case .exact:
            for i in included {
                guard inputs[i] == floored(inputs[i]) else { throw SplitError.notWholeCents }
                raw[i] = int(inputs[i])
            }
            let sum = raw.values.reduce(0, +)
            guard sum == amountCents else { throw SplitError.amountsDontAddUp(remainingCents: amountCents - sum) }
        case .percent:
            guard included.map({ inputs[$0] }).reduce(0, +) == 100 else { throw SplitError.percentagesNot100 }
            for i in included { raw[i] = int(floored(amount * inputs[i] / 100)) }
        case .shares:
            for i in included where inputs[i] != floored(inputs[i]) { throw SplitError.sharesNotWhole }
            let total = included.map { inputs[$0] }.reduce(0, +)
            for i in included { raw[i] = int(floored(amount * inputs[i] / total)) }
        }

        raw[last, default: 0] += amountCents - raw.values.reduce(0, +)
        return inputs.indices.map { raw[$0] }
    }

    private static func floored(_ d: Decimal) -> Decimal {
        var value = d, result = Decimal()
        NSDecimalRound(&result, &value, 0, .down)
        return result
    }

    private static func int(_ d: Decimal) -> Int { NSDecimalNumber(decimal: d).intValue }
}
