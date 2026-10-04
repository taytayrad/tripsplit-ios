import Supabase
import SwiftUI

/// The one place a payment is logged (Figma Log Payment Sheet). Prefilled with the full balance and editable,
/// capped at what's owed, with a note when it touches more than one trip. "Not yet" records nothing.
struct LogPaymentSheet: View {
    let context: LogContext
    let otherId: UUID
    let otherName: String
    /// The combined balance in this direction: the most that can be logged.
    let max: Int
    let openTrips: [Allocation.OpenTrip]
    /// Called after logging, with the rows the server stored.
    let onLogged: ([LoggedPayment]) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?
    @FocusState private var amountFocused: Bool

    private var cents: Int? { Money.cents(from: text) }
    private var problem: String? { LogPayment.problem(cents: cents, max: max, direction: context.direction, otherName: otherName) }
    private var parts: [Allocation.Part]? { cents.flatMap { Allocation.plan($0, across: openTrips) } }

    private var title: String {
        switch (context.direction, context.method) {
        case (.record, _): "Did \(otherName) pay you?"
        case (_, .cash): "Paid \(otherName) in cash?"
        default: "Did you pay \(otherName)?"
        }
    }

    private var how: String {
        switch context.method {
        case .venmo: "With Venmo. Paid a different amount? Tap it to change."
        case .appleCash: "With Apple Cash. Paid a different amount? Tap it to change."
        case .zelle: "Amount copied. Send it with Zelle in your bank’s app, then log it here."
        case .cash: "In cash. Paid a different amount? Tap it to change."
        case .recorded: "Paid a different amount? Tap it to change."
        }
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center).padding(.top, Spacing.xl)
            HStack(spacing: 0) {
                Text("$")
                TextField("0", text: $text).keyboardType(.decimalPad).fixedSize().focused($amountFocused)
                    .onChange(of: text) { _, new in text = Money.cleanAmountInput(new) }
            }
            .font(.system(size: 48, weight: .bold))
            .frame(height: 56)
            .accessibilityLabel("Amount")
            Group {
                if let problem { Text(problem).foregroundStyle((cents ?? 0) > 0 ? Color.tsOwe : Color.tsSecondary) }
                else if let note = parts.flatMap(Allocation.note) { Text(note) }
                else { Text(how) }
            }
            .font(.footnote).foregroundStyle(Color.tsSecondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
        .onAppear { text = Money.plain(max) }
    }

    private func log() async {
        defer { saving = false }
        guard let cents else { return }
        error = nil
        do {
            let rows = try await app.logPayment(with: otherId, cents: cents, direction: context.direction, method: context.method, requestId: context.id)
            onLogged(rows)
            dismiss()
        } catch let e as PostgrestError where e.message.contains("more than what is owed") || e.message.contains("nothing is owed") {
            await app.refresh()
            error = "The balance with \(otherName) just changed. Check the amount and try again."
        } catch {
            self.error = AppModel.describe("Couldn’t log the payment. Check your connection and try again.", error)
        }
    }
}
