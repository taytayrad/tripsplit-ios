import SwiftUI

struct TripDetailView: View {
    let tripId: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        if let trip = app.trip(tripId) {
            ScrollView {
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
                    Text("EXPENSES").font(.footnote).foregroundStyle(Color.tsSecondary)
                    VStack(spacing: Spacing.md) {
                        Text("No expenses yet. Add the first one.").font(.subheadline).foregroundStyle(Color.tsSecondary)
                        Button("Add expense") {}.buttonStyle(PrimaryButtonStyle()).disabled(true)  // Phase 3
                    }
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.md))
                }
                .padding(Spacing.lg)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Edit") { editing = true } }
            .sheet(isPresented: $editing) { TripFormView(mode: .edit(trip)) }
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
