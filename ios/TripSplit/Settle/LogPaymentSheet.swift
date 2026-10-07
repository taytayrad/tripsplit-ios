import Supabase
import SwiftUI

/// Figma Log Payment Sheet: slides up over the Payment page when you come back from Venmo, Zelle or Apple Cash.
/// The amount is editable (paid part of it?), capped at what's owed. "Not yet" records nothing.
struct LogPaymentSheet: View {
    let title: String
    let note: String
    let initialCents: Int
    let max: Int
    let direction: SettleDirection
    let otherName: String
    /// Logs the amount; throws to show an error here.
    let onLog: (Int) async throws -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?

    private var cents: Int? { Money.cents(from: text) }
    private var problem: String? { PaymentLimit.problem(cents: cents, max: max, direction: direction, otherName: otherName) }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center).padding(.top, Spacing.xl)
            HStack(spacing: 0) {
                Text("$")
                TextField("0", text: $text).keyboardType(.decimalPad).fixedSize()
                    .onChange(of: text) { _, new in text = Money.cleanAmountInput(new) }
            }
            .font(.system(size: 48, weight: .bold))
            .frame(height: 56)
            .accessibilityLabel("Amount")
            Text(problem ?? note)
                .font(.footnote).foregroundStyle(problem != nil && (cents ?? 0) > 0 ? Color.tsOwe : Color.tsSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.footnote).foregroundStyle(Color.tsOwe).multilineTextAlignment(.center) }
            Button {
                guard !saving else { return }
                saving = true  // before the task, so a second tap can't start a second log
                Task { await log() }
            } label: {
                if saving { ProgressView().tint(.white) }
                else { Text(error != nil ? "Retry" : (cents ?? 0) > 0 ? "Log \(Money.string(cents ?? 0)) payment" : "Log payment") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(problem != nil || saving)
            .padding(.top, Spacing.md)
            Button("Not yet") { dismiss() }.foregroundStyle(Color.tsTintFill).frame(minHeight: 44).disabled(saving)
        }
        .padding(.horizontal, Spacing.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
        .onAppear { text = Money.plain(initialCents) }
    }

    private func log() async {
        defer { saving = false }
        guard let cents else { return }
        error = nil
        do {
            try await onLog(cents)
            dismiss()
        } catch let e as PostgrestError where e.message.contains("more than what is owed") || e.message.contains("nothing is owed") {
            await app.refresh()
            error = "What you owe \(otherName) just changed. Check the amount and try again."
        } catch {
            self.error = AppModel.describe("Couldn’t log the payment. Check your connection and try again.", error)
        }
    }
}
