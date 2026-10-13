import SwiftUI

/// A ticket with real cut-out notches (TRIP-38, Figma Trips · character V1b): a rounded rectangle with two
/// semicircles removed on the tear line, so the background and the shadow follow the cut. A settled trip's row is
/// a used ticket: its stub torn off, leaving a perforated trailing edge.
struct TicketShape: Shape {
    enum Cut {
        /// A vertical tear line this far in from the trailing edge (the stub's width plus half the tear).
        case vertical(fromTrailing: CGFloat)
        /// A horizontal tear line this far down from the top (the large-text layout).
        case horizontal(fromTop: CGFloat)
        /// No stub: the trailing edge is perforated where it was torn off.
        case torn
    }

    var cut: Cut
    static let notchRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let r = Self.notchRadius
        switch cut {
        case .vertical(let fromTrailing):
            let x = rect.maxX - fromTrailing
            return Path(roundedRect: rect, cornerRadius: Radius.xl)
                .subtracting(notch(at: CGPoint(x: x, y: rect.minY), r))
                .subtracting(notch(at: CGPoint(x: x, y: rect.maxY), r))
        case .horizontal(let fromTop):
            let y = rect.minY + fromTop
            return Path(roundedRect: rect, cornerRadius: Radius.xl)
                .subtracting(notch(at: CGPoint(x: rect.minX, y: y), r))
                .subtracting(notch(at: CGPoint(x: rect.maxX, y: y), r))
        case .torn:
            var edge = Path()
            var y = rect.minY + 6
            while y < rect.maxY { edge.addPath(notch(at: CGPoint(x: rect.maxX, y: y), 5)); y += 12 }
            let card = UnevenRoundedRectangle(topLeadingRadius: Radius.xl, bottomLeadingRadius: Radius.xl).path(in: rect)
            return card.subtracting(edge)
        }
    }

    private func notch(at center: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }
}

extension View {
    /// The ticket's paper: the surface color with the Member Ticket shadow, no border.
    func ticketBackground(_ cut: TicketShape.Cut) -> some View {
        background {
            TicketShape(cut: cut).fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
    }
}

/// The dashed tear line between a ticket's notches, in the neutral separator color (red and green stay for money).
struct TearLine: View {
    var axis: Axis = .vertical

    var body: some View {
        Line(axis: axis)
            .stroke(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            // Stops 8 pt short of each notch.
            .padding(axis == .vertical ? .vertical : .horizontal, TicketShape.notchRadius + 8)
            .frame(width: axis == .vertical ? 2 * TicketShape.notchRadius : nil,
                   height: axis == .horizontal ? 2 * TicketShape.notchRadius : nil)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        let axis: Axis
        func path(in rect: CGRect) -> Path {
            Path {
                $0.move(to: CGPoint(x: axis == .vertical ? rect.midX : rect.minX, y: axis == .vertical ? rect.minY : rect.midY))
                $0.addLine(to: CGPoint(x: axis == .vertical ? rect.midX : rect.maxX, y: axis == .vertical ? rect.maxY : rect.midY))
            }
        }
    }
}
