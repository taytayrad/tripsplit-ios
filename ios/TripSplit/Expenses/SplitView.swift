import SwiftUI

/// Equally, Exact amounts, Percentages, Shares (Figma 09b–09e). The running total is pinned above the
/// keyboard, and Done stays unavailable until the split is valid (PRD › Prototype decisions › Splits).
struct SplitView: View {
    let members: [Member]
    let amountCents: Int
    @Binding var kind: SplitKind
    @Binding var inputs: [UUID: Decimal]
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text: [UUID: String] = [:]
    @FocusState private var focused: UUID?

    private var footer: SplitFooter.Result { SplitFooter.evaluate(kind: kind, amountCents: amountCents, inputs: members.map { inputs[$0.userId] ?? 0 }) }
    private var someoneUnchecked: Bool { members.contains { (inputs[$0.userId] ?? 0) == 0 } }

    var body: some View {
        List {
            Section {
                Picker("Split", selection: $kind) {
                    Text("Equally").tag(SplitKind.equal)
                    Text("Exact").tag(SplitKind.exact)
                    Text("Percent").tag(SplitKind.percent)
                    Text("Shares").tag(SplitKind.shares)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(members, id: \.userId) { m in
                    row(for: m)
                }
            } header: {
                if kind == .equal, someoneUnchecked {
                    HStack { Spacer(); Button("Select all") { for m in members { inputs[m.userId] = 1 } }.font(.footnote) }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar { Button("Done") { dismiss() }.fontWeight(.semibold).disabled(!footer.isValid) }
        .safeAreaInset(edge: .bottom) {
            Text(footer.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(footer.isValid ? Color.primary : Color.tsOwe)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.bar)
        }
        .onChange(of: kind) { _, new in reset(for: new) }
        .onAppear { for m in members { text[m.userId] = display(inputs[m.userId] ?? 0) } }
    }

    private var title: String {
        switch kind { case .equal: "Split equally"; case .exact: "Exact amounts"; case .percent: "Percentages"; case .shares: "Shares" }
    }

    @ViewBuilder private func row(for m: Member) -> some View {
        let name = m.userId == app.userId ? "You" : m.profiles.displayName
        switch kind {
        case .equal:
            CheckRow(title: name, isOn: .init(
                get: { (inputs[m.userId] ?? 0) > 0 },
                set: { on in
                    // At least one person stays selected.
                    if !on, members.filter({ (inputs[$0.userId] ?? 0) > 0 }).count <= 1 { return }
                    inputs[m.userId] = on ? 1 : 0
                }))
        default:
            HStack {
                Text(name)
                Spacer()
                if kind == .exact { Text("$").foregroundStyle(Color.tsSecondary) }
                TextField(kind == .shares ? "1" : "0", text: .init(
                    get: { text[m.userId] ?? "" },
                    set: { text[m.userId] = $0; inputs[m.userId] = parse($0) }))
                    .keyboardType(kind == .shares ? .numberPad : .decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .focused($focused, equals: m.userId)
                if kind == .percent { Text("%").foregroundStyle(Color.tsSecondary) }
            }
        }
    }

    /// Each kind starts fresh (PRD › Splits): equal and shares with everyone in, exact and percent at 0.
    private func reset(for kind: SplitKind) {
        let start: Decimal = (kind == .equal || kind == .shares) ? 1 : 0
        for m in members { inputs[m.userId] = start; text[m.userId] = display(start) }
    }

    private func parse(_ s: String) -> Decimal {
        if kind == .exact { return Decimal(Money.cents(from: s) ?? 0) }
        return Decimal(string: s.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private func display(_ d: Decimal) -> String {
        if d == 0 { return "" }
        if kind == .exact { return Money.plain(NSDecimalNumber(decimal: d).intValue) }
        return "\(d)"
    }
}
