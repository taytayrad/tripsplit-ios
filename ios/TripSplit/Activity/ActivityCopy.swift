import Foundation

/// One `activity_events.kind`. Raw values match the database check.
enum ActivityKind: String, Codable, Hashable, Sendable {
    case tripCreated = "trip_created"
    case memberJoined = "member_joined"
    case expenseAdded = "expense_added"
    case expenseUpdated = "expense_updated"
    case expenseDeleted = "expense_deleted"
    case paymentLogged = "payment_logged"
    case paymentDeleted = "payment_deleted"
    case tripDeleted = "trip_deleted"
    case tripUndeleted = "trip_undeleted"
    case memberRemoved = "member_removed"
}

/// The Activity statement and dollar line for one event, from who is looking (docs/events.md).
enum ActivityCopy {
    struct Result: Equatable, Sendable {
        var statement: String
        var dollarLine: String?
    }

    /// Everything the wording needs. Money is integer cents. A missing delta is 0: the write drops zeros.
    struct Event: Equatable, Sendable {
        var kind: ActivityKind
        var actorId: UUID
        var actorName: String
        var tripName: String
        /// Expense title, or the removed member's name (`member_removed` stores the name, not the id).
        var subject: String? = nil
        /// Who was removed. When nil, a subject equal to the actor's name is a leave.
        var removedId: UUID? = nil
        var deltas: [UUID: Int] = [:]
        /// Snapshotted on the event. The live expense is not a source: a later edit would rewrite this row.
        var expensePayerId: UUID? = nil
        var expenseAmountCents: Int? = nil
        /// The viewer's share. Nil when they were not in the split.
        var viewerShareCents: Int? = nil
        var payerId: UUID? = nil
        var payeeId: UUID? = nil
        var payerName: String? = nil
        var payeeName: String? = nil
        var amountCents: Int? = nil
    }

    static func line(_ event: Event, viewer: UUID, viewerName: String = "") -> Result {
        Result(statement: statement(event, viewer: viewer, viewerName: viewerName),
               dollarLine: dollarLine(event, viewer: viewer))
    }

    // MARK: Statement

    private static func statement(_ event: Event, viewer: UUID, viewerName: String) -> String {
        let trip = quoted(event.tripName)
        let actor = person(event.actorName, isYou: event.actorId == viewer, leading: true)
        switch event.kind {
        case .tripCreated:
            return "\(actor) created the trip \(trip)"
        case .memberJoined:
            return "\(actor) joined \(trip)"
        case .expenseAdded:
            return "\(actor) added \(quoted(event.subject ?? "")) in \(trip)"
        case .expenseUpdated:
            return "\(actor) updated \(quoted(event.subject ?? "")) in \(trip)"
        case .expenseDeleted:
            return "\(actor) deleted \(quoted(event.subject ?? "")) in \(trip)"
        case .paymentLogged:
            return paymentStatement(event, viewer: viewer, trip: trip)
        case .paymentDeleted:
            return "\(actor) removed a payment in \(trip)"
        case .tripDeleted:
            return "\(actor) deleted the trip \(trip)"
        case .tripUndeleted:
            return "\(actor) restored the trip \(trip)"
        case .memberRemoved:
            return removal(event, viewer: viewer, viewerName: viewerName, actor: actor, trip: trip)
        }
    }

    /// Who paid whom. The actor is whoever logged it, which is not always the payer.
    private static func paymentStatement(_ event: Event, viewer: UUID, trip: String) -> String {
        if event.payeeId == viewer, event.payerId != viewer {
            return "\(person(event.payerName, isYou: false, leading: true)) paid you in \(trip)"
        }
        if event.payerId == viewer {
            let payee = person(event.payeeName, isYou: false, leading: false)
            if let amount = event.amountCents {
                return "You paid \(payee) \(Money.string(amount)) in \(trip)"
            }
            return "You paid \(payee) in \(trip)"
        }
        let payer = person(event.payerName, isYou: false, leading: true)
        let payee = person(event.payeeName, isYou: false, leading: false)
        return "\(payer) paid \(payee) in \(trip)"
    }

    private static func removal(_ event: Event, viewer: UUID, viewerName: String, actor: String, trip: String) -> String {
        if left(event) {
            return "\(actor) left \(trip)"
        }
        let removedIsYou: Bool = {
            if let removedId = event.removedId { return removedId == viewer }
            guard let subject = event.subject, !subject.isEmpty else { return false }
            return subject == viewerName
        }()
        return "\(actor) removed \(person(event.subject, isYou: removedIsYou, leading: false)) from \(trip)"
    }

    /// A leave is the actor removing themself. The row stores that person's name in `subject`.
    private static func left(_ event: Event) -> Bool {
        if let removedId = event.removedId { return removedId == event.actorId }
        guard let subject = event.subject, !subject.isEmpty else { return false }
        return event.actorName == subject
    }

    // MARK: Dollar line

    private static func dollarLine(_ event: Event, viewer: UUID) -> String? {
        switch event.kind {
        case .expenseAdded, .expenseUpdated, .expenseDeleted:
            return expenseDollar(event, viewer: viewer)
        case .paymentLogged:
            // Receiving moves your net down, so the expense rule would say "You owe". This line is its own sentence.
            guard event.payeeId == viewer, event.payerId != viewer, let amount = event.amountCents else { return nil }
            return "You received \(Money.string(amount))"
        case .paymentDeleted:
            // The reversal: deleting a payment you received lifts your net; deleting one you made drops it.
            let delta = event.deltas[viewer] ?? 0
            if delta > 0 { return "You get back \(Money.string(delta))" }
            if delta < 0 { return "You owe \(Money.string(delta))" }
            return nil
        case .tripCreated, .memberJoined, .tripDeleted, .tripUndeleted, .memberRemoved:
            return nil
        }
    }

    private static func expenseDollar(_ event: Event, viewer: UUID) -> String? {
        let delta = event.deltas[viewer] ?? 0
        if delta < 0 { return "You owe \(Money.string(delta))" }
        if delta > 0 { return "You get back \(Money.string(delta))" }
        // Your own cost: you paid and your share is the whole amount, so the net did not move.
        if event.expensePayerId == viewer, let amount = event.expenseAmountCents, event.viewerShareCents == amount {
            return "You paid \(Money.string(amount))"
        }
        return nil
    }

    private static func person(_ stored: String?, isYou: Bool, leading: Bool) -> String {
        if isYou { return leading ? "You" : "you" }
        let shown = PersonName.shown(stored ?? "")
        return shown.isEmpty ? "Someone" : shown
    }

    private static func quoted(_ text: String) -> String { "\"\(text)\"" }
}
