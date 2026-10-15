import Supabase
import SwiftUI
import UIKit
import UserNotifications

/// The Profile tab (Figma Flow · Net model › Profile, F1–F5). Settings, so no Main Header. Every change saves as
/// it's made; a failed save offers Retry. Your name and Venmo open their own screens.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var permission: UNAuthorizationStatus?
    @State private var confirmSignOut = false
    @State private var failure: Failure?
    /// Trips, deleted ones too, where you still have a balance; nil until read.
    @State private var unsettled: Int?
    @State private var deleteAlert: DeleteAlert?
    @State private var deleting = false
    @State private var settling = false

    /// Delete account's two alerts (Figma F6, F7).
    private enum DeleteAlert { case notSettled(Int), confirm }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { NameView(name: app.profile?.displayName ?? "") { name in save(["display_name": .string(name)]) } } label: {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(app.profile?.displayName.nilIfEmpty.map(PersonName.shown) ?? "Add your name").font(.headline)
                            Text("Signed in with Apple").font(.footnote).foregroundStyle(Color.tsSecondary)
                        }
                        .padding(.vertical, Spacing.xxs)
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    NavigationLink {
                        VenmoView(username: app.profile?.venmoUsername) { name in
                            save(["venmo_username": name.map(AnyJSON.string) ?? .null])
                        }
                    } label: {
                        LabeledContent("Venmo", value: app.profile?.venmoUsername.map { "@\($0)" } ?? "Add")
                    }
                    CheckRow(title: "Zelle", isOn: payMethod(\.hasZelle, "has_zelle"))
                    CheckRow(title: "Apple Cash", isOn: payMethod(\.hasAppleCash, "has_apple_cash"))
                } header: { Text("How you get paid").accessibilityAddTraits(.isHeader) } footer: {
                    Text("Friends only see a pay button for an app you both have.")
                }

                Section {
                    if permission == .denied {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Notifications are off for TripSplit")
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    } else if permission == .notDetermined {
                        Button("Turn on notifications") {
                            Task {
                                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                                await readPermission()
                                await app.registerForPush()
                            }
                        }
                    }
                    Group {
                        Toggle("Payments with you", isOn: notify(\.notifyPaid, "notify_paid"))
                        Toggle("Expenses that affect you", isOn: notify(\.notifyExpense, "notify_expense"))
                        Toggle("Someone joins your trip", isOn: notify(\.notifyJoin, "notify_join"))
                        Toggle("Someone deletes or restores a trip", isOn: notify(\.notifyTripDeleted, "notify_trip_deleted"))
                    }
                    // Denied: dimmed, keeping what you chose, so turning permission back on restores it.
                    .disabled(permission == .denied)
                } header: { Text("Notify me when").accessibilityAddTraits(.isHeader) } footer: {
                    Text(permission == .denied ? "Turn notifications on in Settings to get these. Your choices here are kept."
                                               : "You’re never notified about your own changes.")
                }

                Section {
                    NavigationLink("App icon") { AppIconView() }
                }

                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }

                Section {
                    Button("Delete account", role: .destructive) { Task { await startDelete() } }.disabled(deleting)
                } footer: {
                    VStack(spacing: Spacing.lg) {
                        if (unsettled ?? 0) > 0 { Text("You can delete your account once you’re settled on every trip.") }
                        Text(Self.version).frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                await readPermission()
                unsettled = try? await app.unsettledTripCount()
            }
            .navigationDestination(isPresented: $settling) { SettleUpView(startTrip: nil) }
            .alert(deleteTitle, isPresented: .init(get: { deleteAlert != nil }, set: { if !$0 { deleteAlert = nil } }),
                   presenting: deleteAlert) { alert in
                Button("Cancel", role: .cancel) {}
                switch alert {
                case .notSettled: Button("Settle up") { settling = true }
                case .confirm: Button("Delete", role: .destructive) { Task { await deleteAccount() } }
                }
            } message: { alert in
                switch alert {
                case .notSettled(let n):
                    Text("You still have a balance on \(n == 1 ? "1 trip" : "\(n) trips"). You can delete your account once you’re settled everywhere.")
                case .confirm:
                    Text("You’ll leave every trip, and your name and pay methods are erased. Past expenses stay on each trip as “Deleted account.” This can’t be undone.")
                }
            }
            .onChange(of: scenePhase) { if scenePhase == .active { Task { await readPermission() } } }
            .alert("Sign out of TripSplit?", isPresented: $confirmSignOut) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive) { Task { await app.signOut() } }
            } message: { Text("Your trips and balances stay saved. Sign back in with Apple anytime.") }
            .failureAlert($failure)
        }
    }

    private var deleteTitle: String {
        if case .notSettled = deleteAlert { return "Settle Up First" }
        return "Delete Your Account?"
    }

    /// Checks your balances first: unsettled opens F6 (Settle up), settled opens F7 (confirm).
    private func startDelete() async {
        do {
            let n = try await app.unsettledTripCount()
            unsettled = n
            deleteAlert = n > 0 ? .notSettled(n) : .confirm
        } catch {
            failure = Failure(title: "Couldn’t check your balances", error: error) { await startDelete() }
        }
    }

    /// Deleting signs you out to the Sign in screen, also when the Apple revoke fails later.
    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do { try await app.deleteAccount() }
        catch { failure = Failure(title: "Couldn’t delete your account", error: error) { await deleteAccount() } }
    }

    /// "TripSplit 1.0 (12)".
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "TripSplit \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    private func readPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// The change shows at once (`ProfileSync`); if its save fails, it drops back to the saved value and Retry
    /// saves it again.
    private func save(_ fields: [String: AnyJSON]) {
        Task { await saveNow(fields) }
    }

    private func saveNow(_ fields: [String: AnyJSON]) async {
        do { try await app.updateProfile(fields) }
        catch { failure = Failure(title: "Couldn’t save", error: error) { await saveNow(fields) } }
    }

    private func payMethod(_ key: KeyPath<Profile, Bool>, _ column: String) -> Binding<Bool> {
        .init(get: { app.profile?[keyPath: key] ?? false }, set: { save([column: .bool($0)]) })
    }

    private func notify(_ key: KeyPath<Profile, Bool?>, _ column: String) -> Binding<Bool> {
        .init(get: { app.profile?[keyPath: key] ?? true }, set: { save([column: .bool($0)]) })
    }
}

