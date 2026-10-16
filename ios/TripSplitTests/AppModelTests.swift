import Foundation
import Supabase
import Testing
@testable import TripSplit

@Suite(.serialized)
struct AppModelTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["trips", "failure", "signedOut"])
    @MainActor func coldLaunchWaitsForItsFirstLoad(_ result: String) async throws {
        let server = AppServer()
        await server.holdTrips(result)
        let storage = AppStorage()
        let signedIn = client(server: server, storage: storage)
        try await signedIn.auth.signInAnonymously()
        let key = "onboarded.\(try #require(signedIn.auth.currentUser?.id))"
        // A cold launch creates both the client and app model again, retaining only saved credentials.
        let db = client(server: server, storage: storage)
        let oldOnboarded = UserDefaults.standard.object(forKey: key)
        let oldInvite = UserDefaults.standard.string(forKey: "pendingInvite")
        defer {
            UserDefaults.standard.set(oldOnboarded, forKey: key)
            UserDefaults.standard.set(oldInvite, forKey: "pendingInvite")
        }
        UserDefaults.standard.set(true, forKey: key)
        let app = AppModel(db: db)
        app.pendingInvite = nil
        let session = Task { await app.start() }
        defer { session.cancel() }
        await server.waitFor("start:GET /rest/v1/trips")

        #expect(app.stage == .loading)
        if result == "signedOut" { try? await db.auth.signOut(scope: .local) }
        await server.release("GET /rest/v1/trips")
        while app.stage == .loading { try await Task.sleep(for: .milliseconds(1)) }
        #expect(app.stage == (result == "signedOut" ? .signedOut : .ready))
        #expect(app.loaded == (result == "trips"))
        #expect(app.loadFailed == (result == "failure"))
        #expect(app.trips.map(\.name) == (result == "trips" ? ["Weekend away"] : []))
        if result == "signedOut" { #expect(app.error == nil) }

        session.cancel()
        await session.value
    }

    @Test(.timeLimit(.minutes(1)), arguments: [true, false]) @MainActor
    func pendingInviteFinishesBeforeTripsOpen(returning: Bool) async throws {
        let server = AppServer()
        await server.holdTrips("invite")
        let db = client(server: server)
        try await db.auth.signInAnonymously()
        let key = "onboarded.\(try #require(db.auth.currentUser?.id))"
        let oldOnboarded = UserDefaults.standard.object(forKey: key)
        let oldInvite = UserDefaults.standard.string(forKey: "pendingInvite")
        defer {
            UserDefaults.standard.set(oldOnboarded, forKey: key)
            UserDefaults.standard.set(oldInvite, forKey: "pendingInvite")
        }
        UserDefaults.standard.set(returning, forKey: key)
        let app = AppModel(db: db)
        app.pendingInvite = "test"
        if !returning { app.stage = .payMethods }
        let entry = Task {
            if returning { await app.start() }
            else { await app.finishOnboarding(name: "Sam") }
        }
        defer { entry.cancel() }
        await server.waitFor("start:POST /rest/v1/rpc/join_trip")
        #expect(app.stage == (returning ? .loading : .payMethods))
        #expect(app.trips.isEmpty)
        await server.release("POST /rest/v1/rpc/join_trip")
        while app.stage != .ready { try await Task.sleep(for: .milliseconds(1)) }
        #expect(app.pendingInvite == nil)
        #expect(app.trips.map(\.name) == ["Weekend away"])
        #expect(app.welcomeTrip?.id == app.trips.first?.id)
        #expect(app.welcomeTrip != nil)
        entry.cancel()
        await entry.value
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func deletionDrainsSavesAndRefusesNewWrites() async throws {
        let oldToken = UserDefaults.standard.string(forKey: "apnsToken")
        defer { UserDefaults.standard.set(oldToken, forKey: "apnsToken") }
        let server = AppServer()
        let db = client(server: server)
        let app = AppModel(db: db)
        await app.signInAsTestPerson(" \n\t ")
        #expect(app.error == "Enter your name to continue.")
        #expect(await server.events.isEmpty)
        try await db.auth.signInAnonymously()
        let profile = Task { try await app.updateProfile(["display_name": .string("Sam")]) }
        let token = Task { await app.saveDeviceToken("first-token") }
        await server.waitFor("start:PATCH /rest/v1/profiles")
        await server.waitFor("start:POST /rest/v1/rpc/register_device_token")
        let deletion = Task { try await app.deleteAccount() }
        await server.release("PATCH /rest/v1/profiles")
        await server.release("POST /rest/v1/rpc/register_device_token")
        try await profile.value
        await token.value
        await server.waitFor("start:POST /rest/v1/rpc/delete_account")

        do {
            try await app.updateProfile(["has_zelle": .bool(true)])
            Issue.record("A new profile save was allowed during deletion")
        } catch { #expect(error is CancellationError) }
        await app.saveDeviceToken("late-token")
        await server.release("POST /rest/v1/rpc/delete_account")
        try await deletion.value

        let events = await server.events
        let deleted = try #require(events.firstIndex(of: "start:POST /rest/v1/rpc/delete_account"))
        #expect(try #require(events.firstIndex(of: "end:PATCH /rest/v1/profiles")) < deleted)
        #expect(try #require(events.firstIndex(of: "end:POST /rest/v1/rpc/register_device_token")) < deleted)
        #expect(events.filter { $0 == "start:POST /rest/v1/rpc/register_device_token" }.count == 1)
        #expect(db.auth.currentUser == nil)  // Logout returns an error, but local credentials are already gone.
    }

    private func client(server: AppServer, storage: AppStorage = AppStorage()) -> SupabaseClient {
        AppURLProtocol.server = server
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AppURLProtocol.self]
        return SupabaseClient(supabaseURL: URL(string: "https://app-test.local")!, supabaseKey: "test",
                              options: .init(auth: .init(storage: storage, autoRefreshToken: false),
                                             global: .init(session: URLSession(configuration: config)),
                                             realtime: .init(maxRetryAttempts: 0)))
    }
}

private actor AppServer {
    let id = "00000000-0000-0000-0000-000000000028"
    var events: [String] = []
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    private var held: [String: CheckedContinuation<Void, Never>] = [:]
    private var tripsResult: String?
    private var joinedInvite = false

    func holdTrips(_ result: String) {
        tripsResult = result
    }

    func waitFor(_ event: String) async {
        if events.contains(event) { return }
        await withCheckedContinuation { waiting[event] = $0 }
    }

    func release(_ route: String) { held.removeValue(forKey: route)?.resume() }

    func respond(_ request: URLRequest) async -> (Int, Data) {
        let route = "\(request.httpMethod ?? "GET") \(request.url!.path)"
        events.append("start:" + route)
        waiting.removeValue(forKey: "start:" + route)?.resume()
        if (tripsResult == nil && ["PATCH /rest/v1/profiles", "POST /rest/v1/rpc/register_device_token", "POST /rest/v1/rpc/delete_account"].contains(route))
            || route == "POST /rest/v1/rpc/join_trip"
            || (route == "GET /rest/v1/trips" && tripsResult != nil && tripsResult != "invite") {
            await withCheckedContinuation { held[route] = $0 }
        }
        events.append("end:" + route)
        if route == "POST /rest/v1/rpc/join_trip" {
            joinedInvite = true
            return (200, Data("\"\(id)\"".utf8))
        }
        if request.url!.path == "/auth/v1/signup" {
            let body: [String: Any] = ["access_token": "test", "token_type": "bearer", "expires_in": 3600,
                                      "expires_at": Date.now.timeIntervalSince1970 + 3600, "refresh_token": "test",
                                      "user": ["id": id, "aud": "authenticated", "app_metadata": [:], "user_metadata": [:],
                                               "created_at": "2026-10-15T00:00:00Z", "updated_at": "2026-10-15T00:00:00Z",
                                               "is_anonymous": true]]
            return (200, try! JSONSerialization.data(withJSONObject: body))
        }
        if route == "GET /rest/v1/profiles" {
            if request.url!.query?.contains("neq.") == true { return (200, Data("[]".utf8)) }
            return (200, Data("{\"id\":\"\(id)\",\"display_name\":\"Sam\",\"has_zelle\":false,\"has_apple_cash\":false}".utf8))
        }
        if route == "GET /rest/v1/trips" {
            if tripsResult == "failure" { return (400, Data("{\"message\":\"Couldn’t load\"}".utf8)) }
            let trip = """
            [{"id":"\(id)","name":"Weekend away","stamp":{"shape":"ticket","glyph":"road","ink":"blue","rotation":-6,"offsetX":0,"offsetY":0},"invite_token":"test","created_by":"\(id)","created_at":"2026-10-15T00:00:00Z","trip_members":[]}]
            """
            return (200, Data((tripsResult == "trips" || joinedInvite ? trip : "[]").utf8))
        }
        if request.url!.path == "/auth/v1/logout" { return (400, Data("{\"msg\":\"Logout failed\"}".utf8)) }
        if ["/rest/v1/rpc/my_trip_nets", "/rest/v1/rpc/my_trip_settlements"].contains(request.url!.path) {
            return (200, Data("[]".utf8))
        }
        if request.httpMethod == "GET" { return (200, Data("[]".utf8)) }
        return (204, Data())
    }
}

private final class AppURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var server: AppServer!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task {
            let (status, data) = await Self.server.respond(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private final class AppStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: Data] = [:]
    func store(key: String, value: Data) { lock.withLock { data[key] = value } }
    func retrieve(key: String) -> Data? { lock.withLock { data[key] } }
    func remove(key: String) { lock.withLock { _ = data.removeValue(forKey: key) } }
}
