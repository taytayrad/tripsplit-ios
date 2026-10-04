import Foundation

// Phase 4's pure rules (docs/money-rules.md › Balances, Payments). Balances come from the server's pair rows;
// these only group, word, and preview them. The server decides every payment.

/// Your Balance: one row per person, combined across trips, under "You owe" and "Owes you". The header chip is
/// `total`, the sum of the same rows, so the two can't disagree.
struct BalanceSummary: Equatable {
    struct Row: Equatable, Identifiable { let id: UUID; let name: String; let cents: Int }

    let youOwe: [Row]
    let owesYou: [Row]
    let total: Int
    /// Trips behind the listed rows ("Across 3 trips"). Deleted trips have no pair rows.
    let tripCount: Int

    init(pairs: [PairBalance], name: (UUID) -> String) {
        let combined = Dictionary(grouping: pairs, by: \.otherUserId).mapValues { $0.reduce(0) { $0 + $1.cents } }.filter { $0.value != 0 }
        let rows = combined.map { Row(id: $0.key, name: name($0.key), cents: $0.value) }
        youOwe = rows.filter { $0.cents < 0 }.sorted { ($0.cents, $0.name) < ($1.cents, $1.name) }
        owesYou = rows.filter { $0.cents > 0 }.sorted { ($1.cents, $0.name) < ($0.cents, $1.name) }
        total = rows.reduce(0) { $0 + $1.cents }
        tripCount = Set(pairs.filter { $0.cents != 0 && combined[$0.otherUserId] != nil }.map(\.tripId)).count
    }

    /// Your net on each trip: the sum of your pairs on it (money-rules › Pairwise balance).
    static func tripNets(_ pairs: [PairBalance]) -> [UUID: Int] {
        Dictionary(grouping: pairs, by: \.tripId).mapValues { $0.reduce(0) { $0 + $1.cents } }
    }
}

/// A person's screen: a group per shared trip (newest first), each with its net and the lines between the two
/// of you. Charges are signed (+ they owe you); payments are neutral amounts.
struct PersonLedger {
    struct Line: Identifiable, Equatable {
        let id: UUID
        let title: String
        let cents: Int
        let isPayment: Bool
        /// The change to your net with this person.
        let effect: Int
    }

    struct Group: Identifiable, Equatable {
        let id: UUID
        let name: String
        let net: Int
        let lines: [Line]
    }

    let total: Int
    let groups: [Group]
    /// Trips you still have a balance on with this person.
    let openTripCount: Int

    init(me: UUID, other: UUID, otherName: String, tripsNewestFirst: [Trip], expenses: [Expense], payments: [Payment], pairs: [PairBalance]) {
        let mine = pairs.filter { $0.otherUserId == other }
        let nets = BalanceSummary.tripNets(mine)
        total = mine.reduce(0) { $0 + $1.cents }
        openTripCount = Set(mine.filter { $0.cents != 0 }.map(\.tripId)).count
        groups = tripsNewestFirst.filter { trip in trip.tripMembers.contains { $0.userId == other } }.compactMap { trip in
            let charges: [Line] = expenses.filter { $0.tripId == trip.id }.sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }.compactMap { e in
                let cents = e.payerId == me ? e.share(of: other) ?? 0 : e.payerId == other ? -(e.share(of: me) ?? 0) : 0
                return cents == 0 ? nil : Line(id: e.id, title: e.description, cents: cents, isPayment: false, effect: cents)
            }
            let paid: [Line] = payments.filter { $0.tripId == trip.id && Set([$0.payerId, $0.payeeId]) == Set([me, other]) }
                .sorted { $0.createdAt < $1.createdAt }.map { p in
                    let title = (p.payerId == me ? "You paid" : "\(otherName) paid you") + (p.method.title.map { " · \($0)" } ?? "")
                    return Line(id: p.id, title: title, cents: p.amountCents, isPayment: true, effect: p.payerId == me ? p.amountCents : -p.amountCents)
                }
            let net = nets[trip.id] ?? 0
            return charges.isEmpty && paid.isEmpty && net == 0 ? nil : Group(id: trip.id, name: trip.name, net: net, lines: charges + paid)
        }
    }

    /// Settled trips hide behind "Show settled trips", except ones that just reached $0 here (`keep`).
    func visible(showSettled: Bool, keep: Set<UUID>) -> [Group] {
        groups.filter { $0.net != 0 || showSettled || keep.contains($0.id) }
    }

    func hiddenCount(keep: Set<UUID>) -> Int { groups.filter { $0.net == 0 && !keep.contains($0.id) }.count }
}

