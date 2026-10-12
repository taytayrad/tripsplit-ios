import SwiftUI

/// Expense details (Figma Flow · Net model › Expense details, D1, D2, D7), pushed when you tap an expense. It always
/// shows the expense as it is now: your part as the large number, the details, then everyone in the split. Edit opens
/// the form as a sheet; Delete stays in the form. A deleted expense (D3) is struck through and can be restored
/// (D4–D6); on a deleted trip it's grayed out and can't be changed.
struct ExpenseDetailView: View {
    let expenseId: UUID
    /// Pushed from this expense's trip: the Trip row goes back instead of pushing the trip again.
    var fromTrip = false
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var openTrip = false
    @State private var restoreAlert: RestoreAlert?

    var body: some View {
        if let e = app.expenses.first(where: { $0.id == expenseId }) {
            let trip = app.trip(e.tripId)
            let gone = trip == nil  // the trip was deleted: nothing here counts
            let deleted = e.deletedAt != nil && !gone
            let gray = gone || deleted
            // A deleted trip isn't in `app.trips`; its Activity rows still carry the name and stamp.
            let event = app.activity.first { $0.tripId == e.tripId }
            let tripName = trip?.name ?? event?.tripName ?? "Trip"
            let stamp = trip?.stamp ?? event?.stamp
            List {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: e.icon.symbol).font(.title2.weight(.medium))
                                .frame(width: 56, height: 56)
                                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.lg))
                                .accessibilityHidden(true)
                            Text(e.description).font(.largeTitle.bold()).lineLimit(2)
                                .strikethrough(deleted)
                                .foregroundStyle(gray ? Color.tsSecondary : Color.primary)
                                .accessibilityLabel(deleted ? "\(e.description), deleted" : e.description)
                        }
                        if deleted {
                            Text(Money.string(e.amountCents)).font(.system(size: 48, weight: .bold)).strikethrough()
                                .lineLimit(1).minimumScaleFactor(0.5)
                                .foregroundStyle(Color.tsSecondary)
                                .accessibilityLabel("\(Money.string(e.amountCents)), not counted")
                            Note(text: "\(e.deletedBy == app.userId ? "You" : e.deletedBy.map(app.name(of:)) ?? "Someone") deleted this expense on \(Self.day(e.deletedAt ?? .now)). It doesn’t count toward anyone’s balance.")
                        } else {
                            hero(e, gone: gone)
                        }
                        if gone {
                            Note(text: "“\(tripName)” was deleted, so this expense doesn’t count and can’t be changed. Restore the trip from Activity first.")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
                }

                Section {
                    LabeledContent("Paid by", value: e.payerId == app.userId ? "You" : app.name(of: e.payerId))
                    LabeledContent("Date", value: Self.day(e.date))
                    Button { if fromTrip { dismiss() } else { openTrip = true } } label: {
                        HStack {
                            LabeledContent {
                                TripLabel(stamps: stamp.map { [$0] } ?? [], text: tripName)
                            } label: { Text("Trip").foregroundStyle(.primary) }
                            if !gone {
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
                            }
                        }
                    }
                    .disabled(gone)
                } footer: {
                    Text("Added by \(e.createdBy == app.userId ? "you" : app.name(of: e.createdBy)) · \(ExpenseLine.when(e.createdAt))")
                }

                Section {
                    let order = trip?.tripMembers.sorted { $0.position < $1.position }.map(\.userId) ?? []
                    ForEach(ExpenseSplit.rows(e, me: app.userId, order: order), id: \.userId) { row in
                        SplitRow(row: row, name: row.userId == app.userId ? "You" : app.name(of: row.userId), gray: gray)
                    }
                } header: {
                    Text(gray ? ExpenseSplit.header(e).components(separatedBy: " · ")[0] + " · NOT COUNTED" : ExpenseSplit.header(e))
                }
            }
            .listSectionSpacing(.compact)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if deleted {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Restore") { restoreAlert = Self.blocker(e, trip).map(RestoreAlert.blocked) ?? .confirm }
                            .accessibilityLabel("Restore expense")
                    }
                } else if !gone {
                    ToolbarItem(placement: .topBarTrailing) { Button("Edit") { app.expenseSheet = .edit(e) } }
                }
            }
            .navigationDestination(isPresented: $openTrip) { TripDetailView(tripId: e.tripId) }
            .alert(restoreAlert?.title(e) ?? "", isPresented: .init(get: { restoreAlert != nil }, set: { if !$0 { restoreAlert = nil } }),
                   presenting: restoreAlert) { alert in
                switch alert {
                case .confirm:
                    Button("Cancel", role: .cancel) {}
                    Button("Restore") { restore(e) }.keyboardShortcut(.defaultAction)
                case .blocked:
                    Button("OK", role: .cancel) {}
                case .failed:
                    Button("Cancel", role: .cancel) {}
                    Button("Try Again") { restore(e) }.keyboardShortcut(.defaultAction)
                }
            } message: { alert in
                Text(alert.message(e, tripName: tripName, you: ExpenseLine.parts(amountCents: e.amountCents, youPaid: e.payerId == app.userId,
                                                                                   yourShareCents: e.share(of: app.userId))))
            }
        } else {
            // Deleted here or on another phone.
            Color(.systemGroupedBackground).onAppear { dismiss() }
        }
    }

    /// Your part, in the trip's balance block: "You owe $20" or "You lent $40" over "$60 total". Your own cost is
    /// "You paid $60"; an expense you're not on, or one on a deleted trip, shows only its total.
    @ViewBuilder private func hero(_ e: Expense, gone: Bool) -> some View {
        let total = "\(Money.string(e.amountCents)) total"
        let part = ExpenseLine.parts(amountCents: e.amountCents, youPaid: e.payerId == app.userId, yourShareCents: e.share(of: app.userId))
        switch (gone ? nil : part)?.label {
        case "You owe": BalanceBlock(cents: -part!.cents, label: "You owe", detail: total)
        case "You lent": BalanceBlock(cents: part!.cents, label: "You lent", detail: total)
        case "You paid": BalanceBlock(cents: 0, label: "You paid", shownCents: e.amountCents)
        default: BalanceBlock(cents: 0, label: "Total", shownCents: e.amountCents)
        }
    }

    private func restore(_ e: Expense) {
        Task {
            do { try await app.restoreExpense(e.id) }
            catch {
                // Someone left between opening this and tapping Restore: the server refuses, like the check below.
                restoreAlert = String(describing: error).contains("left the trip") ? .blocked(nil) : .failed
            }
        }
    }

    /// The first person on the expense (payer or split) who's no longer on the trip: restoring would give them a
    /// balance, so it's refused (docs/money-rules.md › Expense lifecycle).
    static func blocker(_ e: Expense, _ trip: Trip?) -> String? {
        guard let trip else { return nil }
        let people = [e.payerId] + e.expenseShares.map(\.userId)
        return trip.tripMembers.first { m in m.removedAt != nil && people.contains(m.userId) }.map { PersonName.shown($0.profiles.displayName) }
    }

    /// "Oct 3", with the year when it isn't this year (Activity's rule).
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// One person in the split: name and caption ("Paid $60"), then a gray label over the amount. Red and green as on
/// Edit trip; gray when nothing counts. One VoiceOver element: "Atish D., owes $20".
private struct SplitRow: View {
    let row: ExpenseSplit.Row
    let name: String
    let gray: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(name)
                if let caption = row.caption { Text(caption).font(.footnote).foregroundStyle(Color.tsSecondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(row.label).font(.footnote).foregroundStyle(Color.tsSecondary)
                Text(Money.string(row.cents)).font(.headline)
                    .foregroundStyle(gray ? Color.tsSecondary : row.tone == .owe ? Color.tsOwe : row.tone == .owed ? Color.tsOwed : Color.tsSecondary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((name == "You" ? "\(row.label) \(Money.string(row.cents))"
                             : "\(name), \(row.label.lowercased()) \(Money.string(row.cents))") + (row.caption.map { ", \($0)" } ?? ""))
    }
}


/// The Restore alerts (Figma D4–D6): confirm, refused because someone left, and a failed save.
private enum RestoreAlert {
    case confirm
    /// Who left; nil when the server refused it and we don't know.
    case blocked(String?)
    case failed

    func title(_ e: Expense) -> String {
        switch self {
        case .confirm: "Restore “\(e.description)”?"
        case .blocked: "Can’t Restore “\(e.description)”"
        case .failed: "Couldn’t Restore “\(e.description)”"
        }
    }

    /// The confirm names what changes for you: "You’ll owe $20 again."
    func message(_ e: Expense, tripName: String, you: ExpenseLine.Part?) -> String {
        switch self {
        case .confirm:
            let line = switch you?.label {
            case "You owe": " You’ll owe \(Money.string(you!.cents)) again."
            case "You lent": " You’ll get back \(Money.string(you!.cents)) again."
            default: ""
            }
            return "It goes back into “\(tripName)”." + line
        case .blocked(let name):
            return "\(name ?? "Someone on it") left “\(tripName)”. Add them back to the trip to restore this expense."
        case .failed:
            return "Check your connection and try again."
        }
    }
}

/// The gray note under a deleted expense (Figma D3, D7).
private struct Note: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "trash")
            .font(.subheadline).foregroundStyle(.primary)
            .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray5), in: .rect(cornerRadius: Radius.md))
    }
}
