import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView {
            TripsView().tabItem { Label("Trips", systemImage: "suitcase") }
            PlaceholderTab(title: "Activity").tabItem { Label("Activity", systemImage: "clock") }  // Phase 5
            ProfileTab().tabItem { Label("Profile", systemImage: "person.crop.circle") }           // Phase 5 fills this in
        }
        .sheet(item: $app.welcomeTrip) { WelcomeSheet(trip: $0) }
        .sheet(item: $app.expenseSheet) { ExpenseFormView(target: $0) }
        .sheet(isPresented: $app.showingBalance) { YourBalanceView() }
    }
}

/// The header on every main screen: balance chip (left) and Add (right). Add logs an expense; with no trips
/// yet it starts a trip. Another trip starts from the Add trip button under the trip cards.
struct MainHeader: ToolbarContent {
    let onAddTrip: () -> Void
    @Environment(AppModel.self) private var app

    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarLeading) { chip }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) { add }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { chip }
            ToolbarItem(placement: .topBarTrailing) { add }
        }
    }

    private var chip: some View {
        Button { app.showingBalance = true } label: { BalanceChip(cents: app.headerTotal) }.buttonStyle(.plain)
    }

    private var add: some View {
        AddButton(onAddTrip: onAddTrip)
    }
}

/// Tap adds an expense, or starts a trip when you have none (Figma Main Header).
private struct AddButton: View {
    let onAddTrip: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            if app.trips.isEmpty { onAddTrip() } else { app.addExpense() }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.white, Color.tsTintFill)
        }
        .accessibilityLabel("Add")
    }
}

struct PlaceholderTab: View {
    let title: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Coming soon", systemImage: "clock", description: Text("\(title) arrives in a later build."))
                .navigationTitle(title)
        }
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
                        Text(app.profile?.displayName.nilIfEmpty ?? "You").font(.title3.weight(.semibold))
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
