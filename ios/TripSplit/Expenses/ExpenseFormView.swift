import SwiftUI

enum ExpenseSheet: Identifiable, Hashable {
    case add(tripId: UUID)
    case edit(Expense)
    var id: String { switch self { case .add(let t): "add-\(t)"; case .edit(let e): "edit-\(e.id)" } }
}

/// Add expense and Edit expense (Figma 09, E1). A sheet with its own stack; Paid by and Split push inside it.
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

    init(target: ExpenseSheet) {
        self.target = target
        switch target {
        case .add(let t): _tripId = State(initialValue: t)
        case .edit(let e): _tripId = State(initialValue: e.tripId)
        }
    }

    private var editing: Expense? { if case .edit(let e) = target { e } else { nil } }
    private var trip: Trip? { app.trip(tripId) }
    private var members: [Member] { trip?.members ?? [] }
    private var amountCents: Int { Money.cents(from: amountText) ?? 0 }
    private var footer: SplitFooter.Result { SplitFooter.evaluate(kind: splitKind, amountCents: amountCents, inputs: members.map { inputs[$0.userId] ?? 0 }) }
    private var canSave: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty && amountCents > 0 && payer != nil && footer.isValid && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Spacing.md) {
                        Menu {
                            ForEach(ExpenseIcon.allCases, id: \.self) { i in
                                Button { icon = i; iconOverridden = true } label: { Label(i.title, systemImage: i.symbol) }
                            }
                        } label: { IconBadge(icon: icon, size: 40) }
                        TextField("What was it for?", text: $description)
                            .onChange(of: description) { if !iconOverridden { icon = ExpenseIcon.pick(for: description) } }
                    }
                    TextField("$0.00", text: $amountText).keyboardType(.decimalPad).font(.title2.weight(.semibold))
                }

                Section {
                    NavigationLink { PaidByView(members: members, selected: $payer) } label: {
                        LabeledContent("Paid by", value: name(of: payer))
                    }
                    NavigationLink {
                        SplitView(members: members, amountCents: amountCents, kind: $splitKind, inputs: $inputs)
                    } label: {
                        LabeledContent("Split", value: splitSummary)
                    }
                }

                Section {
                    Picker("Trip", selection: $tripId) {
                        ForEach(app.trips) { Text($0.name).tag($0.id) }
                    }
                    .disabled(editing != nil)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                if let expense = editing {
                    Section {
                        Button("Delete expense", role: .destructive) { deleting = expense }
                    } footer: {
                        Text("Added by \(expense.createdBy == app.userId ? "you" : name(of: expense.createdBy)) · \(ExpenseLine.when(expense.createdAt))")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(!canSave) }
            }
            .onAppear(perform: load)
            .onChange(of: tripId) { resetSplit() }
            .deleteExpenseAlert(expense: $deleting, tripName: trip?.name ?? "", afterDelete: { dismiss() })
            .alert("Couldn’t save", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Retry") { Task { await save() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private var splitSummary: String {
        let count = members.filter { (inputs[$0.userId] ?? 0) > 0 }.count
        let kind = switch splitKind { case .equal: "Equally"; case .exact: "Exact amounts"; case .percent: "Percentages"; case .shares: "Shares" }
        return "\(kind), \(count == 1 ? "1 person" : "\(count) people")"
    }

    private func name(of user: UUID?) -> String {
        guard let user else { return "" }
        return user == app.userId ? "You" : members.first { $0.userId == user }?.profiles.displayName ?? app.people.first { $0.id == user }?.displayName ?? "Someone"
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

/// Single select with a trailing checkmark (PRD › Paid by).
struct PaidByView: View {
    let members: [Member]
    @Binding var selected: UUID?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(members, id: \.userId) { m in
            Button { selected = m.userId; dismiss() } label: {
                HStack {
                    Text(m.userId == app.userId ? "You" : m.profiles.displayName).foregroundStyle(.primary)
                    Spacer()
                    if m.userId == selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
            }
        }
        .navigationTitle("Paid by")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IconBadge: View {
    let icon: ExpenseIcon
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: icon.symbol)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(Color.tsTintFill)
            .frame(width: size, height: size)
            .background(Color.tsTintFill.opacity(0.12), in: .rect(cornerRadius: Radius.md))
    }
}

/// One expense on the trip: icon, title, date, and only your part (PRD › Trips).
struct ExpenseRow: View {
    let expense: Expense
    let trip: Trip
    @Environment(AppModel.self) private var app

    var body: some View {
        let line = ExpenseLine.text(amountCents: expense.amountCents, youPaid: expense.payerId == app.userId, yourShareCents: expense.share(of: app.userId))
        HStack(spacing: Spacing.md) {
            IconBadge(icon: expense.icon)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(expense.description).font(.body.weight(.medium)).lineLimit(1)
                Text(expense.date.formatted(.dateTime.month(.abbreviated).day())).font(.footnote).foregroundStyle(Color.tsSecondary)
            }
            Spacer()
            if let line {
                Text(line).font(.subheadline.weight(.semibold))
                    .foregroundStyle(line.hasPrefix("You owe") ? Color.tsOwe : line.hasPrefix("You lent") ? Color.tsOwed : Color.tsSecondary)
            }
        }
        .padding(.vertical, Spacing.xs)
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
    static func plain(_ cents: Int) -> String { cents % 100 == 0 ? "\(cents / 100)" : String(format: "%d.%02d", cents / 100, cents % 100) }
    /// Cents from "$84.20", "84.2", "90"; nil when it isn't money or has more than two decimals.
    static func cents(from text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned), value >= 0 else { return nil }
        let scaled = value * 100
        var rounded = Decimal(); var copy = scaled
        NSDecimalRound(&rounded, &copy, 0, .plain)
        guard rounded == scaled else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
