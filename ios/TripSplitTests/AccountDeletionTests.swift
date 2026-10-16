import Foundation
import Supabase
import Testing
@testable import TripSplit

struct AccountDeletionTests {
    @Test(.timeLimit(.minutes(1))) @MainActor
    func deletionDrainsSavesAndRefusesNewWrites() async throws {
        let oldToken = UserDefaults.standard.string(forKey: "apnsToken")
        defer { UserDefaults.standard.set(oldToken, forKey: "apnsToken") }
        let server = AccountServer()
        AccountURLProtocol.server = server
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountURLProtocol.self]
        let db = SupabaseClient(supabaseURL: URL(string: "https://account-test.local")!, supabaseKey: "test",
                                options: .init(auth: .init(storage: AccountStorage(), autoRefreshToken: false),
                                               global: .init(session: URLSession(configuration: config))))
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
}

private actor AccountServer {
    let id = "00000000-0000-0000-0000-000000000028"
    var events: [String] = []
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    private var held: [String: CheckedContinuation<Void, Never>] = [:]

    func waitFor(_ event: String) async {
        if events.contains(event) { return }
        await withCheckedContinuation { waiting[event] = $0 }
    }

    func release(_ route: String) { held.removeValue(forKey: route)?.resume() }

    func respond(_ request: URLRequest) async -> (Int, Data) {
        let route = "\(request.httpMethod ?? "GET") \(request.url!.path)"
        events.append("start:" + route)
        waiting.removeValue(forKey: "start:" + route)?.resume()
        if ["PATCH /rest/v1/profiles", "POST /rest/v1/rpc/register_device_token", "POST /rest/v1/rpc/delete_account"].contains(route) {
            await withCheckedContinuation { held[route] = $0 }
        }
        events.append("end:" + route)
        if request.url!.path == "/auth/v1/signup" {
            let body: [String: Any] = ["access_token": "test", "token_type": "bearer", "expires_in": 3600,
                                      "expires_at": Date.now.timeIntervalSince1970 + 3600, "refresh_token": "test",
                                      "user": ["id": id, "aud": "authenticated", "app_metadata": [:], "user_metadata": [:],
                                               "created_at": "2026-10-15T00:00:00Z", "updated_at": "2026-10-15T00:00:00Z",
                                               "is_anonymous": true]]
            return (200, try! JSONSerialization.data(withJSONObject: body))
        }
        if route == "GET /rest/v1/profiles" {
            return (200, Data("{\"id\":\"\(id)\",\"display_name\":\"Sam\",\"has_zelle\":false,\"has_apple_cash\":false}".utf8))
        }
        if request.url!.path == "/auth/v1/logout" { return (400, Data("{\"msg\":\"Logout failed\"}".utf8)) }
        return (204, Data())
    }
}

private final class AccountURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var server: AccountServer!
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

private final class AccountStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: Data] = [:]
    func store(key: String, value: Data) { lock.withLock { data[key] = value } }
    func retrieve(key: String) -> Data? { lock.withLock { data[key] } }
    func remove(key: String) { lock.withLock { _ = data.removeValue(forKey: key) } }
}
