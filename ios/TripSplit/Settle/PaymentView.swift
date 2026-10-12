import Supabase
import SwiftUI
import UIKit

/// The Payment page (Figma Flow · Net model › Payment): the Route, the amount, and Trip, Date and Method rows,
/// with one button that follows the method. Paying with an app leaves TripSplit; coming back opens the Log
/// Payment Sheet, and nothing is recorded until Log.
struct PaymentView: View {
    let ticket: SettleTicket
    let onLogged: (PaidTicket) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var amountText: String
    /// One trip, or nil for all of the ticket's trips ("2 Trips").
    @State private var trip: UUID?
    @State private var date = Date.now
    @State private var method: PayMethod?
    /// The payment's `request_id`, so a retried Log is one payment.
    @State private var requestId = UUID()
    /// A pay app you opened; coming back asks whether you paid.
    @State private var awaitingReturn = false
    /// What the pay app was opened for: the confirmation logs against this, not balances that moved since.
    @State private var pending: [SettleTicket.Part]?
    @State private var confirming = false
    @State private var appleCash = false
    @State private var saving = false
    /// "What’s owed just changed": its own sentence, not the failure alert.
    @State private var error: String?
    @State private var failure: Failure?
    @FocusState private var amountFocused: Bool

    init(ticket: SettleTicket, onLogged: @escaping (PaidTicket) -> Void) {
        self.ticket = ticket
        self.onLogged = onLogged
        _amountText = State(initialValue: Money.plain(ticket.cents))
        _trip = State(initialValue: ticket.parts.count == 1 ? ticket.parts[0].tripId : nil)
    }

    private var name: String { app.name(of: ticket.personId) }
    private var them: Profile? { app.profile(of: ticket.personId) }
    private var methods: [PayMethod] { PayOptions.methods(direction: ticket.direction, me: app.profile, them: them) }
    private var chosen: PayMethod { method ?? PayOptions.initial(direction: ticket.direction, me: app.profile, them: them) }
    private var cents: Int? { Money.cents(from: amountText) }
    /// The ticket as it stands now (balances can change while the page is open), narrowed to the chosen trip.
    private var chosenParts: [SettleTicket.Part] {
        let live = app.userId.map { SettleUp.current(ticket, app.settlements, me: $0) } ?? []
        return trip.map { t in live.filter { $0.tripId == t } } ?? live
    }
    private var max: Int { chosenParts.reduce(0) { $0 + $1.cents } }
    private var problem: String? { PaymentLimit.problem(cents: cents, max: max, direction: ticket.direction, otherName: name) }
    private var parts: [PaymentPart]? {
        guard let cents, problem == nil else { return nil }
        return SettleUp.split(cents, across: chosenParts)
    }

