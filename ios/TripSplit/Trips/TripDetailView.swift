import SwiftUI

/// Trip detail (Figma Flow · Net model › Trip): your net with Pay beside it, one list of expenses and payments
/// (newest first), and Add expense pinned at the bottom. When everyone is settled, the trip's stamp says so.
struct TripDetailView: View {
    let tripId: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var settling = false
    @State private var deletingPayment: Payment?
    @State private var openExpense: UUID?

    var body: some View {
        if let trip = app.trip(tripId) {
            let ledger = TripLedger.items(expenses: app.expenses(on: trip.id), payments: app.payments(on: trip.id))
            let net = app.nets[trip.id] ?? 0
            let settled = SettleUp.isSettled(trip: trip.id, app.settlements) && !ledger.isEmpty
            let hasSettlements = app.settlements.contains { $0.tripId == trip.id && ($0.payerId == app.userId || $0.payeeId == app.userId) }
            List {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack(spacing: Spacing.md) {
                            TripAvatar(trip: trip, size: 64)
                            Text(trip.name).font(.largeTitle.bold())
                        }
                        // Either chip opens Edit trip, where the dates and members are changed.
                        HStack(spacing: Spacing.sm) {
                            if let start = trip.start, let end = trip.end {
                                Button { editing = true } label: { Chip(text: DayFormat.range(start, end)) }
                            }
                            Button { editing = true } label: { Chip(text: trip.members.count == 1 ? "1 member" : "\(trip.members.count) members") }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Double tap to edit the trip")
                        if settled {
                            SettledHero(trip: trip, last: app.payments(on: trip.id).max { $0.createdAt < $1.createdAt })
                        } else {
                            HStack(alignment: .center, spacing: Spacing.md) {
                                BalanceBlock(cents: net)
                                if hasSettlements {
                                    Button(net < 0 ? "Pay" : "Settle up") { settling = true }
                                        .font(.headline).foregroundStyle(.white)
                                        .padding(.horizontal, Spacing.xl).frame(minHeight: 44)
                                        .background(Color.tsTintFill, in: .rect(cornerRadius: Radius.lg))
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
                }

                Section {
                    if ledger.isEmpty {
                        Text("No expenses yet. Add the first one.").font(.subheadline).foregroundStyle(Color.tsSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, Spacing.sm)
                    } else {
                        ForEach(ledger) { item in
                            switch item {
                            case .expense(let expense):
                                ExpenseRow(expense: expense, trip: trip)
                                    .contentShape(.rect)
                                    .onTapGesture { openExpense = expense.id }  // details; edit and delete from there, no swipe
                            case .payment(let payment):
                                PaymentRow(payment: payment, trip: trip)
                                    .swipeActions {
                                        if [payment.payerId, payment.payeeId].contains(app.userId) {
                                            Button("Delete", role: .destructive) { deletingPayment = payment }
                                        }
                                    }
                            }
                        }
                    }
                } header: {
                    Text(app.payments(on: trip.id).isEmpty ? "EXPENSES" : "EXPENSES AND PAYMENTS").font(.footnote)
                }
            }
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button("Add expense") { app.addExpense(on: trip.id) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
                    .background(Color(.systemGroupedBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
            .sheet(isPresented: $editing) {
                TripFormView(mode: .edit(trip), onSettleUp: { settling = true })
            }
            .navigationDestination(isPresented: $settling) { SettleUpView(startTrip: trip.id) }
            .navigationDestination(item: $openExpense) { ExpenseDetailView(expenseId: $0, fromTrip: true) }
            .alert("Delete this payment?", isPresented: .init(get: { deletingPayment != nil }, set: { if !$0 { deletingPayment = nil } }),
                   presenting: deletingPayment) { p in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        do { try await app.deletePayment(p.id) }
                        catch { app.error = AppModel.describe("Couldn’t delete the payment. Check your connection and try again.", error) }
                    }
                }
            } message: { _ in Text("It comes off the balances on \(trip.name). Either person on a payment can delete it.") }
        } else {
            // The trip was deleted, or you left it (here or on another phone).
            Color(.systemGroupedBackground).onAppear { dismiss() }
        }
    }
}

/// Everyone on the trip is at $0: the trip's stamp, "Everyone's settled", and the last payment.
private struct SettledHero: View {
    let trip: Trip
    let last: Payment?
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: Spacing.sm) {
            StampView(spec: trip.stamp).frame(width: 140, height: 104).rotationEffect(.degrees(-7)).accessibilityHidden(true)
            Text("Everyone’s settled").font(.title.bold())
            if let last {
                Text(PaymentRow.title(last, me: app.userId, name: app.name(of:)) + " " + Money.string(last.amountCents) + " · "
                     + [last.method.title, ExpenseLine.day(last.date)].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Color.tsSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}

/// A payment in the trip's list: the transfer icon, who paid whom, the method and day, and a gray amount.
struct PaymentRow: View {
    let payment: Payment
    let trip: Trip
    @Environment(AppModel.self) private var app

    static func title(_ p: Payment, me: UUID?, name: (UUID) -> String) -> String {
        if p.payerId == me { return "You paid \(name(p.payeeId))" }
        if p.payeeId == me { return "\(name(p.payerId)) paid you" }
        return "\(name(p.payerId)) paid \(name(p.payeeId))"
    }

    var body: some View {
        ExpenseRowLayout(symbol: "arrow.left.arrow.right", title: Self.title(payment, me: app.userId, name: app.name(of:)),
                         caption: [payment.method.title, ExpenseLine.day(payment.date)].compactMap { $0 }.joined(separator: " · "),
                         label: nil, cents: payment.amountCents, color: .tsSecondary)
    }
}

struct Chip: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline)
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.xs)
            .background(Color(.systemGray5), in: .capsule)
    }
}
