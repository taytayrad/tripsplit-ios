import SwiftUI
import UserNotifications

@main
struct TripSplitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task {
                    delegate.onDeviceToken = { token in Task { await app.saveDeviceToken(token) } }
                    delegate.onNotification = { app.pushEventId = $0 }
                    await app.start()
                }
                .onOpenURL { url in Task { await app.open(url) } }
                .onChange(of: scenePhase) { _, phase in
                    // Also re-register: notifications may have been turned on in Settings while away.
                    if phase == .active, app.stage == .ready { Task { await app.refresh(); await app.registerForPush() } }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            switch app.stage {
            case .loading: Color(.systemGroupedBackground)
            case .signedOut: SignInView()
            case .notifications: NotificationsView()
            case .payMethods: PayMethodsView()
            case .ready: MainView()
            }
        }
        .animation(.default, value: app.stage)
        .alert("Something went wrong", isPresented: .init(get: { app.error != nil }, set: { if !$0 { app.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(app.error ?? "") }
    }
}

/// Receives the APNs token from iOS (TRIP-23). A failure (the simulator, or no network) is ignored: push is
/// optional and nothing waits on it.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var onDeviceToken: ((String) -> Void)?
    var onNotification: ((UUID) -> Void)? {
        didSet {
            if let id = pendingNotification, let onNotification {
                pendingNotification = nil
                onNotification(id)
            }
        }
    }
    private var pendingNotification: UUID?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let id = Self.eventId(response.notification.request.content.userInfo) else { return }
        await receiveNotification(id)
    }

    /// A cold-launch tap can arrive before SwiftUI connects the app model.
    func receiveNotification(_ id: UUID) {
        if let onNotification { onNotification(id) } else { pendingNotification = id }
    }

    nonisolated static func eventId(_ payload: [AnyHashable: Any]) -> UUID? {
        (payload["activity_event_id"] as? String).flatMap(UUID.init(uuidString:))
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        onDeviceToken?(Self.hex(deviceToken))
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    /// APNs wants the token as lowercase hex.
    nonisolated static func hex(_ token: Data) -> String { token.map { String(format: "%02x", $0) }.joined() }
}
