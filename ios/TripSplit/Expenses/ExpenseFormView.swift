import SwiftUI

enum ExpenseSheet: Identifiable, Hashable {
    case add(tripId: UUID)
    case edit(Expense)
    var id: String { switch self { case .add(let t): "add-\(t)"; case .edit(let e): "edit-\(e.id)" } }
}

/// Add expense and Edit expense (Figma 09, E1): the amount up top, the description card, the
/// "Paid by you and split equally" sentence, then Trip and Date. Paid by and Split push inside the sheet.
struct ExpenseFormView: View {
    let target: ExpenseSheet
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var tripId: UUID
    @State private var description = ""
    @State private var icon: ExpenseIcon = .general
    @State private var iconOverridden = false
    @State private var amountText = ""
    @State private var payer: UUID?
    @State private var splitKind: SplitKind = .equal
    @State private var inputs: [UUID: Decimal] = [:]
    @State private var date = Date.now
    @State private var saving = false
    @State private var deleting: Expense?
    @State private var error: String?
    @State private var loaded = false  // onAppear fires again when Paid by or Split pops; fill the form once
    @FocusState private var amountFocused: Bool

    init(target: ExpenseSheet) {
        self.target = target
        switch target {
        case .add(let t): _tripId = State(initialValue: t)
        case .edit(let e): _tripId = State(initialValue: e.tripId)
        }
    }

