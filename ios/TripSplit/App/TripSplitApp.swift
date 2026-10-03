import SwiftUI

@main
struct TripSplitApp: App {
    var body: some Scene {
        WindowGroup {
            // Phase 0: the design system check is the whole app.
            DesignSystemDebugView()
        }
    }
}