    var body: some View {
        List {
            if app.isOffline {
                OfflineBanner(message: OfflineBanner.payment)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                Route(from: ticket.direction == .pay ? "You" : name, to: ticket.direction == .pay ? name : "You")
            }
            Section {
                VStack(spacing: Spacing.xs) {
                    Text(ticket.direction == .pay ? "YOU OWE" : "YOU LENT").font(.footnote).foregroundStyle(Color.tsSecondary)
                    HStack(spacing: 0) {
                        Text("$")
                        TextField("0", text: $amountText).keyboardType(.decimalPad).fixedSize().focused($amountFocused)
                            .onChange(of: amountText) { _, new in amountText = Money.cleanAmountInput(new) }
                    }
                    .font(.system(size: 64, weight: .bold))
                    .accessibilityLabel("Amount")
                    Text(problem ?? "Tap to change the amount").font(.footnote)
                        .foregroundStyle(problem != nil && (cents ?? 0) > 0 ? Color.tsOwe : Color.tsSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                // A Menu, not a menu Picker, so the row can show the trip's stamp; the menu itself lists plain names.
                Menu {
                    Picker("Trip", selection: $trip) {
                        if ticket.parts.count > 1 { Text("\(ticket.parts.count) Trips").tag(UUID?.none) }
                        ForEach(ticket.parts, id: \.tripId) { part in
                            Text(app.trip(part.tripId)?.name ?? "Trip").tag(UUID?.some(part.tripId))
                        }
                    }
                } label: {
                    // Colored here: a Menu label would otherwise take the accent color.
                    LabeledContent {
                        TripLabel(stamps: (trip.map { [$0] } ?? ticket.parts.map(\.tripId)).compactMap { app.trip($0)?.stamp },
                                  text: trip.map { app.trip($0)?.name ?? "Trip" } ?? "\(ticket.parts.count) Trips")
                            .foregroundStyle(Color.tsSecondary)
                    } label: { Text("Trip").foregroundStyle(.primary) }
                }
                .onChange(of: trip) { amountText = Money.plain(max) }
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                NavigationLink {
                    MethodPicker(direction: ticket.direction, name: name, methods: methods, venmo: them?.venmoUsername,
                                 selection: .init(get: { chosen }, set: { method = $0 }))
                } label: {
                    LabeledContent("Method") { Text(chosen.title ?? "Recorded").foregroundStyle(Color.tsTintFill) }
                }
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(explanation)
                    if let error { Text(error).foregroundStyle(Color.tsOwe) }
                }
            }
        }
        .listSectionSpacing(.compact)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Payment")
        .failureAlert($failure)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { act() } label: {
                if saving { ProgressView().tint(.white) } else { Text(cta) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(parts == nil || saving)
            .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
            .background(Color(.systemGroupedBackground))
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, awaitingReturn else { return }
            awaitingReturn = false
            confirming = true
        }
        .sheet(isPresented: $confirming) {
            LogPaymentSheet(title: ticket.direction == .pay ? "Did you pay \(name)?" : "Did \(name) pay you?", note: confirmNote,
                            initialCents: pendingTotal, max: pendingTotal, direction: ticket.direction, otherName: name) { logged in
                try await log(logged)
            }
        }
        .sheet(isPresented: $appleCash) {
            // Live: if the balance changes while the guide is open, it follows (and won't open Messages over the limit).
            AppleCashGuide(otherName: name, cents: parts == nil ? 0 : cents ?? 0, problem: problem) {
                pending = currentAllocation  // the payment starts now, as Messages opens
                awaitingReturn = true
            }
        }
    }

    private var amount: String { Money.string(cents ?? 0) }
    private var currentAllocation: [SettleTicket.Part]? { parts?.map { SettleTicket.Part(tripId: $0.trip_id, cents: $0.cents) } }
    private var pendingTotal: Int { (pending ?? chosenParts).reduce(0) { $0 + $1.cents } }

    private var cta: String {
        if ticket.direction == .record { return "Record \(amount) payment" }
        switch chosen {
        case .cash: return "Log \(amount) cash payment"
        default: return "Pay \(amount) with \(chosen.title ?? "Cash")"
        }
    }

    private var explanation: String {
        var lines: [String] = []
        if ticket.direction == .record {
            lines.append("For when \(name) has already paid you. It comes off what \(name) owes.")
        } else {
            switch chosen {
            case .venmo: lines.append("Opens Venmo with \(amount) for \(name) filled in. Nothing is recorded until you confirm you paid.")
            case .zelle: lines.append("Copies \(amount), then you pay in your bank app and log it here.")
            case .appleCash: lines.append("Opens Messages to send Apple Cash. Nothing is recorded until you confirm you paid.")
            default: lines.append("Hand it over, then log it.")
            }
        }
        if trip == nil, let parts, parts.count > 1 {
            let list = parts.map { "\(Money.string($0.cents)) to \(app.trip($0.trip_id)?.name ?? "a trip")" }
            lines.append("Logged as one payment per trip: " + list.dropLast().joined(separator: ", ") + " and " + list.last! + ".")
        }
        return lines.joined(separator: " ")
    }

    private var confirmNote: String {
        switch chosen {
        case .venmo: "With Venmo. Paid part of it? Change the amount."
        case .appleCash: "With Apple Cash. Paid part of it? Change the amount."
        case .zelle: "Amount copied. Send it with Zelle in your bank’s app, then log it here."
        default: "Paid part of it? Change the amount."
        }
    }

    private func act() {
        // Checked against live balances right before money leaves TripSplit.
        guard let cents, let parts else { return }
        amountFocused = false
        if chosen != .appleCash || ticket.direction == .record { pending = parts.map { SettleTicket.Part(tripId: $0.trip_id, cents: $0.cents) } }
        if ticket.direction == .record || chosen == .cash || chosen == .recorded {
            Task { await logNow(cents) }
            return
        }
        switch chosen {
        case .venmo:
            guard let username = them?.venmoUsername?.nilIfEmpty else { return }
            var url = URLComponents(string: "https://venmo.com/")!
            url.queryItems = [.init(name: "txn", value: "pay"), .init(name: "recipients", value: username),
                              .init(name: "amount", value: Money.plain(cents)), .init(name: "note", value: "TripSplit")]
            awaitingReturn = true
            openURL(url.url!)
        case .zelle:
            UIPasteboard.general.string = Money.plain(cents)
            confirming = true
        case .appleCash:
            appleCash = true
        default:
            break
        }
    }

    private func logNow(_ cents: Int) async {
        guard !saving else { return }
        saving = true; defer { saving = false }
        error = nil
        do { try await log(cents) }
        catch let e as PostgrestError where e.message.contains("more than what is owed") || e.message.contains("nothing is owed") {
            await app.refresh()
            error = "What’s owed just changed. Go back to Settle up and try again."
        } catch {
            failure = Failure(title: "Couldn’t log the payment", error: error) { await logNow(cents) }
        }
    }

    /// Logs `cents` across the chosen trip(s), then goes back to Settle up.
    private func log(_ cents: Int) async throws {
        guard let split = SettleUp.split(cents, across: pending ?? chosenParts) else { return }
        let rows = try await app.logPayment(with: ticket.personId, direction: ticket.direction, method: chosen, paidOn: date,
                                            parts: split, requestId: requestId)
        onLogged(PaidTicket(personId: ticket.personId, direction: ticket.direction, cents: rows.reduce(0) { $0 + $1.amountCents },
                            method: chosen, tripIds: rows.map(\.tripId)))
        dismiss()
    }
}

/// Figma Route: FROM name — dashed line with a centred arrow — TO name.
struct Route: View {
    let from: String
    let to: String

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            end("FROM", from, .leading)
            HStack(spacing: Spacing.xs) {
                dash
                Image(systemName: "arrow.right").font(.footnote).foregroundStyle(Color.tsSecondary)
                dash
            }
            .padding(.bottom, 8)
            end("TO", to, .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(from) to \(to)")
    }

    private var dash: some View {
        Rectangle().fill(.clear).frame(height: 1)
            .overlay(GeometryReader { g in
                Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: g.size.width, y: 0)) }
                    .stroke(Color(.separator), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            })
    }

