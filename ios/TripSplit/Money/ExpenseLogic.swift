import Foundation

/// The starter icons (PRD › Build decisions › Expense icon). Stored by name in `expenses.icon`.
enum ExpenseIcon: String, CaseIterable, Codable, Sendable {
    case groceries, restaurant, coffee, drinks, gas, rideshare, flight, lodging, tickets, shopping, general

    var symbol: String {
        switch self {
        case .groceries: "cart"
        case .restaurant: "fork.knife"
        case .coffee: "cup.and.saucer"
        case .drinks: "wineglass"
        case .gas: "fuelpump"
        case .rideshare: "car"
        case .flight: "airplane"
        case .lodging: "bed.double"
        case .tickets: "ticket"
        case .shopping: "bag"
        case .general: "dollarsign.circle"
        }
    }

    var title: String { rawValue.capitalized }

    private static let keywords: [(ExpenseIcon, [String])] = [
        (.groceries, ["grocer", "costco", "market", "trader joe", "whole foods", "safeway", "walmart", "aldi", "kroger"]),
        (.coffee, ["coffee", "latte", "starbucks", "cafe", "café", "espresso"]),
        (.drinks, ["drink", "beer", "wine", "cocktail", "brewery", "bar ", "bar"]),
        (.restaurant, ["dinner", "lunch", "breakfast", "brunch", "restaurant", "pizza", "taco", "sushi", "burger", "food", "snack"]),
        (.gas, ["gas", "fuel", "shell", "chevron"]),
        (.rideshare, ["uber", "lyft", "taxi", "cab", "ride", "parking", "toll"]),
        (.flight, ["flight", "airline", "plane", "delta", "united", "southwest", "jetblue"]),
        (.lodging, ["airbnb", "hotel", "vrbo", "cabin", "lodge", "motel", "hostel", "rent", "resort"]),
        (.tickets, ["ticket", "concert", "museum", "park", "show", "game", "tour", "pass"]),
        (.shopping, ["shop", "store", "amazon", "souvenir", "gift"]),
    ]

    /// The icon the description picks. Tapping the icon overrides it, and the override then stays put.
    static func pick(for description: String) -> ExpenseIcon {
        let text = description.lowercased()
        return keywords.first { _, words in words.contains { text.contains($0) } }?.0 ?? .general
    }
}

/// Your line on an expense row: only your part, never a minus (PRD › Trips).
enum ExpenseLine {
    static func text(amountCents: Int, youPaid: Bool, yourShareCents: Int?) -> String? {
        let share = yourShareCents ?? 0
        if youPaid {
            return share == amountCents ? "You paid \(Money.string(amountCents))" : "You lent \(Money.string(amountCents - share))"
        }
        return share > 0 ? "You owe \(Money.string(share))" : nil
    }
}

/// The running total pinned above the keyboard, and whether the split can be saved.
enum SplitFooter {
    struct Result: Equatable { let text: String; let isValid: Bool }

    static func evaluate(kind: SplitKind, amountCents: Int, inputs: [Decimal]) -> Result {
        let included = inputs.filter { $0 > 0 }
        switch kind {
        case .equal:
            guard !included.isEmpty else { return Result(text: "Pick at least one person", isValid: false) }
            let each = (Decimal(amountCents) / Decimal(included.count) / 100)
            return Result(text: "\(each.formatted(.currency(code: "USD"))) per person", isValid: true)
        case .exact:
            let left = amountCents - Int(truncating: included.reduce(0, +) as NSDecimalNumber)
            if left < 0 { return Result(text: "\(Money.string(-left)) over", isValid: false) }
            return Result(text: "\(Money.string(left)) left", isValid: left == 0)
        case .percent:
            let left = 100 - included.reduce(0, +)
            if left < 0 { return Result(text: "\(-left)% over", isValid: false) }
            return Result(text: "\(left)% left", isValid: left == 0)
        case .shares:
            let total = included.reduce(0, +)
            return Result(text: "\(total) share\(total == 1 ? "" : "s")", isValid: total > 0)
        }
    }
}

/// Which trip the form starts on (PRD › Expenses, and Build decisions › Default trip after an invite).
enum DefaultTrip {
    static func choose(justJoined: UUID?, lastUsed: UUID?, tripsNewestFirst: [UUID]) -> UUID? {
        if let justJoined, tripsNewestFirst.contains(justJoined) { return justJoined }
        if let lastUsed, tripsNewestFirst.contains(lastUsed) { return lastUsed }
        return tripsNewestFirst.first
    }
}
