import SwiftUI

/// Expense details (Figma Flow · Net model › Expense details, D1, D2, D7), pushed when you tap an expense. It always
/// shows the expense as it is now: your part as the large number, the details, then everyone in the split. Edit opens
/// the form as a sheet; Delete stays in the form. On a deleted trip it's grayed out and can't be edited.
struct ExpenseDetailView: View {
    let expenseId: UUID
    /// Pushed from this expense's trip: the Trip row goes back instead of pushing the trip again.
    var fromTrip = false
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var openTrip = false

    var body: some View {
        if let e = app.expenses.first(where: { $0.id == expenseId }) {
            let trip = app.trip(e.tripId)
            let gone = trip == nil  // the trip was deleted: nothing here counts
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
                                .foregroundStyle(gone ? Color.tsSecondary : Color.primary)
                        }
                        hero(e, gone: gone)
                        if gone {
                            Label("“\(tripName)” was deleted, so this expense doesn’t count and can’t be changed. Restore the trip from Activity first.",
                                  systemImage: "trash")
                                .font(.subheadline).foregroundStyle(.primary)
                                .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray5), in: .rect(cornerRadius: Radius.md))
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
                        SplitRow(row: row, name: row.userId == app.userId ? "You" : app.name(of: row.userId), gray: gone)
                    }
                } header: {
                    Text(gone ? ExpenseSplit.header(e).components(separatedBy: " · ")[0] + " · NOT COUNTED" : ExpenseSplit.header(e))
                }
            }
            .listSectionSpacing(.compact)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !gone { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { app.expenseSheet = .edit(e) } } }
            }
            .navigationDestination(isPresented: $openTrip) { TripDetailView(tripId: e.tripId) }
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