    private var editing: Expense? { if case .edit(let e) = target { e } else { nil } }
    private var trip: Trip? { app.trip(tripId) }
    /// Who can be in the split: active members, plus anyone already on this expense (removed with "keep"),
    /// so editing a title or date doesn't drop their share.
    private var members: [Member] {
        guard let trip else { return [] }
        var kept = Set(editing?.expenseShares.map(\.userId) ?? [])
        if let payer = editing?.payerId { kept.insert(payer) }
        return trip.tripMembers.filter { $0.removedAt == nil || kept.contains($0.userId) }.sorted { $0.position < $1.position }
    }
    private var amountCents: Int { Money.cents(from: amountText) ?? 0 }
    private var footer: SplitFooter.Result { SplitFooter.evaluate(kind: splitKind, amountCents: amountCents, inputs: members.map { inputs[$0.userId] ?? 0 }) }
    private var canSave: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty && amountCents > 0 && payer != nil && footer.isValid && !saving
    }
    private var summary: String { "\(description.isEmpty ? "Expense" : description) · \(Money.string(amountCents))" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Amount (Display/Amount, centered)
                    HStack(spacing: 0) {
                        Text("$")
                        TextField("0", text: $amountText).keyboardType(.decimalPad).fixedSize().focused($amountFocused)
                            .onChange(of: amountText) { _, new in amountText = Money.cleanAmountInput(new) }
                    }
                    .font(.system(size: 48, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)

                    // Description card: icon tile + text
                    HStack(spacing: Spacing.md) {
                        Menu {
                            ForEach(ExpenseIcon.allCases, id: \.self) { i in
                                Button { icon = i; iconOverridden = true } label: { Label(i.title, systemImage: i.symbol) }
                            }
                        } label: { IconTile(icon: icon) }
                        .tint(.primary)  // the tile's symbol is black in Figma, not the menu's accent
                        TextField("What was it for?", text: $description)
                            .onChange(of: description) { if !iconOverridden { icon = ExpenseIcon.pick(for: description) } }
                    }
                    .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.md))

                    // "Paid by you and split equally"
                    HStack(spacing: 0) {
                        Text("Paid by ")
                        NavigationLink { PaidByView(members: members, tripName: trip?.name ?? "", selected: $payer) } label: {
                            Text(payerWord).foregroundStyle(Color.tsTintFill)
                        }
                        Text(" and split ")
                        NavigationLink {
                            SplitView(summary: summary, tripName: trip?.name ?? "", members: members, amountCents: amountCents, kind: $splitKind, inputs: $inputs)
                        } label: {
                            Text(splitWord).foregroundStyle(Color.tsTintFill)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)

                    FieldLabel("TRIP")
                    Menu {
                        ForEach(app.trips) { t in Button(t.name) { tripId = t.id } }
                    } label: {
                        FieldRow(text: trip?.name ?? "", chevron: true, dimmed: editing != nil)
                    }
                    .disabled(editing != nil)  // moving an expense between trips would change two trips' balances

                    FieldLabel("DATE")
                    // Looks like the Figma field ("Today ›"); the real picker sits on top, invisible, and takes the tap.
                    FieldRow(text: ExpenseLine.day(date), chevron: true)
                        .overlay { DatePicker("", selection: $date, displayedComponents: .date).labelsHidden().opacity(0.001) }

                    if let expense = editing {
                        Spacer(minLength: Spacing.xxxl)
                        Button("Delete expense") { deleting = expense }
                            .font(.headline).foregroundStyle(Color.tsOwe)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.md))
                        Text("Added by \(expense.createdBy == app.userId ? "you" : name(of: expense.createdBy)) · \(ExpenseLine.when(expense.createdAt))")
                            .font(.footnote).foregroundStyle(Color.tsSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(editing == nil ? "Add expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(!canSave) }
            }
            .onAppear { let first = !loaded; load(); if first, editing == nil { amountFocused = true } }
            .onChange(of: tripId) { resetSplit() }
            .deleteExpenseAlert(expense: $deleting, tripName: trip?.name ?? "", afterDelete: { dismiss() })
            .alert("Couldn’t save", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Retry") { Task { await save() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private var payerWord: String { payer == app.userId ? "you" : name(of: payer) }
    private var splitWord: String {
        switch splitKind { case .equal: "equally"; case .exact: "by exact amounts"; case .percent: "by percentages"; case .shares: "by shares" }
    }

    private func name(of user: UUID?) -> String {
        guard let user else { return "" }
        if user == app.userId { return "You" }
        let stored = members.first { $0.userId == user }?.profiles.displayName ?? app.people.first { $0.id == user }?.displayName
        return stored.map(PersonName.shown) ?? "Someone"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let e = editing {
            description = e.description; icon = e.icon; iconOverridden = e.icon != ExpenseIcon.pick(for: e.description)
            amountText = Money.plain(e.amountCents); payer = e.payerId; splitKind = e.splitKind; date = e.date
            inputs = Dictionary(uniqueKeysWithValues: e.expenseShares.map { ($0.userId, Self.input(for: $0, kind: e.splitKind)) })
        } else {
            payer = app.userId
            resetSplit()
        }
    }

    /// What the split screen shows for a saved share: 1 for equal, cents for exact, the stored input otherwise.
    private static func input(for share: ExpenseShare, kind: SplitKind) -> Decimal {
        switch kind {
        case .equal: 1
        case .exact: Decimal(share.shareCents)
        case .percent, .shares: share.splitInput ?? 0
        }
    }

    /// Everyone starts in an equal split (PRD › Splits).
    private func resetSplit() {
        guard editing == nil else { return }
        splitKind = .equal
        inputs = Dictionary(uniqueKeysWithValues: members.map { ($0.userId, Decimal(1)) })
        if let payer, !members.contains(where: { $0.userId == payer }) { self.payer = app.userId }
    }

    private func save() async {
        guard let payer else { return }
        saving = true; defer { saving = false }
        let args = SaveExpenseArgs(
            p_trip: tripId, p_expense_id: editing?.id, p_description: description.trimmingCharacters(in: .whitespaces),
            p_icon: icon.rawValue, p_amount_cents: amountCents, p_payer: payer, p_split_kind: splitKind.rawValue,
            p_inputs: members.map { SplitInput(user_id: $0.userId, value: inputs[$0.userId] ?? 0) },
            p_spent_on: DayFormat.string(date))
        do { try await app.saveExpense(args); dismiss() }
        catch { self.error = AppModel.describe("Check your connection and try again.", error) }
    }
}

/// "TRIP", "DATE": the small caps label over a grouped field.
struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.footnote).foregroundStyle(Color.tsSecondary).padding(.top, Spacing.xs) }
}

/// The Figma Text Field component: white, 44 pt, optional chevron.
struct FieldRow: View {
    let text: String
    var chevron = false
    var dimmed = false
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(text).foregroundStyle(dimmed ? Color.tsSecondary : Color.primary)
            Spacer()
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.tsSecondary) }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: 44)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.md))
        .contentShape(.rect)
    }
}

/// Single select with a trailing checkmark (Figma 09a).
struct PaidByView: View {
    let members: [Member]
    let tripName: String
    @Binding var selected: UUID?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(members, id: \.userId) { m in
                    Button { selected = m.userId; dismiss() } label: {
                        HStack {
                            Text(m.userId == app.userId ? "You" : PersonName.shown(m.profiles.displayName)).foregroundStyle(.primary)
                            Spacer()
                            if m.userId == selected { Image(systemName: "checkmark").foregroundStyle(Color.tsTintFill) }
                        }
                    }
                }
            } header: { Text(tripName.uppercased()).font(.footnote) } footer: {
                Text("Anyone on the trip. They can be outside the split.")
            }
        }
        .navigationTitle("Paid by")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The Figma Icon Tile: 36 pt, gray fill, the expense's SF Symbol.
