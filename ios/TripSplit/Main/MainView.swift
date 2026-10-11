import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedTab = 0
    @State private var activityPath: [ActivityEvent.Target] = []
    @State private var activityRoot = 0

    var body: some View {
        @Bindable var app = app
        TabView(selection: $selectedTab) {
            TripsView().tabItem { Label("Trips", systemImage: "suitcase") }.tag(0)
            ActivityView(path: $activityPath).id(activityRoot).tabItem { Label("Activity", systemImage: "clock") }.tag(1)
            ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(2)
        }
        .sheet(item: $app.welcomeTrip) { WelcomeSheet(trip: $0) }
        .sheet(item: $app.expenseSheet) { ExpenseFormView(target: $0) }
        .task(id: app.pushEventId) {
            guard let id = app.pushEventId else { return }
            let user = app.userId
            let target = await app.notificationTarget(id)
            guard !Task.isCancelled, app.stage == .ready, app.userId == user, app.pushEventId == id else { return }
            app.expenseSheet = nil
            app.welcomeTrip = nil
            // Reset search, old details, and sheets before opening the notification's destination.
            activityRoot += 1
            activityPath = target == .activity ? [] : [target]
            selectedTab = 1
            app.pushEventId = nil
        }
    }
}

/// The header on every main screen: Settle up (left) and Add (right). Settle up opens All trips, so anyone you
/// have a balance with stays reachable, including on a trip you were removed from before TRIP-14. Add logs an
/// expense; with no trips yet it starts a trip. There's no running total: money lives on each trip (PRD › Net model).
struct MainHeader: ToolbarContent {
    let onAddTrip: () -> Void
    let onSettleUp: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { Button("Settle up", action: onSettleUp) }
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarTrailing) { add }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .principal) { noInlineTitle }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { add }
            ToolbarItem(placement: .principal) { noInlineTitle }
        }
    }

    /// Scrolled down, the large title would shrink into the bar, off center between Settle up and the wider Add
    /// button. The tab bar already says where you are, so the bar stays empty; the large title still shows at the top.
    private var noInlineTitle: some View {
        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
    }

    private var add: some View {
        AddButton(onAddTrip: onAddTrip)
    }
}

/// "+ Add expense", or "+ Add trip" when you have none (Figma Main Header). Spelled out: a bare "+" over a list of
/// trips reads as "new trip".
private struct AddButton: View {
    let onAddTrip: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let noTrips = app.trips.isEmpty
        Button {
            if noTrips { onAddTrip() } else { app.addExpense() }
        } label: {
            // An HStack, not a Label: iOS 26 toolbars show a Label's icon only, whatever its label style.
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus")
                Text(noTrips ? "Add trip" : "Add expense")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.leading, 14).padding(.trailing, 16).frame(minHeight: 44)  // the height of the glass Settle up button
            // Drawn here, not with .borderedProminent: iOS 26 toolbars restyle button fills (white text on glass).
            .background(Color.tsTintFill, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(noTrips ? "Add trip" : "Add expense")
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
