import SwiftUI

/// A write that didn't reach the server, offline or not (TRIP-33, Figma X7). One alert everywhere: the site's own
/// title, "Check your connection and try again.", Cancel then Retry.
struct Failure {
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
    /// Retry tapped; runs once the alert has closed. An alert presented while the last one is still animating away
    /// is silently dropped, and an offline Retry fails instantly, so the retry waits out the dismissal.
    @State private var pendingRetry: Failure?
    @State private var retrying = false
    @State private var warnings = 0

    func body(content: Content) -> some View {
        content
            .alert(failure?.title ?? "", isPresented: .init(get: { failure != nil }, set: { if !$0 { failure = nil } }), presenting: failure) { f in
                Button("Cancel", role: .cancel) {}
                Button("Retry") {
                    if failure == nil { run(f) } else { pendingRetry = f }
                }
                .keyboardShortcut(.defaultAction)
            } message: { f in Text(f.message) }
            .onChange(of: failure != nil) { _, shown in
                if shown {
                    if !retrying { warnings += 1 }  // `warning` once per failure: a failed Retry re-shows silently
                } else if let f = pendingRetry {
                    pendingRetry = nil
                    run(f)
                }
            }
            .sensoryFeedback(Motion.Haptic.warning.feedback, trigger: warnings)
    }

    private func run(_ f: Failure) {
        retrying = true
        Task {
            try? await Task.sleep(for: .milliseconds(450))  // the alert's dismiss animation
            await f.retry()
            retrying = false
        }
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
