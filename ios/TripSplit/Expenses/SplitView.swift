import SwiftUI

/// Equally, Exact, Percent, Shares (Figma 09b–09e). The summary sits under the title, the running total is
/// pinned above the keyboard, and Done stays unavailable until the split is valid (PRD › Splits).
struct SplitView: View {
    let summary: String
    let tripName: String
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
                VStack(spacing: Spacing.sm) {
                    Text(summary).font(.headline).frame(maxWidth: .infinity)
                    Picker("Split", selection: $kind) {
                        Text("Equally").tag(SplitKind.equal)
                        Text("Exact").tag(SplitKind.exact)
                        Text("Percent").tag(SplitKind.percent)
                        Text("Shares").tag(SplitKind.shares)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(members, id: \.userId) { m in
                    row(for: m)
                }
            } header: {
                HStack {
                    Text(tripName.uppercased()).font(.footnote)
                    Spacer()
                    if kind == .equal, someoneUnchecked {
                        Button("Select all") { for m in members { inputs[m.userId] = 1 } }.font(.subheadline).textCase(nil)
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Done") { dismiss() }.fontWeight(.semibold).disabled(!footer.isValid) }
        .safeAreaInset(edge: .bottom) {
            Text(footer.text)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.bar)
        }
        .onChange(of: kind) { _, new in reset(for: new) }
        .onAppear { for m in members { text[m.userId] = display(inputs[m.userId] ?? 0) } }
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
            HStack(spacing: Spacing.md) {
                Text(name)
                Spacer()
                // The Figma Value Box: gray, 96 × 32, the unit inside, a tint border while editing.
                HStack(spacing: 0) {
                    if kind == .exact { Text("$") }
                    TextField(kind == .shares ? "1" : kind == .exact ? "0.00" : "0", text: .init(
                        get: { text[m.userId] ?? "" },
                        set: { text[m.userId] = $0; inputs[m.userId] = parse($0) }))
                        .keyboardType(kind == .shares ? .numberPad : .decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focused, equals: m.userId)
                    if kind == .percent { Text("%") }
                }
                .padding(.horizontal, Spacing.sm)
                .frame(width: 96, height: 32)
                .background(Color(.systemGray5), in: .rect(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.tsTintFill, lineWidth: focused == m.userId ? 2 : 0))
                .contentShape(.rect)
                .onTapGesture { focused = m.userId }
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
