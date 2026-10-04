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

    /// Whole words, so "barbecue" isn't drinks and "bargain" isn't a bar. Multi-word entries match the phrase.
    private static let keywords: [(ExpenseIcon, [String])] = [
        (.groceries, ["grocery", "groceries", "costco", "market", "supermarket", "trader joe's", "trader joes", "whole foods", "safeway", "walmart", "aldi", "kroger"]),
        (.coffee, ["coffee", "coffees", "latte", "lattes", "starbucks", "cafe", "café", "espresso"]),
        (.drinks, ["drink", "drinks", "beer", "beers", "wine", "cocktail", "cocktails", "brewery", "bar", "bars", "pub"]),
        (.restaurant, ["dinner", "lunch", "breakfast", "brunch", "restaurant", "pizza", "taco", "tacos", "sushi", "burger", "burgers", "food", "snack", "snacks", "bbq", "barbecue"]),
        (.gas, ["gas", "fuel", "shell", "chevron"]),
        (.rideshare, ["uber", "lyft", "taxi", "cab", "ride", "rides", "parking", "toll", "tolls"]),
        (.flight, ["flight", "flights", "airline", "plane", "delta", "united", "southwest", "jetblue"]),
        (.lodging, ["airbnb", "hotel", "vrbo", "cabin", "lodge", "motel", "hostel", "rent", "resort"]),
        (.tickets, ["ticket", "tickets", "concert", "museum", "park", "show", "game", "tour", "pass", "passes"]),
        (.shopping, ["shop", "shopping", "store", "amazon", "souvenir", "souvenirs", "gift", "gifts"]),
    ]

    /// The icon the description picks. Tapping the icon overrides it, and the override then stays put.
    static func pick(for description: String) -> ExpenseIcon {
        let text = description.lowercased()
        let words = Set(text.split { !$0.isLetter && $0 != "'" }.map(String.init))
        return keywords.first { _, keys in
            keys.contains { $0.contains(" ") ? text.contains($0) : words.contains($0) }
        }?.0 ?? .general
    }
}

/// Your line on an expense row: only your part, never a minus (PRD › Trips).
enum ExpenseLine {
    /// "Today, 9:41 AM", or "Oct 3, 10:13 PM" for earlier days (the Activity rule).
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        return calendar.isDate(date, inSameDayAs: now) ? "Today, \(time)" : "\(date.formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }

    struct Part: Equatable { let label: String; let cents: Int }

    /// The label ("You owe", "You lent", "You paid") and the cents it refers to; nil when none of it is yours.
    static func parts(amountCents: Int, youPaid: Bool, yourShareCents: Int?) -> Part? {
        let share = yourShareCents ?? 0
        if youPaid {
            return share == amountCents ? Part(label: "You paid", cents: amountCents) : Part(label: "You lent", cents: amountCents - share)
        }
        return share > 0 ? Part(label: "You owe", cents: share) : nil
    }

    static func text(amountCents: Int, youPaid: Bool, yourShareCents: Int?) -> String? {
        parts(amountCents: amountCents, youPaid: youPaid, yourShareCents: yourShareCents).map { "\($0.label) \(Money.string($0.cents))" }
    }

    /// "Today", or "Oct 2" (the expense row's date).
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now) ? "Today" : date.formatted(.dateTime.month(.abbreviated).day())
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
