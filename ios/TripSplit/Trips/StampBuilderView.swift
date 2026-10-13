import SwiftUI

/// Pick a trip's stamp (TRIP-39, Figma Stamp builder B2–B4): a live preview with Shuffle, then symbol, shape, and
/// ink. Edits a copy; Done hands it back to the form, which saves it with the trip.
struct StampBuilderView: View {
    @Binding var stamp: StampSpec
    @State private var spec: StampSpec
    @State private var pressed = false
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(stamp: Binding<StampSpec>) {
        _stamp = stamp
        _spec = State(initialValue: stamp.wrappedValue)
    }

    private var changed: Bool { spec != stamp }
    private var compact: Bool { typeSize.isAccessibilitySize }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: compact ? 2 : 3) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    section("Symbol")
                    LazyVGrid(columns: columns, spacing: Spacing.sm) {
                        ForEach(StampGlyph.allCases, id: \.self) { g in
                            tile(g.spokenName, selected: spec.glyph == g, height: 46) { spec.glyph = g } content: {
                                Image(systemName: g.systemImage).font(.title2).foregroundStyle(spec.ink.ink)
                            }
                        }
                    }
                    section("Shape")
                    LazyVGrid(columns: columns, spacing: Spacing.sm) {
                        ForEach(StampShape.allCases, id: \.self) { s in
                            tile(s.spokenName, selected: spec.shape == s, height: 54) { spec.shape = s } content: {
                                StampView(spec: StampSpec(shape: s, glyph: spec.glyph, ink: spec.ink, rotation: 0, offsetX: 0, offsetY: 0),
                                          showsGlyph: false).frame(height: 42)
                            }
                        }
                    }
                    section("Ink")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: compact ? 3 : 6)) {
                        ForEach(StampInk.allCases, id: \.self) { ink in
                            Button { spec.ink = ink } label: {
                                Circle().fill(ink.ink).frame(width: 32, height: 32)
                                    .overlay { if spec.ink == ink { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                                    .padding(5)
                                    .overlay { if spec.ink == ink { Circle().stroke(Color.accentColor, lineWidth: 2.5) } }
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ink.spokenName)
                            .accessibilityAddTraits(spec.ink == ink ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.lg))
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
            // The preview stays pinned, so it's in view while you pick an ink; large text shrinks it (B4). At regular
            // sizes everything fits without scrolling.
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .top) {
                preview(size: compact ? 72 : 124)
                    .padding(.horizontal, Spacing.lg).padding(.bottom, Spacing.xs)
                    .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stamp").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if changed { confirmDiscard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { stamp = spec; dismiss() }.fontWeight(.semibold) }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(changed)  // a swipe can't throw away a change; Cancel asks first
        .sensoryFeedback(Motion.Haptic.selection.feedback, trigger: spec)
        .onChange(of: spec) { stampDown() }
    }

    /// The stamp as it'll look, with Shuffle as a round icon in the card's corner so the stamp leads.
    private func preview(size: CGFloat) -> some View {
        StampView(spec: spec).frame(width: size, height: size)
            .scaleEffect(pressed ? 0.94 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stamp")
            .accessibilityValue(spec.spokenName)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.xl))
            .overlay(alignment: .topTrailing) {
                Button { spec = .random() } label: {
                    Image(systemName: "shuffle").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        // Concentric with the card: its radius less the inset.
                        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: Radius.xl - Spacing.sm))
                }
                .foregroundStyle(Color.accentColor)
                .padding(Spacing.sm)
                .accessibilityLabel("Shuffle")
            }
    }

    /// A press on the preview, like a rubber stamp coming down. Reduce Motion: the haptic alone.
    private func stampDown() {
        guard !reduceMotion else { return }
        pressed = true
        Task { withAnimation(Motion.quick.animation(reduceMotion: false)) { pressed = false } }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.footnote).foregroundStyle(Color.tsSecondary)
            .padding(.top, Spacing.xs).accessibilityAddTraits(.isHeader)
    }

    /// A picker tile: selected is a ring plus a checkmark badge, never color alone.
    private func tile(_ name: String, selected: Bool, height: CGFloat, action: @escaping () -> Void,
                      @ViewBuilder content: () -> some View) -> some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Radius.lg))
                .overlay { if selected { RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Color.accentColor, lineWidth: 2.5) } }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.body).foregroundStyle(.white, Color.accentColor).padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
