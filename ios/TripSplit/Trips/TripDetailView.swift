import SwiftUI

struct TripDetailView: View {
    let tripId: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting: Expense?

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
                        HStack(spacing: Spacing.sm) {
                            if let start = trip.start, let end = trip.end { Chip(text: DayFormat.range(start, end)) }
                            Chip(text: trip.members.count == 1 ? "1 member" : "\(trip.members.count) members")
                        }
                        BalanceBlock(cents: app.nets[trip.id] ?? 0)
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
                                .onTapGesture { app.expenseSheet = .edit(expense) }
                                .swipeActions { Button("Delete", role: .destructive) { deleting = expense } }
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
            .deleteExpenseAlert(expense: $deleting, tripName: trip.name)
        } else {
            // The trip was deleted (here or on another phone).
            Color(.systemGroupedBackground).onAppear { dismiss() }
        }
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
