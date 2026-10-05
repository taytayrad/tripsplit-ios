import MessageUI
import PassKit
import SwiftUI

/// Before Apple Cash: how to send it (many people never have), then Messages inside TripSplit with the message
/// written. TripSplit never sees a phone number: you pick the person in Messages' To field from your own contacts.
/// No API fills in an Apple Cash payment, so the amount goes on the clipboard.
struct AppleCashGuide: View {
    let otherName: String
    let cents: Int
    /// Called when Messages closes (sent or not); the person screen then asks "Did you pay?".
    let onMessagesClosed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var composing = false

    private var message: String { "Sending you \(Money.string(cents)) with Apple Cash for our TripSplit balance." }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Send \(Money.string(cents)) with Apple Cash").font(.title3.weight(.semibold)).padding(.top, Spacing.xl)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                step(1, "Tap Open Messages and pick \(otherName) in the To field.")
                step(2, "Tap the Apple Cash button (or + and then Apple Cash).")
                step(3, "Paste \(Money.string(cents)). It’s already copied.")
                step(4, "Tap the arrow and confirm.")
            }
            Text("Nothing is logged until you say you paid.").font(.footnote).foregroundStyle(Color.tsSecondary)
            Button("Open Messages") { open() }.buttonStyle(PrimaryButtonStyle()).padding(.top, Spacing.sm)
            Button("New to Apple Cash? Set it up in Wallet") { PKPassLibrary().openPaymentSetup() }
                .font(.subheadline).foregroundStyle(Color.tsTintFill).frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, Spacing.lg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { UIPasteboard.general.string = Money.plain(cents) }
        .sheet(isPresented: $composing, onDismiss: { onMessagesClosed(); dismiss() }) {
            MessageComposer(body: message).ignoresSafeArea()
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(n)").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Color.tsTintFill, in: .circle)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Messages inside TripSplit when the device can send texts; otherwise the Messages app with the text filled in.
    private func open() {
        if MFMessageComposeViewController.canSendText() { composing = true; return }
        if let link = URL(string: "sms:&body=" + (message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) { openURL(link) }
        onMessagesClosed()
        dismiss()
    }
}

/// The system Messages composer, prefilled with a body and no recipient.
private struct MessageComposer: UIViewControllerRepresentable {
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    /// MessageUI calls its delegate on the main thread; `@preconcurrency` checks that at run time.
    @MainActor final class Coordinator: NSObject, @preconcurrency MFMessageComposeViewControllerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { done() }
    }
}
