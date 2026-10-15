import Foundation

/// The activity read. No `deleted_at` filter: a deleted trip's rows stay (docs/permissions.md).
/// Newest first is the caller's `.order("created_at", ascending: false)`.
enum ActivityQuery {
    static let columns = [
        "id", "trip_id", "kind", "actor_id", "actor_name", "subject", "deltas", "expense_id", "created_at",
        "expense_payer_id", "expense_amount_cents", "expense_payer_share_cents",
        "actor:profiles!activity_events_actor_id_fkey(display_name)",
        "trips!activity_events_trip_id_fkey(name, stamp, deleted_at)",
        "payments(payer_id, payee_id, amount_cents, deleted_at, payer:profiles!payments_payer_id_fkey(display_name), payee:profiles!payments_payee_id_fkey(display_name))",
    ].joined(separator: ",")
}

/// One `activity_events` row plus the trip, actor, and payment the statement needs.
/// A hard-deleted expense is absent; its title is `subject`. A soft-deleted payment still has its parties.
struct ActivityEvent: Decodable, Identifiable, Hashable, Sendable {
    struct PaymentParty: Hashable, Sendable {
        var payerId: UUID
        var payeeId: UUID
        var payerName: String
        var payeeName: String
        var amountCents: Int
        var deletedAt: Date?
    }

    let id: UUID
    let tripId: UUID
    let kind: ActivityKind
    let actorId: UUID
    let actorName: String
    let actorSnapshot: String?
    let tripName: String
    let stamp: StampSpec
    /// Set when the trip is soft-deleted. The row stays in Activity.
    let tripDeletedAt: Date?
    let subject: String?
    let deltas: [UUID: Int]
    let expenseId: UUID?
    /// Payer, amount, and the payer's share at the moment this event was written. Nil on older rows.
    let expensePayerId: UUID?
    let expenseAmountCents: Int?
    let expensePayerShareCents: Int?
    let createdAt: Date
    let payment: PaymentParty?

    var tripDeleted: Bool { tripDeletedAt != nil }

    enum Target: Hashable { case expense(UUID), trip(UUID), undelete(UUID), activity }

    /// Notification taps (N1–N9) have different payment/deleted-trip destinations from Activity row taps.
    func notificationTarget(expenses: Set<UUID>, trips: Set<UUID>) -> Target {
        switch kind {
        case .expenseAdded, .expenseUpdated, .expenseDeleted, .expenseRestored, .memberJoined, .tripUndeleted:
            return target(expenses: expenses, trips: trips) ?? .activity
        case .paymentLogged, .paymentDeleted:
            return trips.contains(tripId) ? .trip(tripId) : .activity
        case .tripDeleted, .tripCreated, .memberRemoved, .unknown:
            return .activity
        }
    }

    /// What tapping this row opens (TRIP-20): an expense row opens its details (a deleted one, its deleted state);
    /// a trip or member row opens the trip. A `trip_deleted` row asks to undelete a trip that's still deleted
    /// (TRIP-21), and opens it once it's back. Nil when there's nothing to open: an expense deleted before TRIP-27,
    /// a trip you can't see now, or a payment row.
    func target(expenses: Set<UUID>, trips: Set<UUID>) -> Target? {
        switch kind {
        case .expenseAdded, .expenseUpdated, .expenseDeleted, .expenseRestored:
            return expenseId.flatMap { expenses.contains($0) ? .expense($0) : nil }
        case .tripCreated, .tripUndeleted, .memberJoined, .memberRemoved:
            return trips.contains(tripId) ? .trip(tripId) : nil
        case .tripDeleted:
            return trips.contains(tripId) ? .trip(tripId) : tripDeleted ? .undelete(tripId) : nil
        case .paymentLogged, .paymentDeleted, .unknown:
            return nil
        }
    }

