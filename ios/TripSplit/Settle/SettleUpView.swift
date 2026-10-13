import SwiftUI

/// What a payment logged here leaves behind on its ticket until you leave the page (Figma Settle up [U3]).
struct PaidTicket: Equatable {
    let personId: UUID
    let direction: SettleDirection
    let cents: Int
    let method: PayMethod
    let tripIds: [UUID]
}

/// Settle up (Figma Flow · Net model › Settle up): one page for every trip. Opened from a trip it starts on that
/// trip, and a segmented control switches to All trips. One Member Ticket per person you have a suggested
/// payment with; tapping one opens the Payment page.
struct SettleUpView: View {
    let startTrip: UUID?
    @Environment(AppModel.self) private var app
    /// The trip shown, or nil for All trips.
    @State private var scope: UUID?
    @State private var paying: SettleTicket?
    /// Payments logged on this page, oldest first. A ticket a payment settled stays, stamped, until you leave.
    @State private var paid: [PaidTicket] = []

    init(startTrip: UUID?) {
        self.startTrip = startTrip
        _scope = State(initialValue: startTrip)
    }

    var body: some View {
        let tickets = app.userId.map { SettleUp.tickets(app.settlements, me: $0, trip: scope, tripsOldestFirst: SettleUp.oldestFirst(app.trips)) } ?? []
        let settledHere = paid.filter { p in !tickets.contains { $0.personId == p.personId && $0.direction == p.direction } }
            .filter { p in scope == nil || p.tripIds.contains(scope!) }
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                let everyoneSettled = tickets.isEmpty && settledHere.isEmpty
                // Figma X10: nobody to settle, so no question.
                if !everyoneSettled { Text("Who do you want to settle?").font(.largeTitle.bold()) }
                if let startTrip, let trip = app.trip(startTrip) {
                    Picker("Trips", selection: $scope) {
                        Text(trip.name).tag(UUID?.some(startTrip))
                        Text("All trips").tag(UUID?.none)
                    }
                    .pickerStyle(.segmented)
                }
                ForEach(tickets) { ticket in
                    Button { paying = ticket } label: {
                        MemberTicketView(personId: ticket.personId, direction: ticket.direction, cents: ticket.cents, tripIds: ticket.tripIds,
                                         paid: paid.last { $0.personId == ticket.personId && $0.direction == ticket.direction })
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double tap to pay or record")
                }
                ForEach(settledHere.indices, id: \.self) { i in
                    let p = settledHere[i]
                    MemberTicketView(personId: p.personId, direction: p.direction, cents: 0, tripIds: p.tripIds, paid: p)
                }
                if everyoneSettled {
                    EmptyState(title: "You’re settled up",
                               message: scope == nil ? "You don’t owe anyone, and nobody owes you." : "You don’t owe anyone on this trip, and nobody here owes you.") {
                        StampCluster()
                    }
                    .padding(.top, 80)
                } else {
                    Text("Simplified so the fewest payments settle everyone. Tap someone to pay them, or to record what they paid you.")
                        .font(.footnote).foregroundStyle(Color.tsSecondary)
                }
            }
            .padding(Spacing.lg)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Settle up")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await app.refresh() }
        .navigationDestination(item: $paying) { ticket in
            PaymentView(ticket: ticket) { paid.append($0) }
        }
    }
}

/// Figma Member Ticket: the trip stamp(s), name and caption, a perforation, then "You owe" or "You lent" and the
/// amount. After a payment here it reads "Settled $0 · You paid $30 · Today" and the trip's stamp slams onto it.
struct MemberTicketView: View {
    let personId: UUID
    let direction: SettleDirection
    let cents: Int
    let tripIds: [UUID]
    var paid: PaidTicket?
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false
    /// The stub's width: where the tear and its notches go.
    @State private var stubWidth: CGFloat = 80

    private var settled: Bool { cents == 0 }
    private var name: String { app.name(of: personId) }
    private var label: String { settled ? "Settled" : direction == .pay ? "You owe" : "You’re owed" }
    private var caption: String {
        if let paid {
            let who = paid.direction == .pay ? "You paid" : "\(name) paid you"
            return "\(who) \(Money.string(paid.cents)) · Today"
        }
        return tripIds.count == 1 ? app.trip(tripIds[0])?.name ?? "" : "\(tripIds.count) trips"
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                Stamps(tripIds: tripIds)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(name).font(.title3.bold()).lineLimit(1)
                    Text(caption).font(.footnote).foregroundStyle(Color.tsSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Spacing.lg).padding(.vertical, Spacing.lg)
            TearLine()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(label).font(.footnote).foregroundStyle(Color.tsSecondary)
                Text(Money.string(cents)).font(.title3.bold())
                    .foregroundStyle(settled ? Color.tsSecondary : direction == .pay ? Color.tsOwe : Color.tsOwed)
            }
            .fixedSize()
            .padding(.leading, Spacing.xs).padding(.trailing, Spacing.lg)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stubWidth = $0 }
        }
        // The trip cards' ticket (TRIP-38): real notches, no chevron; the whole ticket is the tap target.
        .ticketBackground(.vertical(fromTrailing: stubWidth + TicketShape.notchRadius))
        .overlay {
            if settled, let first = tripIds.first, let stamp = app.trip(first)?.stamp {
                StampView(spec: stamp)
                    .frame(width: 96, height: 72)
                    .rotationEffect(.degrees(-10))
                    .scaleEffect(landed ? 1 : 2.2)
                    .opacity(landed ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onAppear {
                        withAnimation(Motion.celebrate.animation(reduceMotion: reduceMotion)) { landed = true }
                        AccessibilityNotification.Announcement("Settled with \(name).").post()
                    }
            }
        }
        .sensoryFeedback(Motion.Haptic.settled.feedback, trigger: landed) { _, new in new }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(settled ? "Settled with \(name). \(caption)"
                            : "\(NetSentence.text(direction == .pay ? -cents : cents, name: name)), \(caption)")
    }
}

/// Up to two trip stamps, then "+N", in a fixed-width column so names line up.
private struct Stamps: View {
    let tripIds: [UUID]
    @Environment(AppModel.self) private var app

    var body: some View {
        let stamps = tripIds.compactMap { app.trip($0)?.stamp }
        HStack(spacing: -14) {
            ForEach(Array(stamps.prefix(2).enumerated()), id: \.offset) { _, spec in
                StampView(spec: spec).frame(width: 40, height: 40)
            }
            if stamps.count > 2 {
                Text("+\(stamps.count - 2)").font(.caption.weight(.semibold)).foregroundStyle(Color.tsSecondary)
                    .padding(.horizontal, 6).frame(minWidth: 28, minHeight: 24)
                    .background(Color(.systemGray5), in: .capsule)
                    .overlay(Capsule().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
            }
        }
        .frame(width: 80, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// The ticket's tear line: a dashed rule with a notch at the top and bottom.