    private func end(_ label: String, _ name: String, _ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(Color.tsSecondary)
            Text(name).font(.title2.bold()).lineLimit(1)
        }
    }
}

/// The methods a payment can use (Figma Payment / Method): only what the other person can receive, plus cash.
struct MethodPicker: View {
    let direction: SettleDirection
    let name: String
    let methods: [PayMethod]
    let venmo: String?
    @Binding var selection: PayMethod
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(methods, id: \.self) { m in
                    Button { selection = m; dismiss() } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(m.title ?? "Recorded").foregroundStyle(.primary)
                                if let caption = caption(m) { Text(caption).font(.footnote).foregroundStyle(Color.tsSecondary) }
                            }
                            Spacer()
                            if m == selection { Image(systemName: "checkmark").foregroundStyle(Color.tsTintFill) }
                        }
                    }
                }
            } header: {
                Text(direction == .pay ? "\(name) can receive" : "\(name) paid with")
            } footer: {
                if direction == .pay { Text("Only methods \(name) has set up, plus cash.") }
            }
        }
        .navigationTitle("Method")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func caption(_ m: PayMethod) -> String? {
        guard direction == .pay else { return nil }
        switch m {
        case .venmo: return venmo.map { "@\($0) · opens Venmo" }
        case .zelle: return "Copies the amount, then you pay in your bank app"
        case .appleCash: return "Opens Messages to send it"
        case .cash: return "Hand it over, then log it"
        case .recorded: return nil
        }
    }
}
