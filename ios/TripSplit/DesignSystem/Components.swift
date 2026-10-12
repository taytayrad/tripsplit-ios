import SwiftUI

// Shared pieces from the Figma library (Buttons, Trip Avatar, Balance Block).

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

/// A trip's image wherever the trip appears: its generated stamp, straight on the background (stamps only, no photos).
struct TripAvatar: View {
    let trip: Trip
    var size: CGFloat = 56
    var body: some View { StampAvatar(spec: trip.stamp, size: size) }
}

/// No fill behind the stamp (TRIP-15); the frame stays `size` square so layouts don't shift.
struct StampAvatar: View {
    let spec: StampSpec
    var size: CGFloat = 56
    var body: some View {
        StampView(spec: spec).padding(size * 0.05)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Net in words, never a sign: "You owe $90", "You're owed $56.14", "Settled $0". VoiceOver reads a net as one
/// sentence naming `name` (the trip on trip detail): "You’re owed Coast Road $90" (TRIP-34).
struct BalanceBlock: View {
    let cents: Int
    var label: String?
    var name: String?
    var detail: String?
    /// The amount to show when it isn't the net, in gray: an expense's total ("You paid $60", "Total $60").
    var shownCents: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label ?? (cents < 0 ? "You owe" : cents > 0 ? "You’re owed" : "Settled"))
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.tsSecondary)
            Text(Money.string(shownCents ?? cents))
                .font(.system(size: 48, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.5)  // never wraps beside the Pay button; a long amount shrinks
                .foregroundStyle(cents < 0 ? Color.tsOwe : cents > 0 ? Color.tsOwed : Color.tsSecondary)
            if let detail {
                Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(Color.tsSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label == nil && cents != 0 ? NetSentence.text(cents, name: name)
                            : [label ?? "Settled", Money.string(shownCents ?? cents), detail].compactMap { $0 }.joined(separator: ", "))
    }
}

/// A net as the sentence VoiceOver reads (TRIP-34): "You’re owed Alex $90", "You owe Coast Road $30". `$90` is
/// spoken "90 dollars". At $0 the screen shows the amount alone, so there's no sentence.
enum NetSentence {
    static func text(_ cents: Int, name: String?) -> String {
        [cents < 0 ? "You owe" : "You’re owed", name, Money.string(cents)].compactMap { $0 }.joined(separator: " ")
    }
}

/// A trip as a row's value: its stamp at 24 pt, then the name. More than one trip shows two overlapping stamps
/// ("2 Trips"), like the Settle up tickets.
struct TripLabel: View {
    let stamps: [StampSpec]
    let text: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: -8) {
                ForEach(Array(stamps.prefix(2).enumerated()), id: \.offset) { StampAvatar(spec: $0.element, size: 24) }
            }
            Text(text)
        }
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
