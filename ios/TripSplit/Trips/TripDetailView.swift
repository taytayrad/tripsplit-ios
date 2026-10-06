import SwiftUI

struct TripDetailView: View {
    let tripId: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    /// The person whose screen is pushed to settle up.
    @State private var paying: UUID?
    /// Who you owe on this trip, when it's more than one person: the tap asks which.
    @State private var choosing: [PairBalance] = []

    var body: some View {
        if let trip = app.trip(tripId) {
            let expenses = app.expenses(on: trip.id)
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
                        let net = app.nets[trip.id] ?? 0
                        if net < 0 {
                            // What you owe here settles on that person's screen (their pay bar, their whole balance).
                            Button { settleUp(trip) } label: { BalanceBlock(cents: net) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Double tap to settle up")
                        } else {
                            BalanceBlock(cents: net)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
                }

                Section {
                    if expenses.isEmpty {
                        VStack(spacing: Spacing.md) {
                            Text("No expenses yet. Add the first one.").font(.subheadline).foregroundStyle(Color.tsSecondary)
                            Button("Add expense") { app.addExpense(on: trip.id) }.buttonStyle(PrimaryButtonStyle())
                        }
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(expenses) { expense in
                            ExpenseRow(expense: expense, trip: trip)
                                .contentShape(.rect)
                                .onTapGesture { app.expenseSheet = .edit(expense) }  // delete from there; no swipe
                        }
                        Button("Add expense") { app.addExpense(on: trip.id) }.foregroundStyle(Color.tsTintFill)
                    }
                } header: { Text("EXPENSES").font(.footnote) }
            }
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
            .sheet(isPresented: $editing) { TripFormView(mode: .edit(trip)) }
            .navigationDestination(item: $paying) { PersonView(personId: $0) }
            .confirmationDialog("Who are you paying?", isPresented: .init(get: { !choosing.isEmpty }, set: { if !$0 { choosing = [] } }),
                                titleVisibility: .visible) {
                ForEach(choosing, id: \.otherUserId) { pair in
                    Button("\(app.name(of: pair.otherUserId)) · \(Money.string(pair.cents))") { paying = pair.otherUserId }
                }
            }
        } else {
            // The trip was deleted (here or on another phone).
            Color(.systemGroupedBackground).onAppear { dismiss() }
        }
    }
}

extension TripDetailView {
    /// One person you owe here: straight to their screen. Several: pick, most owed first.
    private func settleUp(_ trip: Trip) {
        let owed = app.pairs.filter { $0.tripId == trip.id && $0.cents < 0 }.sorted { $0.cents < $1.cents }
        if owed.count == 1 { paying = owed[0].otherUserId } else { choosing = owed }
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