/// Edit your full name (F4). Friends see the short form ("Taylor R."). Saves when you go back, if it isn't empty.
struct NameView: View {
    let name: String
    let onSave: (String) -> Void
    @State private var text = ""

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $text).textContentType(.name).submitLabel(.done)
            } header: { Text("Name") } footer: {
                Text(text.isEmpty ? "Friends see your name on every trip." : "Friends see “\(PersonName.shown(text))”.")
            }
        }
        .navigationTitle("Name").navigationBarTitleDisplayMode(.inline)
        .onAppear { text = name }
        .onDisappear {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != name { onSave(trimmed) }
        }
    }
}

/// Your Venmo username (F3), on Profile and in onboarding. Checked as you type; saved on back when valid (an empty
/// field or Remove Venmo means no Venmo). An invalid name isn't saved, and the error says why.
struct VenmoView: View {
    let username: String?
    let onSave: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var text = ""
    @State private var removed = false

    private var name: String { VenmoName.clean(text) }
    private var valid: Bool { VenmoName.isValid(name) }

    var body: some View {
        Form {
            Section {
                // A fixed, lighter "@" before the field (as in Venmo): you type only the name after it.
                HStack(spacing: 1) {
                    Text("@").foregroundStyle(Color.tsSecondary).accessibilityHidden(true)
                    TextField("username", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.done)
                        .accessibilityLabel("Venmo username")
                }
            } header: { Text("Venmo username") } footer: {
                if !name.isEmpty, !valid {
                    Text("Venmo usernames are 5–30 letters, numbers, - or _.").foregroundStyle(Color.tsOwe)
                } else if valid {
                    Text("Friends pay you at venmo.com/u/\(name). Saves when you go back.")
                } else {
                    Text("Letters, numbers, - and _ only. Saves when you go back.")
                }
            }
            Section {
                Button("Check in Venmo") { if let url = URL(string: "https://venmo.com/u/\(name)") { openURL(url) } }
                    .disabled(!valid)
            }
            if username != nil {
                Section {
                    Button("Remove Venmo", role: .destructive) { removed = true; dismiss() }
                }
            }
        }
        .navigationTitle("Venmo").navigationBarTitleDisplayMode(.inline)
        .onAppear { text = username ?? "" }
        .onDisappear {
            if removed || name.isEmpty { if username != nil { onSave(nil) } }
            else if valid, name != username { onSave(name) }
        }
    }
}
