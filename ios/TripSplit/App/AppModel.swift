import Foundation
import Observation

import Supabase
import UserNotifications

/// App state and every backend call. Views read from it and call its methods.
@MainActor @Observable
final class AppModel {
    enum Stage: Equatable { case loading, signedOut, notifications, payMethods, ready }

    var stage: Stage = .loading
    var profile: Profile?
    var trips: [Trip] = []
    var nets: [UUID: Int] = [:]
    var headerTotal = 0
    /// People you share a trip with ("On TripSplit").
    var people: [PersonName] = []
    var pendingInvite: String? {
        didSet { UserDefaults.standard.set(pendingInvite, forKey: "pendingInvite") }
    }
    var invitePreview: InvitePreview?
    /// Set after joining by link; drives the welcome modal.
    var welcomeTrip: Trip?
    var error: String?
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

    private let db = Backend.client

    /// A user-facing message; Debug builds append the underlying error to speed up fixes.
    static func describe(_ message: String, _ error: Error) -> String {
        #if DEBUG
        return message + "\n\n" + String(describing: error)
        #else
        return message
        #endif
    }
    var userId: UUID? { db.auth.currentUser?.id }

    init() {
        pendingInvite = UserDefaults.standard.string(forKey: "pendingInvite")
    }

    // MARK: Session

    func start() async {
        for await (event, session) in db.auth.authStateChanges {
            guard [.initialSession, .signedIn, .signedOut].contains(event) else { continue }
            if session == nil {
                profile = nil; trips = []; expenses = []
                stage = .signedOut
                await stopRealtime()
                await loadInvitePreview()
            } else {
                await afterSignIn()
                await startRealtime()
            }
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async {
        do {
            try await db.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
            // Apple shares the name only on the very first sign-in.
            if let name = fullName.map({ PersonNameComponentsFormatter().string(from: $0) }), !name.isEmpty,
               let id = userId {
                try await db.from("profiles").update(["display_name": name]).eq("id", value: id).run()
            }
        } catch { self.error = "Couldn't sign in. Try again." }
    }

    func signOut() async { try? await db.auth.signOut() }

    #if DEBUG
    /// Local development only: a throwaway account, so two simulators can act as two people.
    func signInAsTestPerson(_ name: String) async {
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
        await loadProfile()
        guard let id = userId else { return }
        let onboarded = UserDefaults.standard.bool(forKey: "onboarded.\(id)")
        stage = onboarded ? .ready : .notifications
        if onboarded { await refresh(); await joinPendingInvite() }
    }

    // MARK: Onboarding

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        stage = .payMethods
    }

    func skipNotifications() { stage = .payMethods }

    func savePayMethods(venmo: String?, zelle: Bool, appleCash: Bool) async {
        guard let id = userId else { return }
        let venmo = venmo?.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        do {
            try await db.from("profiles").update(PayMethodsUpdate(venmo_username: venmo?.isEmpty == false ? venmo : nil,
                                                        has_zelle: zelle, has_apple_cash: appleCash))
                .eq("id", value: id).run()
            await finishOnboarding()
        } catch { self.error = "Couldn't save. Check your connection and try again." }
    }

    func finishOnboarding() async {
        guard let id = userId else { return }
        UserDefaults.standard.set(true, forKey: "onboarded.\(id)")
        stage = .ready
        await refresh()
        await joinPendingInvite()
    }

    // MARK: Data

    func loadProfile() async {
        guard let id = userId else { return }
        profile = try? await db.from("profiles").select().eq("id", value: id).single().value()
    }

    func refresh() async {
        do {
            async let t: [Trip] = db.from("trips")
                .select("*, trip_members(user_id, position, removed_at, profiles!trip_members_user_id_fkey(id, display_name))")
                .is("deleted_at", value: nil).order("created_at", ascending: false).value()
            async let n: [TripNet] = db.rpc("my_trip_nets").value()
            async let h: Int = db.rpc("my_header_total").value()
            async let p: [PersonName] = db.from("profiles").select("id, display_name").neq("id", value: userId ?? UUID()).value()
            async let e: [Expense] = db.from("expenses").select("*, expense_shares(user_id, share_cents, split_input)")
                .order("spent_on", ascending: false).order("created_at", ascending: false).value()
            (trips, nets, headerTotal, people, expenses) = try await (t, Dictionary(uniqueKeysWithValues: n.map { ($0.tripId, $0.cents) }), h, p, e)
        } catch { self.error = Self.describe("Couldn't load your trips. Pull to retry.", error) }
        if pendingInvite != nil, stage == .ready { await joinPendingInvite() }
    }

    func trip(_ id: UUID) -> Trip? { trips.first { $0.id == id } }
    func expenses(on trip: UUID) -> [Expense] { expenses.filter { $0.tripId == trip } }

    // MARK: Realtime

    /// Any change on a money table re-queries everything, coalesced so a burst of rows is one refresh.
    private func startRealtime() async {
        guard realtime == nil else { return }
        let channel = db.channel("changes")
        for table in ["trips", "trip_members", "expenses", "expense_shares", "payments", "activity_events"] {
            realtimeSubscriptions.append(channel.onPostgresChange(AnyAction.self, schema: "public", table: table) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            })
        }
        realtime = channel
        do { try await channel.subscribeWithError() } catch { print("realtime subscribe failed:", error) }
    }

    private func stopRealtime() async {
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
        let _: UUID = try await db.rpc("save_expense", params: args).value()
        lastExpenseTrip = args.p_trip
        justJoinedTrip = nil
        await refresh()
    }

    func deleteExpense(_ id: UUID) async throws {
        try await db.rpc("delete_expense", params: ["p_expense": id]).run()
        await refresh()
    }

    // MARK: Trips

    func createTrip(name: String, stamp: StampSpec, start: Date?, end: Date?) async throws -> Trip {
        let id: UUID = try await db.rpc("create_trip", params: CreateTripArgs(
            p_name: name, p_stamp: stamp, p_start_date: start.map(DayFormat.string), p_end_date: end.map(DayFormat.string)
        )).value()
        await refresh()
        guard let trip = trip(id) else { throw URLError(.badServerResponse) }
        return trip
    }

    func updateTrip(_ id: UUID, name: String, start: Date?, end: Date?) async throws {
        try await db.from("trips").update(TripDetailsUpdate(name: name, start_date: start.map(DayFormat.string), end_date: end.map(DayFormat.string)))
            .eq("id", value: id).run()
        await refresh()
    }

    func deleteTrip(_ id: UUID) async throws {
        try await db.rpc("delete_trip", params: ["p_trip": id]).run()
        await refresh()
    }

    func addMember(_ user: UUID, to trip: UUID) async throws {
        try await db.rpc("add_member", params: ["p_trip": trip, "p_user": user]).run()
        await refresh()
    }

    func removeMember(_ user: UUID, from trip: UUID, keepBalance: Bool) async throws {
        try await db.rpc("remove_member", params: RemoveMemberArgs(p_trip: trip, p_user: user, p_mode: keepBalance ? "keep" : "wipe")).run()
        await refresh()
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
            // Offline or a full trip: keep the token so pull-to-refresh retries the join.
            self.error = Self.describe("Couldn't join the trip yet. Pull to retry.", error)
        }
    }
}