/// The bottom bar on a person's screen (PRD › Settling).
enum PayBar {
    enum Action: Equatable, Hashable { case venmo(username: String), zelle, appleCash, cash, record }

    /// You owe them: the methods you both have (absent, never disabled), then Cash. They owe you: Record a Payment.
    /// Settled: nothing.
    static func actions(me: Profile, them: Profile, total: Int) -> [Action] {
        if total > 0 { return [.record] }
        guard total < 0 else { return [] }
        var actions: [Action] = []
        if me.venmoUsername?.nilIfEmpty != nil, let theirs = them.venmoUsername?.nilIfEmpty { actions.append(.venmo(username: theirs)) }
        if me.hasZelle && them.hasZelle { actions.append(.zelle) }
        if me.hasAppleCash && them.hasAppleCash { actions.append(.appleCash) }
        return actions + [.cash]
    }
}

/// Where a logged amount goes: the trips you owe on (or are owed on), oldest first, each filled before the next.
/// A preview for the log sheet's note; `log_payment` does the real allocation the same way.
enum Allocation {
    struct OpenTrip: Equatable { let id: UUID; let name: String; let owed: Int; let start: Date?; let created: Date }
    struct Part: Equatable { let tripId: UUID; let name: String; let cents: Int; let paysOff: Bool }

    /// Nil when the amount is $0 or more than everything owed (no overpaying).
    static func plan(_ cents: Int, across trips: [OpenTrip]) -> [Part]? {
        guard cents > 0, cents <= trips.reduce(0, { $0 + $1.owed }) else { return nil }
        var left = cents
        return trips.sorted { ($0.start ?? $0.created, $0.created) < ($1.start ?? $1.created, $1.created) }.compactMap { trip in
            guard left > 0 else { return nil }
            let take = min(left, trip.owed)
            left -= take
            return Part(tripId: trip.id, name: trip.name, cents: take, paysOff: take == trip.owed)
        }
    }

    /// "Pays off Lake House ($30) first, then $20 toward Coast Road." Nil when only one trip is touched.
    static func note(_ parts: [Part]) -> String? {
        guard parts.count > 1 else { return nil }
        let paidOff = parts.filter(\.paysOff).map { "\($0.name) (\(Money.string($0.cents)))" }
        let list = paidOff.count > 2 ? paidOff.dropLast().joined(separator: ", ") + ", and " + paidOff.last! : paidOff.joined(separator: " and ")
        guard let partial = parts.last, !partial.paysOff else { return "Pays off \(list)." }
        return "Pays off \(list) first, then \(Money.string(partial.cents)) toward \(partial.name)."
    }
}

/// The Log payment sheet's rules.
enum LogPayment {
    enum Direction { case pay, record }

    /// Why Log is unavailable, or nil when the amount can be logged.
    static func problem(cents: Int?, max: Int, direction: Direction, otherName: String) -> String? {
        guard let cents, cents > 0 else { return "Enter an amount." }
        guard cents > max else { return nil }
        return direction == .pay ? "That’s more than the \(Money.string(max)) you owe \(otherName)."
                                 : "That’s more than the \(Money.string(max)) \(otherName) owes you."
    }
}
