import SwiftUI

struct TripsView: View {
    @Environment(AppModel.self) private var app
    @State private var addingTrip = false
    @State private var showSettled = false
    @State private var path: [UUID] = []

    private var visible: [Trip] {
        app.trips.filter { showSettled || !TripVisibility.isHidden(endDate: $0.end, netCents: app.nets[$0.id] ?? 0) }
    }
    private var hiddenCount: Int { app.trips.count - app.trips.filter { !TripVisibility.isHidden(endDate: $0.end, netCents: app.nets[$0.id] ?? 0) }.count }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if app.trips.isEmpty {
                    EmptyTrips { addingTrip = true }.padding(.top, 80)
                } else {
                    LazyVStack(spacing: Spacing.lg) {
                        ForEach(visible) { trip in
                            NavigationLink(value: trip.id) { TripCard(trip: trip, netCents: app.nets[trip.id] ?? 0) }
                                .buttonStyle(.plain)
                        }
                        if hiddenCount > 0 {
                            Button(showSettled ? "Hide settled trips" : "Show settled trips") { showSettled.toggle() }
                                .font(.subheadline)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trips")
            .toolbar { MainHeader { if app.trips.isEmpty { addingTrip = true } else { app.addExpense() } } }
            .refreshable { await app.refresh() }
            .navigationDestination(for: UUID.self) { TripDetailView(tripId: $0) }
            .sheet(isPresented: $addingTrip) {
                TripFormView(mode: .add) { created in path = [created.id] }
            }
        }
    }
}

struct EmptyTrips: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: Spacing.md) {
            StampCluster()
            Text("No trips yet").font(.title3.weight(.semibold)).padding(.top, Spacing.xs)
            Text("Start one, add your friends, and log who paid.")
                .font(.subheadline).foregroundStyle(Color.tsSecondary).multilineTextAlignment(.center)
            Button("Add Trip", action: onAdd).buttonStyle(PrimaryButtonStyle()).frame(width: 200)
        }
        .padding(.horizontal, Spacing.lg)
    }
}

/// The trips list card: name and your net in words (no sign), over the trip's ink.
struct TripCard: View {
    let trip: Trip
    let netCents: Int

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                Text(trip.name).font(.title2.bold()).foregroundStyle(.primary).lineLimit(2)
                Spacer(minLength: Spacing.md)
                if netCents != 0 {
                    Text(netCents < 0 ? "You owe" : "You’re owed").font(.subheadline.weight(.semibold)).foregroundStyle(Color.tsSecondary)
                }
                Text(Money.string(netCents)).font(.title2.bold())
                    .foregroundStyle(netCents < 0 ? Color.tsOwe : netCents > 0 ? Color.tsOwed : Color.tsSecondary)
            }
            Spacer()
            TripAvatar(trip: trip, size: 100)
        }
        .padding(Spacing.lg)
        .frame(minHeight: 132)
        .background(trip.stamp.ink.tint, in: .rect(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(trip.stamp.ink.ink.opacity(0.2)))
        .accessibilityElement(children: .combine)
    }
}
