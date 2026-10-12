import SwiftUI

struct TripsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var addingTrip = false
    @State private var showSettled = false
    @State private var path: [UUID] = []
    @State private var settling = false

    private func isSettled(_ trip: Trip) -> Bool { TripVisibility.isHidden(endDate: trip.end, netCents: app.nets[trip.id] ?? 0) }
    /// Trips still in play, newest first.
    private var active: [Trip] { app.trips.filter { !isSettled($0) } }
    /// Past trips at $0, shown below "Show settled trips" once it's tapped.
    private var settled: [Trip] { app.trips.filter(isSettled) }

    var body: some View {
        NavigationStack(path: $path) {
            // A List, not a ScrollView: a ScrollView's pull-to-refresh could stay pulled down (TRIP-33). Rows are
            // clear, with no separators or chevrons, so the cards look as they did.
            List {
                if app.isOffline { OfflineBanner(message: OfflineBanner.reading).tripsRow() }
                if app.trips.isEmpty {
                    if app.loadFailed {
                        CouldntLoad(title: "Couldn’t load your trips").padding(.top, 80).tripsRow()
                    } else {
                        EmptyTrips { addingTrip = true }.padding(.top, 80).tripsRow()
                    }
                } else if active.isEmpty && !showSettled {
                    // Every trip is settled: the empty state, with the way back to them.
                    EmptyTrips(title: "You’re all settled",
                               message: "Every trip is paid up. Start a new one, or look back at the ones you’ve settled.") { addingTrip = true }
                        .padding(.top, 80).tripsRow()
                } else {
                    ForEach(active) { trip in
                        Button { path.append(trip.id) } label: { TripCard(trip: trip, netCents: app.nets[trip.id] ?? 0) }
                            .buttonStyle(.plain).tripsRow()
                    }
                    // Add trip stays with the trips in play, so showing settled trips doesn't push it down.
                    AddTripCard { addingTrip = true }.tripsRow()
                }
                if !settled.isEmpty {
                    Button(showSettled ? "Hide settled trips" : settled.count == 1 ? "Show 1 settled trip" : "Show \(settled.count) settled trips") {
                        withAnimation(Motion.quick.animation(reduceMotion: reduceMotion)) { showSettled.toggle() }
                    }
                    .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityValue(showSettled ? "Showing" : "Hidden")
                    .tripsRow()
                    if showSettled {
                        ForEach(settled) { trip in
                            Button { path.append(trip.id) } label: { SettledTripRow(trip: trip) }.buttonStyle(.plain).tripsRow()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(Spacing.lg)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, Spacing.lg, for: .scrollContent)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trips")
            .toolbar { MainHeader(onAddTrip: { addingTrip = true }, onSettleUp: { settling = true }) }
            .navigationDestination(isPresented: $settling) { SettleUpView(startTrip: nil) }
            .refreshable { await app.refresh() }
            .navigationDestination(for: UUID.self) { TripDetailView(tripId: $0) }
            .sheet(isPresented: $addingTrip) {
                TripFormView(mode: .add) { created in path = [created.id] }
            }
        }
    }
}

private extension View {
    /// A Trips list row: the Figma card spacing, no row background, separator, or selection highlight.
    func tripsRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Figma X8: a first load failed with nothing to show. No stamps on an error.
struct CouldntLoad: View {
    let title: String
    @Environment(AppModel.self) private var app
    @State private var retrying = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text(title).font(.title3.weight(.semibold))
            Text("Check your connection and try again.")
                .font(.subheadline).foregroundStyle(Color.tsSecondary).multilineTextAlignment(.center)
            Button {
                retrying = true
                Task { await app.refresh(); retrying = false }
            } label: {
                if retrying { ProgressView().tint(.white) } else { Text("Retry") }
            }
            .buttonStyle(PrimaryButtonStyle()).frame(width: 200).disabled(retrying)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
        .onAppear { appeared = true }
        .sensoryFeedback(Motion.Haptic.warning.feedback, trigger: appeared) { _, new in new }
    }
}

struct EmptyTrips: View {
    var title = "No trips yet"
    var message = "Start one, add your friends, and log who paid."
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: Spacing.md) {
            EmptyState(title: title, message: message) { StampCluster() }
            Button("Add Trip", action: onAdd).buttonStyle(PrimaryButtonStyle()).frame(width: 200)
        }
    }
}

/// Figma Empty State: stamps, a title, and a line under it. Stamps are decoration, hidden from VoiceOver.
struct EmptyState<Art: View>: View {
    let title: String
    let message: String
    @ViewBuilder let art: Art
    var body: some View {
        VStack(spacing: Spacing.md) {
            art.accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold)).padding(.top, Spacing.xs)
            Text(message)
                .font(.subheadline).foregroundStyle(Color.tsSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}

/// Figma Add trip card: a short dashed placeholder under the trips in play. The outline uses the secondary text
/// color so it stays visible (3:1 or better) on the grouped background.
struct AddTripCard: View {
    let onAdd: () -> Void
    var body: some View {
        Button(action: onAdd) {
            Label("Add trip", systemImage: "plus").font(.headline).foregroundStyle(Color.tsTintFill)
                .frame(maxWidth: .infinity, minHeight: 72)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Color.tsSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A settled trip, shown below "Show settled trips": one compact line (stamp, name, "Settled"), so finished trips
/// don't compete with the ones still in play.
struct SettledTripRow: View {
    let trip: Trip
    var body: some View {
        HStack(spacing: Spacing.md) {
            StampAvatar(spec: trip.stamp, size: 40)
            Text(trip.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
            Spacer()
            Text("Settled").font(.subheadline).foregroundStyle(Color.tsSecondary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, Spacing.lg).frame(minHeight: 60)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.xl))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.name), settled")
    }
}

/// The trips list card: name and your net in words (no sign), on the surface color with the trip's ink as its
/// border (TRIP-15: no tint fill).
struct TripCard: View {
    let trip: Trip
    let netCents: Int

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                Text(trip.name).font(.title2.bold()).foregroundStyle(.primary).lineLimit(1)
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
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(trip.stamp.ink.ink.opacity(0.2)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(netCents == 0 ? "\(trip.name), \(Money.string(0))" : NetSentence.text(netCents, name: trip.name))
    }
}
