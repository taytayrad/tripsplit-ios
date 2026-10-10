import Foundation

/// The activity read. No `deleted_at` filter: a deleted trip's rows stay (docs/permissions.md).
/// Newest first is the caller's `.order("created_at", ascending: false)`.
enum ActivityQuery {
    static let columns = [
        "id", "trip_id", "kind", "actor_id", "subject", "deltas", "expense_id", "created_at",
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
    let tripName: String
    let stamp: StampSpec
    /// Set when the trip is soft-deleted. The row stays in Activity.
    let tripDeletedAt: Date?
    let subject: String?
    let deltas: [UUID: Int]
    let expenseId: UUID?
    let createdAt: Date
    let payment: PaymentParty?

    var tripDeleted: Bool { tripDeletedAt != nil }

    func statement(viewer: UUID, viewerName: String, expenses: [Expense]) -> ActivityCopy.Result {
        ActivityCopy.line(facts(viewer: viewer, viewerName: viewerName, expenses: expenses),
                          viewer: viewer, viewerName: viewerName)
    }

    private func facts(viewer: UUID, viewerName: String, expenses: [Expense]) -> ActivityCopy.Event {
        let expense = expenseId.flatMap { id in expenses.first { $0.id == id } }
        return ActivityCopy.Event(
            kind: kind, actorId: actorId, actorName: actorName, tripName: tripName, subject: subject,
            deltas: deltas,
            expensePayerId: expense?.payerId, expenseAmountCents: expense?.amountCents,
            viewerShareCents: expense?.share(of: viewer),
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
        case tripId = "trip_id", actorId = "actor_id", expenseId = "expense_id", createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tripId = try c.decode(UUID.self, forKey: .tripId)
        kind = try c.decode(ActivityKind.self, forKey: .kind)
        actorId = try c.decode(UUID.self, forKey: .actorId)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        expenseId = try c.decodeIfPresent(UUID.self, forKey: .expenseId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        actorName = try c.decodeIfPresent(NameRow.self, forKey: .actor)?.displayName ?? ""
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
