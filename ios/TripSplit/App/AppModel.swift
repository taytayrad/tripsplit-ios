import Foundation
import Network
import Observation

import Supabase
import UIKit
import UserNotifications

/// App state and every backend call. Views read from it and call its methods.
@MainActor @Observable
final class AppModel {
    enum Stage: Equatable {
        case loading, signedOut, notifications, payMethods, ready

        static func afterSignIn(displayName: String?, onboarded: Bool) -> Self {
            guard onboarded else { return .notifications }
            // Apple may omit the name after account deletion. Repair existing blank accounts too.
            return displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? .ready : .payMethods
        }
    }

    var stage: Stage = .loading
    /// Your profile as shown: the server's, with any edits still saving laid on top (`ProfileSync`).
    var profile: Profile? { profileSync.shown }
    private var profileSync = ProfileSync()
    var trips: [Trip] = []
    /// Every suggested payment on your trips. Tickets, member amounts, and "Everyone's settled" come from these.
    var settlements: [Settlement] = []
    /// Your net on each trip.
    var nets: [UUID: Int] = [:]
    /// Payments on your trips, oldest first.
    var payments: [Payment] = []
    /// Your activity, newest first, including rows on a deleted trip.
    var activity: [ActivityEvent] = []
    /// Retained through sign-in/onboarding when a notification launches the app.
    var pushEventId: UUID?
    /// People you share a trip with ("On TripSplit"), with their pay methods.
    var people: [Profile] = []
    var pendingInvite: String? {
        didSet { UserDefaults.standard.set(pendingInvite, forKey: "pendingInvite"); inviteErrorShown = false }
    }
    /// A join that keeps failing the same way (trip full, offline) alerts once, not on every background refresh.
    private var inviteErrorShown = false
    var invitePreview: InvitePreview?
    /// Set after joining by link; drives the welcome modal.
    var welcomeTrip: Trip?
    var error: String?
    /// No network, per `NWPathMonitor`. Writes are refused before the request (`requireOnline`); the server still
    /// decides, since the monitor can be wrong.
    private(set) var isOffline = false
    private let pathMonitor = NWPathMonitor()
    /// A refresh has succeeded since sign-in, so what's on screen is a real (possibly empty) load.
    private(set) var loaded = false
    /// The first load failed with nothing loaded: Trips and Activity show Couldn’t load (Figma X8).
    private(set) var loadFailed = false
    /// Expenses on every trip you're on, newest first.
    var expenses: [Expense] = []
    /// The expense form, when it's open.
    var expenseSheet: ExpenseSheet?
    /// The trip you joined most recently by link; the expense form starts there (PRD › Default trip after an invite).
    private var justJoinedTrip: UUID?
    private var lastExpenseTrip: UUID? {
        get { UserDefaults.standard.string(forKey: "lastExpenseTrip").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "lastExpenseTrip") }
    }
    private var realtime: RealtimeChannelV2?
    private var realtimeSubscriptions: [RealtimeSubscription] = []  // dropping a token removes its callback
    private var refreshTask: Task<Void, Never>?
    /// The latest profile save; the next one waits for it.
    private var profileSave: Task<Void, Error>?

    private let db: SupabaseClient

    /// A user-facing message; Debug builds append the underlying error to speed up fixes.
    nonisolated static func describe(_ message: String, _ error: Error) -> String {
        #if DEBUG
        return message + "\n\n" + String(describing: error)
        #else
        return message
        #endif
    }
    var userId: UUID? { db.auth.currentUser?.id }

    init(db: SupabaseClient = Backend.client) {
        self.db = db
        pendingInvite = UserDefaults.standard.string(forKey: "pendingInvite")
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in self?.setOffline(offline) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "path-monitor"))
    }

    private func setOffline(_ offline: Bool) {
        guard offline != isOffline else { return }
        isOffline = offline
        if offline { AccessibilityNotification.Announcement("You’re offline").post() }
        else if stage == .ready { Task { await refresh() } }  // back online: catch up
    }

    /// Refuses a write before the request when there's no network (TRIP-33). The caller shows the failure alert.
    private func requireOnline() throws {
        if signingOut { throw CancellationError() }
        if isOffline { throw URLError(.notConnectedToInternet) }
    }

    // MARK: Session

    func start() async {
        for await (event, session) in db.auth.authStateChanges {
            guard [.initialSession, .signedIn, .signedOut].contains(event) else { continue }
            if session == nil {
                profileSync.reset(); profileSave = nil; trips = []; expenses = []; settlements = []; nets = [:]; payments = []; people = []; activity = []
                loaded = false; loadFailed = false
                stage = .signedOut
                await stopRealtime()
                await loadInvitePreview()
            } else {
                await afterSignIn()
                await startRealtime()
            }
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?, authorizationCode: String?) async {
        do {
            try await db.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
            // Store what Delete account needs to revoke Sign in with Apple (TRIP-28). The code is single-use; if the
            // exchange fails, sign-in still stands and the next sign-in tries again.
            if let authorizationCode {
                Task { try? await db.functions.invoke("apple", options: FunctionInvokeOptions(body: ["code": authorizationCode])) }
            }
            // Apple shares the name only on the very first sign-in.
            if let name = fullName.map({ PersonNameComponentsFormatter().string(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }), !name.isEmpty,
               let id = userId {
                try await db.from("profiles").update(["display_name": name]).eq("id", value: id).run()
                await loadProfile()
            }
        } catch { self.error = "Couldn't sign in. Try again." }
    }

    /// Deletes this phone's push token first (while still signed in, so the row is ours to delete), so pushes for
    /// this account stop arriving here. A token save still in flight finishes first, and none starts meanwhile, so
    /// it can't put the row back. If the delete fails (offline), the next account to register this phone takes the
    /// token over (`register_device_token`), so it never stays with the wrong person for long.
    func signOut() async {
        pushEventId = nil
        signingOut = true
        defer { signingOut = false }
        await tokenSave?.value
        if let token = deviceToken { try? await db.from("device_tokens").delete().eq("token", value: token).run() }
        try? await db.auth.signOut()
    }

    /// Trips, live or deleted, where you still have a balance: Delete account waits for 0 (TRIP-28).
    func unsettledTripCount() async throws -> Int {
        let count: Int = try await db.rpc("my_unsettled_trip_count").execute().value
        return count
    }

    /// Deletes your account, only at $0 everywhere, then signs out on this phone. The server deleted the sign-in, so
    /// the sign-out is local; Sign in with Apple is revoked after the server's commit.
    func deleteAccount() async throws {
        try requireOnline()
        signingOut = true
        defer { signingOut = false }
        await tokenSave?.value
        _ = await profileSave?.result
        try await db.rpc("delete_account").run()
        // The SDK clears its local session before attempting the server logout, which may now fail.
        try? await db.auth.signOut(scope: .local)
    }

    #if DEBUG
    /// Local development only: a throwaway account, so two simulators can act as two people.
    func signInAsTestPerson(_ name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Enter your name to continue."; return }
        do {
            try await db.auth.signInAnonymously()
            if let id = userId {
                try await db.from("profiles").update(["display_name": name]).eq("id", value: id).run()
                await loadProfile()
            }
        } catch { self.error = "Test sign-in failed. Is the local Supabase running?" }
    }
    #endif

    private func afterSignIn() async {
        await registerForPush()
        await loadProfile()
        guard let id = userId else { return }
        let onboarded = UserDefaults.standard.bool(forKey: "onboarded.\(id)")
        stage = Stage.afterSignIn(displayName: profile?.displayName, onboarded: onboarded)
        if stage == .ready { await refresh(); await joinPendingInvite() }
    }

    // MARK: Onboarding

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await registerForPush()
        stage = .payMethods
    }

    // MARK: Push token

    /// This phone's APNs token, once iOS has handed it over (never on the simulator). Kept across launches, so
    /// sign-out can delete it even after notifications were turned off (PR #36 review).
    private(set) var deviceToken: String? = UserDefaults.standard.string(forKey: "apnsToken") {
        didSet { UserDefaults.standard.set(deviceToken, forKey: "apnsToken") }
    }
    private var tokenSave: Task<Void, Never>?
    private var signingOut = false

    /// Asks iOS for this phone's push token when notifications are allowed; the token arrives in `saveDeviceToken`.
    /// Without permission nothing happens, and nothing waits on it.
    func registerForPush() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Registers this phone for whoever is signed in. The server takes the token away from any other account, so
    /// a phone gets one account's pushes at a time. Skipped while signing out.
    func saveDeviceToken(_ token: String) async {
        deviceToken = token
        guard userId != nil, !signingOut else { return }
        let previous = tokenSave
        let save = Task {
            await previous?.value
            _ = try? await db.rpc("register_device_token", params: ["p_token": token]).run()
        }
        tokenSave = save
        await save.value
    }

    func skipNotifications() { stage = .payMethods }

    func savePayMethods(name: String, venmo: String?, zelle: Bool, appleCash: Bool) async {
        guard let id = userId else { return }
        let venmo = venmo.map(VenmoName.clean)
        do {
            try requireOnline()
            try await db.from("profiles").update(PayMethodsUpdate(venmo_username: venmo?.isEmpty == false ? venmo : nil,
                                                        has_zelle: zelle, has_apple_cash: appleCash))
                .eq("id", value: id).run()
            await finishOnboarding(name: name)
        } catch { self.error = "Couldn't save. Check your connection and try again." }
    }

    func finishOnboarding(name: String) async {
        guard let id = userId else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Enter your name to continue."; return }
        do {
            try await updateProfile(["display_name": .string(name)])
        } catch {
            self.error = "Couldn't save your name. Check your connection and try again."
            return
        }
        UserDefaults.standard.set(true, forKey: "onboarded.\(id)")
        stage = .ready
        await refresh()
        await joinPendingInvite()
    }

    /// Saves fields on your own profile; Profile saves each change as it's made (no Save button). Keys are the
    /// `profiles` columns you may update (docs/permissions.md). The change shows at once (`ProfileSync`). Saves run
    /// one after another, in the order they were made, so the latest choice is the one saved. Throws only when the
    /// failure still matters: a newer pending save that rewrites the same fields makes an older failure moot.
    func updateProfile(_ fields: [String: AnyJSON]) async throws {
        guard let id = userId else { return }
        try requireOnline()
        let saveId = profileSync.begin(fields)
        let previous = profileSave
        let save = Task {
            _ = await previous?.result
            try await db.from("profiles").update(fields).eq("id", value: id).run()
        }
        profileSave = save
        do { try await save.value } catch {
            if profileSync.failed(saveId) { throw error }
            return
        }
        profileSync.saved(saveId)
        if profileSync.isSettled { await loadProfile() }
    }

    // MARK: Data

    func loadProfile() async {
        guard let id = userId else { return }
        let startedAt = profileSync.epoch
        // A failed load (offline) keeps the profile you had; a load overtaken by a newer save is dropped.
        if let loaded: Profile = try? await db.from("profiles").select().eq("id", value: id).single().value() {
            profileSync.loaded(loaded, startedAt: startedAt)
        }
    }

    func refresh() async {
        do {
            async let t: [Trip] = db.from("trips")
                .select("*, trip_members(user_id, position, removed_at, profiles!trip_members_user_id_fkey(id, display_name))")
                // Deleted trips stay off this list. Activity loads those rows on purpose.
                .is("deleted_at", value: nil).order("created_at", ascending: false).value()
            async let s: [Settlement] = allPages { from, to in
                try self.db.rpc("my_trip_settlements").order("trip_id").order("seq").range(from: from, to: to)
            }
            async let n: [TripNet] = allPages { from, to in
                try self.db.rpc("my_trip_nets").order("trip_id").range(from: from, to: to)
            }
            // Your own row too: onboarding and Profile change your pay methods, which the Payment page reads.
            async let me: Profile? = db.from("profiles").select("id, display_name, deleted_at, venmo_username, has_zelle, has_apple_cash, notify_paid, notify_expense, notify_join, notify_trip_deleted")
                .eq("id", value: userId ?? UUID()).single().value()
            async let p: [Profile] = db.from("profiles").select("id, display_name, deleted_at, venmo_username, has_zelle, has_apple_cash")
                .neq("id", value: userId ?? UUID()).value()
            async let e: [Expense] = allPages { from, to in
                self.db.from("expenses").select("*, expense_shares(user_id, share_cents, split_input)")
                    .order("spent_on", ascending: false).order("created_at", ascending: false).order("id").range(from: from, to: to)
            }
            async let pay: [Payment] = allPages { from, to in
                self.db.from("payments").select("id, trip_id, payer_id, payee_id, amount_cents, method, paid_on, created_at")
                    .is("deleted_at", value: nil).order("created_at").order("id").range(from: from, to: to)
            }
            // Newest first, including a deleted trip. A soft-deleted payment still embeds (no deleted_at filter).
            async let events: [ActivityEvent] = allPages { from, to in
                self.db.from("activity_events").select(ActivityQuery.columns)
                    .order("created_at", ascending: false).order("id").range(from: from, to: to)
            }
            let tripNets: [TripNet]
            let loadedProfile: Profile?
            let profileStartedAt = profileSync.epoch
            (trips, settlements, tripNets, loadedProfile, people, expenses, payments, activity) = try await (t, s, n, me, p, e, pay, events)
            if let loadedProfile { profileSync.loaded(loadedProfile, startedAt: profileStartedAt) }
            activity.removeAll { $0.kind == .unknown }
            nets = Dictionary(tripNets.map { ($0.tripId, $0.cents) }, uniquingKeysWith: +)
            loaded = true; loadFailed = false
        } catch {
            // What's on screen stays (TRIP-33). Only a first load with nothing to show becomes Couldn’t load.
            if !loaded { loadFailed = true }
        }
        if pendingInvite != nil, stage == .ready { await joinPendingInvite() }
        if realtime == nil, stage == .ready { await startRealtime() }
    }

    /// Every row of a query, in pages (the API caps a response at 1000 rows). The query must have a stable order.
    private func allPages<T: Decodable & Sendable>(_ page: (Int, Int) throws -> PostgrestTransformBuilder) async throws -> [T] {
        var all: [T] = []
        let size = 1000
        while true {
            let rows: [T] = try await page(all.count, all.count + size - 1).value()
            all += rows
            if rows.count < size { return all }
        }
    }

    /// The name to show for that person (`PersonName.shown`). "Someone" when we have none.
    func name(of user: UUID) -> String {
        let stored = people.first { $0.id == user }?.displayName.nilIfEmpty
            ?? trips.lazy.flatMap(\.tripMembers).first { $0.userId == user }?.profiles.displayName
        return stored.map(PersonName.shown) ?? "Someone"
    }

    func trip(_ id: UUID) -> Trip? { trips.first { $0.id == id } }

    func notificationTarget(_ id: UUID) async -> ActivityEvent.Target {
        await refresh()
        do {
            // refresh() keeps cached activity on failure; recheck this event's RLS before routing a push.
            let rows: [ActivityEvent] = try await db.from("activity_events").select(ActivityQuery.columns)
                .eq("id", value: id).value()
            return rows.first?.notificationTarget(expenses: Set(expenses.map(\.id)), trips: Set(trips.map(\.id))) ?? .activity
        } catch {
            self.error = Self.describe("Couldn’t open the notification. Check your connection and try again.", error)
            return .activity
        }
    }
    /// The trip's expenses, leaving out deleted ones (they open from Activity, not the trip's list).
    func expenses(on trip: UUID) -> [Expense] { expenses.filter { $0.tripId == trip && $0.deletedAt == nil } }
    func payments(on trip: UUID) -> [Payment] { payments.filter { $0.tripId == trip } }
    func profile(of user: UUID) -> Profile? { user == userId ? profile : people.first { $0.id == user } }

    // MARK: Realtime

    /// Any change on a money table re-queries everything, coalesced so a burst of rows is one refresh.
    private func startRealtime() async {
        guard realtime == nil else { return }
        let channel = db.channel("changes")
        // Not expenses or expense_shares: their DELETE events would reach every subscriber. Every change to
        // them writes an activity_events row, so that table is the signal. This refresh reloads activity too.
        for table in ["trips", "trip_members", "payments", "activity_events"] {
            realtimeSubscriptions.append(channel.onPostgresChange(AnyAction.self, schema: "public", table: table) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            })
        }
        do {
            try await channel.subscribeWithError()
            realtime = channel
        } catch {
            // Nil means the next refresh (pull, foreground) subscribes again.
            realtimeSubscriptions = []
            await db.removeChannel(channel)
            self.error = Self.describe("Live updates are off. Pull to refresh.", error)
        }
    }

    private func stopRealtime() async {
        refreshTask?.cancel(); refreshTask = nil
        if let realtime { await db.removeChannel(realtime) }
        realtime = nil; realtimeSubscriptions = []
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    // MARK: Expenses

    /// Opens the form on `trip`, or on the default trip (PRD › Expenses) when nil.
    func addExpense(on trip: UUID? = nil) {
        guard let id = trip ?? DefaultTrip.choose(justJoined: justJoinedTrip, lastUsed: lastExpenseTrip, tripsNewestFirst: trips.map(\.id)) else { return }
        expenseSheet = .add(tripId: id)
    }

    func saveExpense(_ args: SaveExpenseArgs) async throws {
        try requireOnline()
        let _: UUID = try await db.rpc("save_expense", params: args).value()
        lastExpenseTrip = args.p_trip
        justJoinedTrip = nil
        await refresh()
    }

    func deleteExpense(_ id: UUID) async throws {
        try requireOnline()
        try await db.rpc("delete_expense", params: ["p_expense": id]).run()
        await refresh()
    }

    /// Puts a deleted expense back. Refused when someone on it has left the trip, or the trip is deleted.
    func restoreExpense(_ id: UUID) async throws {
        try requireOnline()
        try await db.rpc("restore_expense", params: ["p_expense": id]).run()
        await refresh()
    }

    // MARK: Payments

    /// Logs a payment with `other`, one row per trip in `parts`: `pay` when you paid them, `record` when they paid you.
    /// Retrying with the same `requestId` creates nothing new. Returns the rows the server stored.
    func logPayment(with other: UUID, direction: SettleDirection, method: PayMethod, paidOn: Date, parts: [PaymentPart],
                    requestId: UUID) async throws -> [LoggedPayment] {
        try requireOnline()
        let rows: [LoggedPayment] = try await db.rpc("log_payment", params: LogPaymentArgs(
            p_other: other, p_direction: direction == .pay ? "pay" : "record", p_method: method.rawValue,
            p_request_id: requestId, p_paid_on: DayFormat.string(paidOn), p_parts: parts)).value()
        await refresh()
        return rows
    }

    func deletePayment(_ id: UUID) async throws {
        try requireOnline()
        try await db.rpc("delete_payment", params: ["p_payment": id]).run()
        await refresh()
    }

    // MARK: Trips

    func createTrip(name: String, stamp: StampSpec, start: Date?, end: Date?) async throws -> Trip {
        try requireOnline()
        let id: UUID = try await db.rpc("create_trip", params: CreateTripArgs(
            p_name: name, p_stamp: stamp, p_start_date: start.map(DayFormat.string), p_end_date: end.map(DayFormat.string)
        )).value()
        await refresh()
        guard let trip = trip(id) else { throw URLError(.badServerResponse) }
        return trip
    }

    func updateTrip(_ id: UUID, name: String, stamp: StampSpec?, start: Date?, end: Date?) async throws {
        try requireOnline()
        try await db.from("trips").update(TripDetailsUpdate(name: name, stamp: stamp, start_date: start.map(DayFormat.string), end_date: end.map(DayFormat.string)))
            .eq("id", value: id).run()
        await refresh()
    }

    /// Deletes the trip. The caller refreshes after closing the trip's screens, so the trip doesn't vanish
    /// from under them mid-animation.
    func deleteTrip(_ id: UUID) async throws {
        try requireOnline()
        try await db.rpc("delete_trip", params: ["p_trip": id]).run()
    }

    /// Brings a deleted trip back with the expenses and payments it had when it was deleted (money-rules M7).
    func undeleteTrip(_ id: UUID) async throws {
        try requireOnline()
        try await db.rpc("undelete_trip", params: ["p_trip": id]).run()
        await refresh()
    }

    func addMember(_ user: UUID, to trip: UUID) async throws {
        try requireOnline()
        try await db.rpc("add_member", params: ["p_trip": trip, "p_user": user]).run()
        await refresh()
    }

    /// Only someone at $0 on the trip can be removed (TRIP-14); the server refuses otherwise.
    func removeMember(_ user: UUID, from trip: UUID) async throws {
        try requireOnline()
        try await db.rpc("remove_member", params: ["p_trip": trip, "p_user": user]).run()
        await refresh()
    }

    /// Leaves the trip; only at $0. Like `deleteTrip`, the caller refreshes after closing the trip's screens.
    func leaveTrip(_ trip: UUID) async throws {
        try requireOnline()
        try await db.rpc("leave_trip", params: ["p_trip": trip]).run()
    }

    // MARK: Invites

    func open(_ url: URL) async {
        guard let token = InviteLink.token(from: url) else { return }
        pendingInvite = token
        if stage == .ready { await joinPendingInvite() } else { await loadInvitePreview() }
    }

    private func loadInvitePreview() async {
        guard let token = pendingInvite else { invitePreview = nil; return }
        let rows: [InvitePreview] = (try? await db.rpc("invite_preview", params: ["p_invite_token": token]).value()) ?? []
        invitePreview = rows.first
    }

    private func joinPendingInvite() async {
        guard let token = pendingInvite else { return }
        do {
            let alreadyOn = trips.contains { $0.inviteToken == token }
            let id: UUID = try await db.rpc("join_trip", params: ["p_invite_token": token]).value()
            pendingInvite = nil; invitePreview = nil
            await refresh()
            // Someone already on the trip just opens it; newcomers get the welcome.
            if !alreadyOn { welcomeTrip = trip(id); justJoinedTrip = id }
        } catch let e as PostgrestError where e.message.contains("invite link not found") {
            pendingInvite = nil
            self.error = "That invite link didn't work. Ask for a new one."
        } catch let e as PostgrestError where e.message.contains("removed from this trip") {
            pendingInvite = nil
            self.error = "You were removed from that trip. Ask a member to add you back."
        } catch {
            // Keep the token so pull-to-refresh retries the join; say why once.
            guard !inviteErrorShown else { return }
            inviteErrorShown = true
            if let e = error as? PostgrestError, e.message.contains("at most 20 members") {
                self.error = "That trip is full (20 people). Once someone leaves, pull to retry."
            } else {
                self.error = Self.describe("Couldn't join the trip yet. Pull to retry.", error)
            }
        }
    }
}
