import SwiftUI

/// Settling to $0 with someone: the settled trips' stamps thump onto the screen, each with a heavy tap and a ring
/// of pieces in the stamp inks. Plays once (about 3 s), then clears; never blocks a tap. Reduce Motion: the stamps
/// and pieces appear still, then fade.
struct Celebration: View {
    /// Up to three; topped up with random stamps.
    let stamps: [StampSpec]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var particles: [Particle] = []
    @State private var thumps = 0
    /// The three stamps shown, picked once when it starts (random fillers would otherwise change on every redraw).
    @State private var shown: [StampSpec] = []
    /// Set when it's over: the view (and its animation schedule) goes away.
    @State private var finished = false
    @State private var fading = false

    private let duration = 3.0
    /// Where the stamps land, as fractions of the screen: the first just right of the balance block's "$0", as if
    /// stamped next to it; the others to its right.
    private static let spots = [CGPoint(x: 0.4, y: 0.16), CGPoint(x: 0.78, y: 0.11), CGPoint(x: 0.7, y: 0.3)]
    private static func landing(_ i: Int) -> Double { 0.15 + Double(i) * 0.22 }


    struct Particle {
        var origin: CGPoint      // fraction of the view
        var velocity: CGVector   // points per second
        var delay: Double
        var size: CGSize
        var spin: Double         // radians per second
        var flutter: Double      // flips per second (fake 3D)
        var phase: Double
        var circle: Bool
        var ink: Color
    }

    var body: some View {
        if !finished { celebration }
    }

    private var celebration: some View {
        let stamps = shown
        return TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.9 : context.date.timeIntervalSince(start)
            ZStack {
                Canvas { gc, size in draw(gc, size: size, t: t) }
                GeometryReader { geo in
                    ForEach(stamps.indices, id: \.self) { i in
                        let k = t - Self.landing(i)
                        StampView(spec: stamps[i])
                            .frame(width: 92, height: 92)
                            .scaleEffect(reduceMotion ? 1 : k < 0 ? 0 : 1 + 1.4 * exp(-9 * k) * cos(13 * k))  // big, then a wobble
                            .opacity(k < 0 && !reduceMotion ? 0 : 1)
                            .position(x: geo.size.width * Self.spots[i].x, y: geo.size.height * Self.spots[i].y)
                    }
                }
            }
            .opacity(t > duration - 0.6 ? max(0, (duration - t) / 0.6) : 1)
        }
        .opacity(fading ? 0 : 1)  // Reduce Motion: time stands still, so the fade comes from here
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .heavy), trigger: thumps)
        .task {
            shown = Array((stamps + (0..<3).map { _ in StampSpec.random() }).prefix(3))
            particles = Self.rings()
            start = .now
            // A cancelled task (the screen closed) stops here: no haptic on the way out.
            do {
                if !reduceMotion {
                    for i in Self.spots.indices {  // one thump as each stamp lands
                        try await Task.sleep(for: .seconds(i == 0 ? Self.landing(0) : Self.landing(i) - Self.landing(i - 1)))
                        thumps += 1
                    }
                }
                try await Task.sleep(for: .seconds(duration - 0.6 - (reduceMotion ? 0 : Self.landing(2))))
                if reduceMotion { withAnimation(.easeOut(duration: 0.6)) { fading = true } }
                try await Task.sleep(for: .seconds(0.6))
                finished = true
            } catch { return }
        }
    }

    private func draw(_ gc: GraphicsContext, size: CGSize, t: Double) {
        guard t < duration else { return }
        for p in particles where t >= p.delay || reduceMotion {
            let k = max(0, t - p.delay)
            var g = gc
            g.translateBy(x: p.origin.x * size.width + p.velocity.dx * k, y: p.origin.y * size.height + p.velocity.dy * k + 300 * k * k)
            g.rotate(by: .radians(p.phase + p.spin * k))
            g.scaleBy(x: cos(k * p.flutter + p.phase), y: 1)
            let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height)
            g.fill(p.circle ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5), with: .color(p.ink.opacity(0.9)))
        }
    }

    /// A ring of pieces bursting from each stamp as it lands.
    private static func rings() -> [Particle] {
        let inks = StampInk.allCases.map(\.ink)
        return spots.indices.flatMap { i in
            (0..<26).map { _ in
                let angle = Double.random(in: 0...(2 * .pi)), speed = Double.random(in: 160...420)
                return Particle(origin: spots[i], velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                delay: landing(i) + .random(in: 0...0.08), size: CGSize(width: .random(in: 5...9), height: .random(in: 8...14)),
                                spin: .random(in: -6...6), flutter: .random(in: 4...10), phase: .random(in: 0...(2 * .pi)),
                                circle: Int.random(in: 0..<5) == 0, ink: inks.randomElement()!)
            }
        }
    }
}
