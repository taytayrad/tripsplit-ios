import Foundation

// Settling up in the net model (docs/money-rules.md › Suggested payments, Payments). The server suggests every
// payment; these only group, word, and split them. The server checks every payment.

/// Which way the money goes, from your side: you pay them, or you record what they paid you.
enum SettleDirection: Hashable { case pay, record }

/// One person on the Settle up page: what you owe them (or they owe you), per trip.
struct SettleTicket: Identifiable, Hashable {
    struct Part: Hashable { let tripId: UUID; let cents: Int }

    let personId: UUID
    let direction: SettleDirection
    /// Each trip's suggested amount, oldest trip first.
    let parts: [Part]

    var id: String { "\(personId)-\(direction)" }
    var cents: Int { parts.reduce(0) { $0 + $1.cents } }
    var tripIds: [UUID] { parts.map(\.tripId) }
}

enum SettleUp {
    /// The tickets for you: one per person and direction, from a trip's suggestions or (with no trip) all of them.
    /// You-owe tickets first, then you-lent; the biggest first within each. Parts follow `tripsOldestFirst`.
    static func tickets(_ settlements: [Settlement], me: UUID, trip: UUID?, tripsOldestFirst: [UUID]) -> [SettleTicket] {
        let order = Dictionary(tripsOldestFirst.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let mine = settlements.filter { ($0.payerId == me || $0.payeeId == me) && (trip == nil || $0.tripId == trip) }
        let groups = Dictionary(grouping: mine) { s in
            s.payerId == me ? TicketKey(person: s.payeeId, direction: .pay) : TicketKey(person: s.payerId, direction: .record)
        }
        return groups.map { key, rows in
            let byTrip = Dictionary(grouping: rows, by: \.tripId).mapValues { $0.reduce(0) { $0 + $1.cents } }
            let parts = byTrip.map { SettleTicket.Part(tripId: $0.key, cents: $0.value) }
                .sorted { (order[$0.tripId] ?? .max, $0.tripId.uuidString) < (order[$1.tripId] ?? .max, $1.tripId.uuidString) }
            return SettleTicket(personId: key.person, direction: key.direction, parts: parts)
        }
        .sorted { a, b in
            if a.direction != b.direction { return a.direction == .pay }
            return (b.cents, a.personId.uuidString) < (a.cents, b.personId.uuidString)
        }
    }

    private struct TicketKey: Hashable { let person: UUID; let direction: SettleDirection }

    /// Every member's net on a trip, from its suggestions: what they're paid minus what they pay. Members not
    /// listed are at $0.
    static func memberNets(trip: UUID, _ settlements: [Settlement]) -> [UUID: Int] {
        var nets: [UUID: Int] = [:]
        for s in settlements where s.tripId == trip {
            nets[s.payerId, default: 0] -= s.cents
            nets[s.payeeId, default: 0] += s.cents
        }
        return nets
    }

    /// Everyone on the trip is at $0.
    static func isSettled(trip: UUID, _ settlements: [Settlement]) -> Bool { !settlements.contains { $0.tripId == trip } }

    /// How `cents` splits across a ticket's trips: oldest first, each filled before the next. Nil when it's $0 or
    /// more than the ticket's total (no overpaying).
    static func split(_ cents: Int, across parts: [SettleTicket.Part]) -> [PaymentPart]? {
        guard cents > 0, cents <= parts.reduce(0, { $0 + $1.cents }) else { return nil }
        var left = cents
        return parts.compactMap { part in
            guard left > 0 else { return nil }
            let take = min(left, part.cents)
            left -= take
            return PaymentPart(trip_id: part.tripId, cents: take)
        }
    }

    /// Trips oldest first, the order a payment fills them: by start date, then created date.
    static func oldestFirst(_ trips: [Trip]) -> [UUID] {
        trips.sorted { ($0.startDate ?? DayFormat.utcString($0.createdAt), $0.createdAt) < ($1.startDate ?? DayFormat.utcString($1.createdAt), $1.createdAt) }
            .map(\.id)
    }
}

/// How a payment can be made on the Payment page.
enum PayOptions {
    /// Paying: the apps you both use (absent, never disabled), then Cash. Recording what they paid you: any method.
    static func methods(direction: SettleDirection, me: Profile?, them: Profile?) -> [PayMethod] {
        guard direction == .pay else { return [.venmo, .zelle, .appleCash, .cash] }
        var methods: [PayMethod] = []
        if me?.venmoUsername?.nilIfEmpty != nil, them?.venmoUsername?.nilIfEmpty != nil { methods.append(.venmo) }
        if me?.hasZelle == true, them?.hasZelle == true { methods.append(.zelle) }
        if me?.hasAppleCash == true, them?.hasAppleCash == true { methods.append(.appleCash) }
        return methods + [.cash]
    }

    /// The method a payment starts on: the first available (cash when recording).
    static func initial(direction: SettleDirection, me: Profile?, them: Profile?) -> PayMethod {
        direction == .record ? .cash : methods(direction: direction, me: me, them: them).first ?? .cash
    }
}

/// The amount check on the Payment page and the Log Payment Sheet.
enum PaymentLimit {
    /// Why the amount can't be logged, or nil when it can.
    static func problem(cents: Int?, max: Int, direction: SettleDirection, otherName: String) -> String? {
        guard max > 0 else { return direction == .pay ? "You don’t owe \(otherName) anything now." : "\(otherName) doesn’t owe you anything now." }
        guard let cents, cents > 0 else { return "Enter an amount." }
        guard cents > max else { return nil }
        return direction == .pay ? "That’s more than the \(Money.string(max)) you owe \(otherName)."
                                 : "That’s more than the \(Money.string(max)) \(otherName) owes you."
    }
}
