import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView {
            TripsView().tabItem { Label("Trips", systemImage: "suitcase") }
            ActivityView().tabItem { Label("Activity", systemImage: "clock") }
            ProfileTab().tabItem { Label("Profile", systemImage: "person.crop.circle") }           // Phase 5 fills this in
        }
        .sheet(item: $app.welcomeTrip) { WelcomeSheet(trip: $0) }
        .sheet(item: $app.expenseSheet) { ExpenseFormView(target: $0) }
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

struct ProfileTab: View {
    @Environment(AppModel.self) private var app
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(app.profile?.displayName.nilIfEmpty.map(PersonName.shown) ?? "You").font(.title3.weight(.semibold))
                        Text("Signed in with Apple").font(.footnote).foregroundStyle(Color.tsSecondary)
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }
            }
            .navigationTitle("Profile")
            .alert("Sign out of TripSplit?", isPresented: $confirmSignOut) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive) { Task { await app.signOut() } }
            } message: { Text("Your trips and balances stay saved. Sign back in with Apple anytime.") }
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
