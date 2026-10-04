import SwiftUI

// Shared pieces from the Figma library (Buttons, Trip Avatar, Balance Block, Balance Chip).

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = .tsTintFill
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(fill, in: .rect(cornerRadius: Radius.lg))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color(.separator)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A trip's image wherever the trip appears: its generated stamp on the ink tint (stamps only, no photos).
struct TripAvatar: View {
    let trip: Trip
    var size: CGFloat = 56
    var body: some View { StampAvatar(spec: trip.stamp, size: size) }
}

struct StampAvatar: View {
    let spec: StampSpec
    var size: CGFloat = 56
    var body: some View {
        ZStack {
            spec.ink.tint
            StampView(spec: spec).padding(size * 0.05)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size > 60 ? Radius.xl : Radius.md))
        .accessibilityHidden(true)
    }
}

/// Net in words, never a sign: "You owe $90", "You're owed $56.14", "Settled $0".
struct BalanceBlock: View {
    let cents: Int
    var label: String?
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label ?? (cents < 0 ? "You owe" : cents > 0 ? "You’re owed" : "Settled"))
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.tsSecondary)
            Text(Money.string(cents))
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(cents < 0 ? Color.tsOwe : cents > 0 ? Color.tsOwed : Color.tsSecondary)
            if let detail {
                Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(Color.tsSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}

/// The header total: the only place money shows a sign.
struct BalanceChip: View {
    let cents: Int
    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(Money.signed(cents)).font(.headline)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
        }
        .foregroundStyle(cents == 0 ? Color.primary : .white)
        .padding(.horizontal, Spacing.md).padding(.vertical, 6)
        .background(cents < 0 ? Color.tsOweFill : cents > 0 ? Color.tsOwedFill : Color(.systemGray5), in: .capsule)
        .fixedSize()
        .contentShape(.rect.inset(by: -6))  // 44 pt tap target
        .accessibilityLabel(cents < 0 ? "Balance, you owe \(Money.string(cents))"
                            : cents > 0 ? "Balance, you’re owed \(Money.string(cents))" : "Balance, settled")
    }
}

/// Three different stamps for empty states and sign-in.
struct StampCluster: View {
    var size: CGFloat = 96
    var body: some View {
        HStack(spacing: Spacing.xs) {
            StampView(spec: .init(shape: .ticket, glyph: .boat, ink: .blue, rotation: -6, offsetX: 0, offsetY: 0)).frame(width: size * 0.85)
            StampView(spec: .init(shape: .circle, glyph: .tent, ink: .green, rotation: 7, offsetX: 0, offsetY: 0)).frame(width: size)
            StampView(spec: .init(shape: .octagon, glyph: .sun, ink: .red, rotation: -4, offsetX: 0, offsetY: 0)).frame(width: size * 0.85)
        }
    }
}

/// A tappable row with the round check from the Figma Check component (multi-select).
struct CheckRow: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.tsTintFill : Color(.separator))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
