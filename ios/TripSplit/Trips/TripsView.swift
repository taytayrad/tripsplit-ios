import SwiftUI

struct TripsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var addingTrip = false
    @State private var showSettled = false
    @State private var path: [UUID] = []
    @State private var settling = false
    /// The trip Add trip just created: its detail opens the share sheet once (TRIP-40).
    @State private var inviteOnOpen: UUID?

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
            .navigationDestination(for: UUID.self) { TripDetailView(tripId: $0, inviteOnOpen: $inviteOnOpen) }
            .sheet(isPresented: $addingTrip) {
                TripFormView(mode: .add) { created in inviteOnOpen = created.id; path = [created.id] }
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

/// Add trip as a blank ticket (TRIP-38, Figma A2): the trip cards' paper and tear line, with an empty dashed stamp
/// frame in the stub waiting for the new trip's stamp.
struct AddTripCard: View {
    let onAdd: () -> Void
    private static let stubWidth: CGFloat = 112  // the trip cards' stub (92 pt minimum plus padding), so the tears line up

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 0) {
                Label("Add trip", systemImage: "plus").font(.headline).foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                TearLine()
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(.separator), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 46, height: 34).rotationEffect(.degrees(-8))
                    .frame(width: Self.stubWidth)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 72)
            .ticketBackground(.vertical(fromTrailing: Self.stubWidth + TicketShape.notchRadius))
            .contentShape(TicketShape(cut: .vertical(fromTrailing: Self.stubWidth + TicketShape.notchRadius)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add trip")
    }
}

/// A settled trip, shown below "Show settled trips": a used ticket, its stub torn off (TRIP-38). The stamp is whole
/// here, since it's the trip's picture, not a watermark.
struct SettledTripRow: View {
    let trip: Trip
    var body: some View {
        HStack(spacing: Spacing.md) {
            StampAvatar(spec: trip.stamp, size: 40)
            Text(trip.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
            Spacer()
            Text("Settled").font(.subheadline).foregroundStyle(Color.tsSecondary)
        }
        .padding(.leading, Spacing.lg).padding(.trailing, Spacing.xl).frame(minHeight: 60)
        .ticketBackground(.torn)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.name), settled")
    }
}

/// The trips list card as a boarding pass (TRIP-38, Figma V1b): name and dates · members, a tear line, and a stub
/// with your net in words (no sign). The trip's stamp is a faded watermark cropped by the card; at accessibility
/// text sizes the pass stacks, tearing across instead of down.
struct TripCard: View {
    let trip: Trip
    let netCents: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    /// The stub's width (it hugs its text), or the main part's height when stacked: where the tear goes.
    @State private var tear: CGFloat = 100

    private var stacked: Bool { typeSize.isAccessibilitySize }
    private var cut: TicketShape.Cut {
        stacked ? .horizontal(fromTop: tear + TicketShape.notchRadius) : .vertical(fromTrailing: tear + TicketShape.notchRadius)
    }

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 0) {
                    main.padding(.top, Spacing.xl).padding(.bottom, Spacing.sm)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tear = $0 }
                    TearLine(axis: .horizontal)
                    stub.padding(.horizontal, Spacing.lg).padding(.top, Spacing.sm).padding(.bottom, Spacing.xl)
                }
            } else {
                HStack(spacing: 0) {
                    main.padding(.vertical, Spacing.xxl)
                    TearLine()
                    stub.padding(.trailing, Spacing.lg).padding(.leading, Spacing.xs)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tear = $0 }
                }
                .frame(minHeight: 120)
            }
        }
        .background { watermark }
        .ticketBackground(cut)
        .contentShape(TicketShape(cut: cut))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(netCents == 0 ? "\(trip.name), \(Money.string(0))" : NetSentence.text(netCents, name: trip.name))
        .accessibilityValue(subtitle)  // dates and members, so trips with the same name and balance sound different
    }

    private var subtitle: String { TripCardText.subtitle(start: trip.start, end: trip.end, memberCount: trip.members.count) }

    private var main: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Wraps to two lines (no limit at accessibility sizes): the amount has its own stub, so nothing collides.
            Text(trip.name).font(.title2.bold()).foregroundStyle(.primary).lineLimit(stacked ? nil : 2)
            Text(subtitle)
                .font(.footnote).foregroundStyle(Color.tsSecondary).lineLimit(stacked ? nil : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Spacing.lg).padding(.trailing, stacked ? Spacing.lg : Spacing.xs)
    }

    private var stub: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = TripCardText.label(netCents: netCents) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Color.tsSecondary)
            }
            Text(Money.string(netCents)).font(.title2.bold())
                .foregroundStyle(netCents < 0 ? Color.tsOwe : netCents > 0 ? Color.tsOwed : Color.tsSecondary)
        }
        .fixedSize()
        // A shared minimum keeps the tear lines in one column down the list; a wider amount grows the stub.
        .frame(minWidth: stacked ? nil : 92, alignment: .leading)
    }

    /// The trip's stamp, 130 pt at 15%, rotated −14°, centered 36 pt before the tear and clipped to the trip's side of
    /// it, so it bleeds off the card. Off with Increase Contrast.
    @ViewBuilder private var watermark: some View {
        if contrast != .increased {
            GeometryReader { geo in
                let tearX = stacked ? geo.size.width : geo.size.width - tear - TicketShape.notchRadius
                let tearY = stacked ? tear + TicketShape.notchRadius : geo.size.height
                StampView(spec: trip.stamp).frame(width: 130)
                    .rotationEffect(.degrees(-14))
                    .opacity(0.15)
                    .position(x: tearX - (stacked ? 44 : 36), y: stacked ? tearY / 2 : geo.size.height / 2)
                    .frame(width: tearX, height: tearY, alignment: .topLeading)
                    .clipped()
            }
            .clipShape(TicketShape(cut: cut))
            .accessibilityHidden(true)
        }
    }
}
