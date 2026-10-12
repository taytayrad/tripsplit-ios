import SwiftUI

/// A write that didn't reach the server, offline or not (TRIP-33, Figma X7). One alert everywhere: the site's own
/// title, "Check your connection and try again.", Cancel then Retry.
struct Failure: Identifiable {
    let id = UUID()
    let title: String
    var error: Error?
    /// Runs the write again. If it fails again it sets a new `Failure`, which shows without a second haptic.
    let retry: () async -> Void

    var message: String {
        error.map { AppModel.describe("Check your connection and try again.", $0) } ?? "Check your connection and try again."
    }
}

extension View {
    func failureAlert(_ failure: Binding<Failure?>) -> some View { modifier(FailureAlert(failure: failure)) }
}

private struct FailureAlert: ViewModifier {
    @Binding var failure: Failure?
    /// The failure on screen. It appears a beat after `failure` is set: an offline write fails instantly, often
    /// while a confirmation (Delete, Restore, Leave) or this alert's own Retry is still animating away, and an alert
    /// presented during that animation is silently dropped.
    @State private var shown: Failure?
    @State private var retrying = false
    @State private var warnings = 0

    func body(content: Content) -> some View {
        content
            .alert(shown?.title ?? "", isPresented: .init(get: { shown != nil }, set: { if !$0 { dismiss() } }), presenting: shown) { f in
                Button("Cancel", role: .cancel) {}
                Button("Retry") {
                    retrying = true
                    Task {
                        await f.retry()
                        retrying = false
                    }
                }
                .keyboardShortcut(.defaultAction)
            } message: { f in Text(f.message) }
            .onChange(of: failure?.id) {
                guard let f = failure else { return }
                let silent = retrying  // `warning` once per failure: a failed Retry re-shows silently
                Task {
                    try? await Task.sleep(for: .milliseconds(450))  // an alert's dismiss animation
                    guard failure?.id == f.id else { return }
                    if !silent { warnings += 1 }
                    shown = f
                }
            }
            .sensoryFeedback(Motion.Haptic.warning.feedback, trigger: warnings)
    }

    /// Clears only the failure that was on screen, never a newer one a Retry set meanwhile.
    private func dismiss() {
        if failure?.id == shown?.id { failure = nil }
        shown = nil
    }
}

/// Figma Offline Banner (X1–X6): a quiet strip in the flow, never over the content. VoiceOver reads it as one line.
struct OfflineBanner: View {
    let message: String
    var body: some View {
        Label { Text(message) } icon: { Image(systemName: "wifi.slash").foregroundStyle(Color.tsSecondary) }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.sm).padding(.horizontal, Spacing.md)
            .background(Color(.systemGray5), in: .rect(cornerRadius: Radius.md))
            .accessibilityElement(children: .combine)
    }
}

extension OfflineBanner {
    static let reading = "You’re offline. Showing your last update."
    static let expense = "You’re offline. Connect to save this expense."
    static let payment = "You’re offline. Connect to log this payment."
}
