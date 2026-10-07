import SwiftUI

/// Before Apple Cash: how to send it (many people never have), then the Messages app with the message written.
/// TripSplit never sees a phone number: you pick the person in Messages' To field from your own contacts. It's the
/// Messages app, not the in-app composer, because the composer can't use iMessage apps like Apple Cash. No API
/// fills in an Apple Cash payment, so the amount goes on the clipboard.
struct AppleCashGuide: View {
    let otherName: String
    let cents: Int
    /// Why the amount can't be sent now (it's more than is owed, or nothing is): shown instead of the steps.
    var problem: String? = nil
    /// Called as Messages opens; coming back to TripSplit then asks "Did you pay?".
    let onOpenMessages: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var message: String { "Sending you \(Money.string(cents)) with Apple Cash for our TripSplit balance." }

    var body: some View {
        ScrollView {
            if cents > 0, problem == nil { guide } else {
                // The balance changed while the guide was open (someone logged a payment or edited an expense).
                Text(problem ?? "You don’t owe \(otherName) anything now.").font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.top, Spacing.xxxl).padding(.horizontal, Spacing.lg)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: copyAmount)
        .onChange(of: cents) { copyAmount() }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Send \(Money.string(cents)) with Apple Cash").font(.title3.weight(.semibold)).padding(.top, Spacing.xl)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                step(1, "Tap Open Messages and pick \(otherName) in the To field.")
                step(2, "Tap the Apple Cash button (or + and then Apple Cash).")
                step(3, "Paste \(Money.string(cents)). It’s already copied.")
                step(4, "Tap the arrow and confirm.")
            }
            Text("When you come back, TripSplit asks whether you paid. Nothing is logged until you say so.").font(.footnote).foregroundStyle(Color.tsSecondary)
            Button("Open Messages") { open() }.buttonStyle(PrimaryButtonStyle()).padding(.top, Spacing.sm)
            // Apps can't open that Settings page, and Wallet's add-card flow doesn't turn on Apple Cash.
            VStack(spacing: Spacing.xxs) {
                Text("New to Apple Cash? Turn it on in Settings › Wallet & Apple Pay › Apple Cash.")
                    .font(.footnote).foregroundStyle(Color.tsSecondary).multilineTextAlignment(.center)
                Link("How to set up Apple Cash", destination: URL(string: "https://support.apple.com/en-us/109304")!)
                    .font(.subheadline).foregroundStyle(Color.tsTintFill).frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.lg)
    }

    /// Step 3 says the amount is copied, so the clipboard follows the live balance (and only a real amount).
    private func copyAmount() { if cents > 0, problem == nil { UIPasteboard.general.string = Money.plain(cents) } }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(n)").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Color.tsTintFill, in: .circle)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A new message in the Messages app with the text filled in and no recipient. "Did you pay?" is armed only once
    /// Messages has actually opened; if it doesn't, the guide stays up.
    private func open() {
        guard cents > 0, problem == nil, let link = URL(string: "sms:&body=" + (message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) else { return }
        copyAmount()
        openURL(link) { opened in
            guard opened else { return }
            onOpenMessages()
            dismiss()
        }
    }
}
