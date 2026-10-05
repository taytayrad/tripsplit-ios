import SwiftUI
import UIKit

/// The sheet the balance chip opens (Figma 13): your net across trips, then one row per person under
/// "You owe" and "Owes you". Tapping someone pushes their screen.
struct YourBalanceView: View {
    @Environment(AppModel.self) private var app
    @State private var showSettled = false

    var body: some View {
        let balance = app.balance
        NavigationStack {
            List {
                Section {
                    BalanceBlock(cents: balance.total,
                                 detail: balance.tripCount > 0 ? "Across \(balance.tripCount) trip\(balance.tripCount == 1 ? "" : "s")" : nil)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
                }
                if !balance.youOwe.isEmpty {
                    Section { ForEach(balance.youOwe) { PersonRow(row: $0) } } header: { Text("YOU OWE").font(.footnote) }
                }
                if !balance.owesYou.isEmpty {
                    Section { ForEach(balance.owesYou) { PersonRow(row: $0) } } header: { Text("OWES YOU").font(.footnote) }
                }
                if showSettled, !balance.settled.isEmpty {
                    Section { ForEach(balance.settled) { PersonRow(row: $0) } } header: { Text("SETTLED").font(.footnote) }
                } else if !balance.settled.isEmpty {
                    Section { Button("Show settled people") { showSettled = true }.foregroundStyle(Color.tsTintFill) }
                }
                Section {} footer: {
                    Text(balance.youOwe.isEmpty && balance.owesYou.isEmpty ? "You’re settled with everyone." : "Tap someone to pay and for details.")
                        .frame(maxWidth: .infinity)
                }
            }
            .listSectionSpacing(.compact)
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationTitle("Your Balance")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { PersonView(personId: $0) }
            .refreshable { await app.refresh() }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Figma Person Row: a name and one unsigned amount, red when you owe, green when they owe you.
private struct PersonRow: View {
    let row: BalanceSummary.Row
    var body: some View {
        NavigationLink(value: row.id) {
            HStack(spacing: Spacing.md) {
                Text(row.name)
                Spacer()
                Text(Money.string(row.cents)).font(.headline)
                    .foregroundStyle(row.cents < 0 ? Color.tsOwe : row.cents > 0 ? Color.tsOwed : Color.tsSecondary)
            }
        }
        .accessibilityLabel(row.cents < 0 ? "You owe \(row.name) \(Money.string(row.cents))"
                            : row.cents > 0 ? "\(row.name) owes you \(Money.string(row.cents))" : "\(row.name), settled")
    }
}

/// One person's screen (Figma 14, 17–20, P1–P6): your combined balance, a group per shared trip with the charges
/// and payments between you, and the pay bar.
struct PersonView: View {
    let personId: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var showSettled = false
    /// Trips a payment here just settled; they stay visible until the screen next opens.
    @State private var keep: Set<UUID> = []
    /// Payments logged here, for "You paid $50 today" and the confetti. Read back from `app.payments`, so a
    /// delete on either phone takes them away.
    @State private var loggedIds: Set<UUID> = []
    @State private var logging: LogContext?
    /// A pay app you opened; returning to TripSplit asks whether you paid (it logs nothing by itself).
    @State private var awaitingReturn: PayMethod?
    @State private var payingWithAppleCash = false
    @State private var deleting: PersonLedger.Line?

    private var name: String { app.name(of: personId) }

    var body: some View {
        let ledger = PersonLedger(me: app.userId ?? UUID(), other: personId, otherName: name, tripsNewestFirst: app.trips,
                                  expenses: app.expenses, payments: app.payments, pairs: app.pairs)
        List {
            Section {
                BalanceBlock(cents: ledger.total, label: label(ledger.total), detail: detail(ledger))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
            }
            ForEach(ledger.visible(showSettled: showSettled, keep: keep)) { group in
                Section {
                    ForEach(group.lines) { line in
                        ChargeRow(line: line)
                            .swipeActions { if line.isPayment { Button("Delete", role: .destructive) { deleting = line } } }
                    }
                } header: {
                    HStack {
                        Text(group.name.uppercased()).font(.footnote)
                        Spacer()
                        Text(Money.string(group.net)).font(.subheadline.weight(.semibold)).textCase(nil)
                            .foregroundStyle(group.net < 0 ? Color.tsOwe : group.net > 0 ? Color.tsOwed : Color.tsSecondary)
                    }
                }
            }
            if !showSettled, ledger.hiddenCount(keep: keep) > 0 {
                Section { Button("Show settled trips") { showSettled = true }.foregroundStyle(Color.tsTintFill) }
            }
        }
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .overlay { if !loggedHere.isEmpty && ledger.total == 0 { Celebration(stamps: settledStamps(ledger)) } }  // settled by a payment here
        .safeAreaInset(edge: .bottom) { payBar(total: ledger.total) }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await app.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let method = awaitingReturn else { return }
            awaitingReturn = nil
            logging = LogContext(direction: .pay, method: method)
        }
        .sheet(isPresented: $payingWithAppleCash) {
            AppleCashGuide(otherName: name, cents: -ledger.total) { awaitingReturn = .appleCash }
        }
        .sheet(item: $logging) { context in
            LogPaymentSheet(context: context, otherId: personId, otherName: name, max: LogPayment.max(total: ledger.total, direction: context.direction),
                            openTrips: openTrips(direction: context.direction)) { rows in
                keep.formUnion(rows.map(\.tripId))
                loggedIds.formUnion(rows.map(\.paymentId))
            }
        }
        .alert("Delete this payment?", isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { line in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do { try await app.deletePayment(line.id) }
                    catch { app.error = AppModel.describe("Couldn’t delete the payment. Check your connection and try again.", error) }
                }
            }
        } message: { _ in Text("It comes off your balance with \(name). Either of you can delete a payment.") }
    }

    private var loggedHere: [Payment] { app.payments.filter { loggedIds.contains($0.id) } }

    /// The stamps of the trips a payment here brought to $0, newest first, for the celebration. A trip it touched
    /// that still has a balance isn't one of them.
    private func settledStamps(_ ledger: PersonLedger) -> [StampSpec] {
        ledger.groups.filter { keep.contains($0.id) && $0.net == 0 }.compactMap { app.trip($0.id)?.stamp }
    }

    private func label(_ total: Int) -> String {
        total < 0 ? "You owe \(name)" : total > 0 ? "\(name) owes you" : "Settled"
    }

    private func detail(_ ledger: PersonLedger) -> String? {
        if ledger.total == 0 { return ledger.groups.isEmpty ? nil : "You and \(name) are settled" }
        if let first = loggedHere.first {
            let cents = loggedHere.reduce(0) { $0 + $1.amountCents }
            return first.payerId == app.userId ? "You paid \(Money.string(cents)) today" : "\(name) paid you \(Money.string(cents)) today"
        }
        return ledger.openTripCount > 1 ? "Across \(ledger.openTripCount) trips" : nil
    }

    /// The trips a payment in this direction can go to, with what's open on each. Empty (so the sheet shows no
    /// allocation note) when one of them is a trip you can't read: its order can't be known here.
    private func openTrips(direction: LogPayment.Direction) -> [Allocation.OpenTrip] {
        let open = app.pairs.filter { $0.otherUserId == personId && (direction == .pay ? $0.cents < 0 : $0.cents > 0) }
        let trips = open.compactMap { pair in
            app.trip(pair.tripId).map { Allocation.OpenTrip(id: $0.id, name: $0.name, owed: abs(pair.cents), startDay: $0.startDate, created: $0.createdAt) }
        }
        return trips.count == open.count ? trips : []
    }

    @ViewBuilder private func payBar(total: Int) -> some View {
        let me = app.profile ?? Profile(id: app.userId ?? UUID(), displayName: "", venmoUsername: nil, hasZelle: false, hasAppleCash: false)
        let them = app.people.first { $0.id == personId } ?? Profile(id: personId, displayName: name, venmoUsername: nil, hasZelle: false, hasAppleCash: false)
        let actions = PayBar.actions(me: me, them: them, total: total)
        if !actions.isEmpty {
            VStack(spacing: Spacing.sm) {
                ForEach(actions, id: \.self) { action in
                    switch action {
                    case .venmo(let username):
                        Button("Venmo") { openVenmo(username, cents: -total) }.buttonStyle(PrimaryButtonStyle())
                    case .zelle:
                        Button("Zelle") { copy(-total); logging = LogContext(direction: .pay, method: .zelle) }.buttonStyle(PrimaryButtonStyle())
                    case .appleCash:
                        Button("Apple Cash") { payingWithAppleCash = true }.buttonStyle(PrimaryButtonStyle())
                    case .cash:
                        Button("Cash") { logging = LogContext(direction: .pay, method: .cash) }.buttonStyle(SecondaryButtonStyle())
                    case .record:
                        Button("Record a Payment") { logging = LogContext(direction: .record, method: .recorded) }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            .padding(Spacing.lg)
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(alignment: .top) { Divider() }
        }
    }

    /// Venmo's pay link: opens the app with the person and amount filled in (or venmo.com without it).
    private func openVenmo(_ username: String, cents: Int) {
        var url = URLComponents(string: "https://venmo.com/")!
        url.queryItems = [.init(name: "txn", value: "pay"), .init(name: "recipients", value: username),
                          .init(name: "amount", value: Money.plain(cents)), .init(name: "note", value: "TripSplit")]
        awaitingReturn = .venmo
        openURL(url.url!)
    }

    private func copy(_ cents: Int) { UIPasteboard.general.string = Money.plain(cents) }
}

/// Figma Charge Row: an expense line (red when you owe, green when they owe you) or a payment line (neutral).
private struct ChargeRow: View {
    let line: PersonLedger.Line
    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(line.title)
            Spacer()
            Text(Money.string(line.cents))
                .foregroundStyle(line.isPayment ? Color.tsSecondary : line.cents < 0 ? Color.tsOwe : Color.tsOwed)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Why the log sheet is open: which way the money went and how.
struct LogContext: Identifiable {
    /// Also the payment's `request_id`, so a retried Log is one payment.
    let id = UUID()
    let direction: LogPayment.Direction
    let method: PayMethod
}
