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
    @State private var failedSave: (() async -> Void)?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { NameView(name: app.profile?.displayName ?? "") { name in
                        save(["display_name": .string(name)], apply: { app.profile?.displayName = name })
                    } } label: {
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
                            save(["venmo_username": name.map(AnyJSON.string) ?? .null], apply: { app.profile?.venmoUsername = name })
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
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }

                Section {
                    // ponytail: shown but inactive until Delete account ships (TRIP-28).
                    Button("Delete account", role: .destructive) {}.disabled(true)
                } footer: {
                    VStack(spacing: Spacing.lg) {
                        Text("You can delete your account once you’re settled on every trip.")
                        Text(Self.version).frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Profile")
            .task { await readPermission() }
            .onChange(of: scenePhase) { if scenePhase == .active { Task { await readPermission() } } }
            .alert("Sign out of TripSplit?", isPresented: $confirmSignOut) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive) { Task { await app.signOut() } }
            } message: { Text("Your trips and balances stay saved. Sign back in with Apple anytime.") }
            .alert("Couldn’t save", isPresented: .init(get: { failedSave != nil }, set: { if !$0 { failedSave = nil } })) {
                Button("Cancel", role: .cancel) {}
                Button("Retry") { if let retry = failedSave { Task { await retry() } } }
            } message: { Text("Check your connection and try again.") }
        }
    }

    /// "TripSplit 1.0 (12)".
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "TripSplit \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    private func readPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// `apply` shows the change at once. If the save fails, AppModel puts the confirmed value back (`ProfileSync`),
    /// and Retry applies the change again.
    private func save(_ fields: [String: AnyJSON], apply: (() -> Void)? = nil) {
        apply?()
        Task {
            do { try await app.updateProfile(fields) }
            catch { failedSave = { save(fields, apply: apply) } }
        }
    }

    private func payMethod(_ key: WritableKeyPath<Profile, Bool>, _ column: String) -> Binding<Bool> {
        .init(get: { app.profile?[keyPath: key] ?? false },
              set: { new in save([column: .bool(new)], apply: { app.profile?[keyPath: key] = new }) })
    }

    private func notify(_ key: WritableKeyPath<Profile, Bool?>, _ column: String) -> Binding<Bool> {
        .init(get: { app.profile?[keyPath: key] ?? true },
              set: { new in save([column: .bool(new)], apply: { app.profile?[keyPath: key] = new }) })
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
