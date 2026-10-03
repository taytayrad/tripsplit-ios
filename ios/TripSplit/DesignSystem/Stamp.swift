import SwiftUI

// A trip stamp: wordless, single ink, a little crooked, never cropped.
// Stored on the trip (trips.stamp) so every device draws the same one.

enum StampShape: String, CaseIterable, Codable { case ticket, circle, octagon, rounded, hexagon, postage }

enum StampGlyph: String, CaseIterable, Codable {
    case road, house, market, plane, palm, mountain, tent, boat, sun

    var systemImage: String {
        switch self {
        case .road: "road.lanes"
        case .house: "house"
        case .market: "cart"
        case .plane: "airplane"
        case .palm: "beach.umbrella"
        case .mountain: "mountain.2"
        case .tent: "tent"
        case .boat: "sailboat"
        case .sun: "sun.max"
        }
    }
}

enum StampInk: String, CaseIterable, Codable {
    case blue, green, red, purple, orange, teal

    var ink: Color {
        switch self {
        case .blue: .stampBlue
        case .green: .stampGreen
        case .red: .stampRed
        case .purple: .stampPurple
        case .orange: .stampOrange
        case .teal: .stampTeal
        }
    }

    var tint: Color {
        switch self {
        case .blue: .stampBlueTint
        case .green: .stampGreenTint
        case .red: .stampRedTint
        case .purple: .stampPurpleTint
        case .orange: .stampOrangeTint
        case .teal: .stampTealTint
        }
    }
}

struct StampSpec: Codable, Hashable {
    var shape: StampShape
    var glyph: StampGlyph
    var ink: StampInk
    /// Degrees, within ±maxRotation.
    var rotation: Double
    /// Fractions of the stamp's frame, within ±maxOffset.
    var offsetX: Double
    var offsetY: Double

    static let maxRotation = 8.0
    static let maxOffset = 0.025
    /// The art box is this fraction of the frame, leaving room to rotate and offset without cropping.
    static let artScale = 100.0 / 120.0

    static func random<G: RandomNumberGenerator>(using rng: inout G) -> StampSpec {
        StampSpec(
            shape: StampShape.allCases.randomElement(using: &rng)!,
            glyph: StampGlyph.allCases.randomElement(using: &rng)!,
            ink: StampInk.allCases.randomElement(using: &rng)!,
            rotation: .random(in: -maxRotation...maxRotation, using: &rng),
            offsetX: .random(in: -maxOffset...maxOffset, using: &rng),
            offsetY: .random(in: -maxOffset...maxOffset, using: &rng)
        )
    }

    static func random() -> StampSpec {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }

    /// True when the rotated, offset art box stays inside a square frame of side 1.
    var fitsFrame: Bool {
        let a = Self.artScale, t = rotation * .pi / 180
        let half = a * (abs(cos(t)) + abs(sin(t))) / 2
        return half + abs(offsetX) <= 0.5 && half + abs(offsetY) <= 0.5
    }
}

struct StampView: View {
    let spec: StampSpec

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let art = side * StampSpec.artScale
            ZStack {
                StampBorder(shape: spec.shape, size: art)
                Image(systemName: spec.glyph.systemImage)
                    .font(.system(size: art * glyphScale, weight: .regular))
            }
            .foregroundStyle(spec.ink.ink)
            .frame(width: art, height: art)
            .rotationEffect(.degrees(spec.rotation))
            .offset(x: spec.offsetX * side, y: spec.offsetY * side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var glyphScale: Double { spec.shape == .ticket ? 0.28 : 0.36 }
}

private struct StampBorder: View {
    let shape: StampShape
    let size: CGFloat

    // Stroke widths scale with the stamp so small avatars don't look heavy.
    private var outer: CGFloat { size * 0.04 }
    private var inner: CGFloat { size * 0.015 }

    var body: some View {
        switch shape {
        case .ticket:
            double(RoundedRectangle(cornerRadius: size * 0.16), RoundedRectangle(cornerRadius: size * 0.1))
                .frame(height: size * 0.6)
        case .circle:
            double(Circle(), Circle())
        case .octagon:
            double(Polygon(sides: 8, rotation: .pi / 8), Polygon(sides: 8, rotation: .pi / 8))
        case .rounded:
            double(RoundedRectangle(cornerRadius: size * 0.22), RoundedRectangle(cornerRadius: size * 0.16))
                .padding(size * 0.04)
        case .hexagon:
            double(Polygon(sides: 6, rotation: 0), Polygon(sides: 6, rotation: 0))
        case .postage:
            ZStack {
                Circle().stroke(style: StrokeStyle(lineWidth: outer, dash: [size * 0.06, size * 0.06]))
                Circle().stroke(lineWidth: inner * 1.4).padding(size * 0.09)
            }
            .padding(outer / 2)
        }
    }

    private func double<S: Shape, T: Shape>(_ a: S, _ b: T) -> some View {
        ZStack {
            a.stroke(lineWidth: outer)
            b.stroke(lineWidth: inner).padding(size * 0.07)
        }
        .padding(outer / 2)
    }
}

/// Regular polygon inscribed in the rect.
struct Polygon: Shape {
    let sides: Int
    let rotation: Double

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2, c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for i in 0..<sides {
            let a = rotation + Double(i) * 2 * .pi / Double(sides)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}