struct IconTile: View {
    let symbol: String
    init(icon: ExpenseIcon) { symbol = icon.symbol }
    init(symbol: String) { self.symbol = symbol }
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .background(Color(.systemGray5), in: .rect(cornerRadius: Radius.sm))
    }
}

/// One expense on the trip (Figma Expense Row): icon, title, "Alex paid $120 · Today", and only your part
/// as a gray label over a colored amount.
struct ExpenseRow: View {
    let expense: Expense
    let trip: Trip
    @Environment(AppModel.self) private var app

    var body: some View {
        let youPaid = expense.payerId == app.userId
        let part = ExpenseLine.parts(amountCents: expense.amountCents, youPaid: youPaid, yourShareCents: expense.share(of: app.userId))
        let payer = youPaid ? "You" : trip.tripMembers.first { $0.userId == expense.payerId }.map { PersonName.shown($0.profiles.displayName) } ?? "Someone"
        ExpenseRowLayout(symbol: expense.icon.symbol, title: expense.description,
                         caption: ExpenseLine.caption(payer: payer, amountCents: expense.amountCents, date: expense.date),
                         label: part?.label, cents: part?.cents,
                         color: part?.label == "You owe" ? .tsOwe : part?.label == "You lent" ? .tsOwed : .tsSecondary)
    }
}

/// The Figma Expense Row's layout, shared by a trip's expenses and a person's screen: icon tile, title over
/// caption, and an optional gray label over the amount (none at all when `cents` is nil).
struct ExpenseRowLayout: View {
    let symbol: String
    let title: String
    let caption: String
    let label: String?
    let cents: Int?
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.md) {
            IconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).lineLimit(1)
                Text(caption).font(.footnote).foregroundStyle(Color.tsSecondary)
            }
            Spacer()
            if let cents {
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    if let label { Text(label).font(.footnote).foregroundStyle(Color.tsSecondary) }
                    Text(Money.string(cents)).font(.headline).foregroundStyle(color)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// "Delete 'Costco'?" (PRD › Prototype decisions › Expenses › Delete).
    func deleteExpenseAlert(expense: Binding<Expense?>, tripName: String, afterDelete: @escaping () -> Void = {}) -> some View {
        modifier(DeleteExpenseAlert(expense: expense, tripName: tripName, afterDelete: afterDelete))
    }
}

private struct DeleteExpenseAlert: ViewModifier {
    @Binding var expense: Expense?
    let tripName: String
    let afterDelete: () -> Void
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.alert("Delete ‘\(expense?.description ?? "")’?", isPresented: .init(get: { expense != nil }, set: { if !$0 { expense = nil } }), presenting: expense) { e in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do { try await app.deleteExpense(e.id); afterDelete() }
                    catch { app.error = AppModel.describe("Couldn’t delete the expense. Try again.", error) }
                }
            }
        } message: { _ in
            Text("It comes off everyone’s balance on \(tripName). This can’t be undone.")
        }
    }
}

extension Money {
    /// "84.20" for a text field; "90" when whole.
    static func plain(_ cents: Int) -> String {
        let a = abs(cents)
        return (cents < 0 ? "-" : "") + (a % 100 == 0 ? "\(a / 100)" : String(format: "%d.%02d", a / 100, a % 100))
    }

    /// What the amount field keeps as you type (or paste): digits and one decimal point. A comma is the point
    /// on decimal-comma keyboards, so it's kept as "."; nothing else gets in.
    static func cleanAmountInput(_ text: String) -> String {
        var out = ""; var seenPoint = false; var decimals = 0
        for c in text {
            if c.isASCII, c.isNumber { if seenPoint { guard decimals < 2 else { continue }; decimals += 1 }; out.append(c) }
            else if c == "." || c == ",", !seenPoint { seenPoint = true; out.append(".") }
        }
        return out
    }

    /// Cents from "$84.20", "84,20", "84.2", "90". Nil for anything else: trailing text, two points, more than
    /// two decimals, or $10,000,000 and up (amount_cents is a 32-bit integer).
    static func cents(from text: String) -> Int? {
        let t = text.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, t.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." }), t.filter({ $0 == "." }).count <= 1 else { return nil }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0]), frac = parts.count > 1 ? String(parts[1]) : ""
        guard frac.count <= 2, whole.count <= 7, !(whole.isEmpty && frac.isEmpty) else { return nil }
        guard let w = Int(whole.isEmpty ? "0" : whole), let f = Int(frac.isEmpty ? "0" : frac.padding(toLength: 2, withPad: "0", startingAt: 0)) else { return nil }
        return w * 100 + f
    }
}
