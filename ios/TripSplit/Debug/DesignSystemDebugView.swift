import SwiftUI

/// Phase 0 check: every color token in light and dark, every stamp shape in every ink.
struct DesignSystemDebugView: View {
    static let colors: [(String, Color)] = [
        ("AccentColor", Color("AccentColor")), ("tsTintFill", .tsTintFill),
        ("tsDestructive", .tsDestructive), ("tsDestructiveFill", .tsDestructiveFill),
        ("tsOwe", .tsOwe), ("tsOwed", .tsOwed), ("tsOweFill", .tsOweFill), ("tsOwedFill", .tsOwedFill),
        ("tsSecondary", .tsSecondary),
    ] + StampInk.allCases.flatMap { [("stamp \($0.rawValue)", $0.ink), ("stamp \($0.rawValue) tint", $0.tint)] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        swatches.environment(\.colorScheme, .light)
                        swatches.environment(\.colorScheme, .dark)
                    }
                    stamps.environment(\.colorScheme, .light)
                    stamps.environment(\.colorScheme, .dark)
                }
                .padding(Spacing.lg)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Design System")
        }
    }

    private var swatches: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Self.colors, id: \.0) { name, color in
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: Radius.sm).fill(color).frame(width: 28, height: 20)
                    Text(name).font(.caption).foregroundStyle(.primary)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.md))
    }

    private var stamps: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 6), spacing: Spacing.sm) {
            ForEach(0..<36, id: \.self) { cell in
                let row = cell / 6, i = cell % 6, ink = StampInk.allCases[row]
                StampView(spec: StampSpec(shape: StampShape.allCases[i],
                                          glyph: StampGlyph.allCases[(i + row) % StampGlyph.allCases.count],
                                          ink: ink, rotation: [-6, 7, -4, 6, -7, 5][i], offsetX: 0.02, offsetY: -0.015))
                    .background(ink.tint, in: .rect(cornerRadius: Radius.sm))
            }
        }
        .padding(Spacing.md)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.md))
    }
}

#Preview { DesignSystemDebugView() }
