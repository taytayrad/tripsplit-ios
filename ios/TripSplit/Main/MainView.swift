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
    }
}

/// The header on every main screen: balance chip (left) and Add (right). Add logs an expense; with no trips
/// yet it starts a trip, and otherwise a long press offers Add trip too (PRD › Navigation).
struct MainHeader: ToolbarContent {
    let onAddTrip: () -> Void
    @Environment(AppModel.self) private var app

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            BalanceChip(cents: app.headerTotal)  // Phase 4 makes it open Your Balance
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { app.addExpense() } label: { Label("Add expense", systemImage: "dollarsign.circle") }
                Button(action: onAddTrip) { Label("Add trip", systemImage: "suitcase") }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.white, Color.tsTintFill)
            } primaryAction: {
                if app.trips.isEmpty { onAddTrip() } else { app.addExpense() }
            }
            .accessibilityLabel("Add")
        }
    }
}

/// The Add button alone, for screens that already have a leading control (trip detail's back button).
struct MainHeaderAdd: ToolbarContent {
    let onAdd: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onAdd) { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.white, Color.tsTintFill) }
                .accessibilityLabel("Add")
        }
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