    /// Search (docs/events.md › Search): a person, the expense title, or the trip name. People are the actor and
    /// a payment's payer and payee; `subject` is the expense title, or the removed person on `member_removed`.
    /// Names match as stored ("Atish Dey") and as shown ("Atish D."). Case and accents don't matter.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let names = [actorName, payment?.payerName, payment?.payeeName, subject].compactMap { $0 }
        return ([tripName] + names + names.map(PersonName.shown)).contains { $0.localizedStandardContains(query) }
    }

    /// `expenses` is the live list. Own-cost lines do not read it: a later edit would rewrite an earlier row.
    func statement(viewer: UUID, viewerName: String, expenses: [Expense]) -> ActivityCopy.Result {
        _ = expenses
        return ActivityCopy.line(facts(viewer: viewer), viewer: viewer, viewerName: viewerName)
    }

    private func facts(viewer: UUID) -> ActivityCopy.Event {
        // The viewer's own-cost share is the payer's share only when the viewer paid.
        let viewerShare = expensePayerId == viewer ? expensePayerShareCents : nil
        return ActivityCopy.Event(
            kind: kind, actorId: actorId, actorName: actorName, tripName: tripName, subject: subject,
            actorSnapshot: actorSnapshot,
            deltas: deltas,
            expensePayerId: expensePayerId, expenseAmountCents: expenseAmountCents, viewerShareCents: viewerShare,
            payerId: payment?.payerId, payeeId: payment?.payeeId,
            payerName: payment?.payerName, payeeName: payment?.payeeName, amountCents: payment?.amountCents)
    }

    private struct NameRow: Decodable {
        var displayName: String
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }

    private struct TripRow: Decodable {
        var name: String
        var stamp: StampSpec
        var deletedAt: Date?
        enum CodingKeys: String, CodingKey { case name, stamp, deletedAt = "deleted_at" }
    }

    private struct PaymentRow: Decodable {
        var payerId: UUID
        var payeeId: UUID
        var amountCents: Int
        var deletedAt: Date?
        var payer: NameRow?
        var payee: NameRow?
        enum CodingKeys: String, CodingKey {
            case payerId = "payer_id", payeeId = "payee_id", amountCents = "amount_cents"
            case deletedAt = "deleted_at", payer, payee
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, subject, deltas, actor, trips, payments
        case tripId = "trip_id", actorId = "actor_id", actorSnapshot = "actor_name", expenseId = "expense_id", createdAt = "created_at"
        case expensePayerId = "expense_payer_id", expenseAmountCents = "expense_amount_cents"
        case expensePayerShareCents = "expense_payer_share_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tripId = try c.decode(UUID.self, forKey: .tripId)
        kind = try c.decode(ActivityKind.self, forKey: .kind)
        actorId = try c.decode(UUID.self, forKey: .actorId)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        expenseId = try c.decodeIfPresent(UUID.self, forKey: .expenseId)
        expensePayerId = try c.decodeIfPresent(UUID.self, forKey: .expensePayerId)
        expenseAmountCents = try c.decodeIfPresent(Int.self, forKey: .expenseAmountCents)
        expensePayerShareCents = try c.decodeIfPresent(Int.self, forKey: .expensePayerShareCents)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        actorName = try c.decodeIfPresent(NameRow.self, forKey: .actor)?.displayName ?? ""
        actorSnapshot = try c.decodeIfPresent(String.self, forKey: .actorSnapshot)
        let trip = try c.decode(TripRow.self, forKey: .trips)
        tripName = trip.name
        stamp = trip.stamp
        tripDeletedAt = trip.deletedAt
        let raw = try c.decodeIfPresent([String: Int].self, forKey: .deltas) ?? [:]
        deltas = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
        if let row = try c.decodeIfPresent(PaymentRow.self, forKey: .payments) {
            payment = PaymentParty(payerId: row.payerId, payeeId: row.payeeId,
                                   payerName: row.payer?.displayName ?? "", payeeName: row.payee?.displayName ?? "",
                                   amountCents: row.amountCents, deletedAt: row.deletedAt)
        } else {
            payment = nil
        }
    }
}
