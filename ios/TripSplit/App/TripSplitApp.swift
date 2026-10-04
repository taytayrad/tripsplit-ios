import SwiftUI

@main
struct TripSplitApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { await app.start() }
                .onOpenURL { url in Task { await app.open(url) } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, app.stage == .ready { Task { await app.refresh() } }
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
