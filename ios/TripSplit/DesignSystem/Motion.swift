import SwiftUI

/// The app's only animations and haptics (TRIP-31). Every `withAnimation` / `.animation` goes through a token, and
/// Reduce Motion is decided here alone: views pass `@Environment(\.accessibilityReduceMotion)` in, never branch on it.
///
/// Guardrails (prd.md › Prototype decisions):
/// - Motion never delays a money action; writes stay outside the animation and don't wait for it.
/// - No celebration on errors or on what you owe: `celebrate` and `Haptic.settled` are only for a settled balance.
/// - Respect Reduce Motion.
enum Motion {
    /// In-place changes: Show / Hide settled trips, and Add/Edit trip's stamp, Dates toggle, and calendars.
    /// `Animation.default`, on iOS 17+ a spring with response 0.55, dampingFraction 1, blendDuration 0. Kept as
    /// `.default`: a spring written out with those numbers isn't equal to it.
    case quick
    /// The stage transition on `RootView` (sign in, onboarding, the app). Also `Animation.default`.
    case standard
    /// The stamp slam on a settled Member Ticket, and nothing else.
    case celebrate

    /// Reduce Motion on: `celebrate` doesn't animate (the stamp shows at rest), and the others become a short fade.
    func animation(reduceMotion: Bool) -> Animation? {
        switch (self, reduceMotion) {
        case (.celebrate, false): .spring(response: 0.35, dampingFraction: 0.55)
        case (.celebrate, true): nil
        case (_, false): .default
        case (_, true): .easeInOut(duration: 0.2)
        }
    }

    /// The four haptic meanings. Only `settled` is played today; Reduce Motion doesn't turn haptics off.
    enum Haptic {
        case selection, success, settled, warning

        var feedback: SensoryFeedback {
            switch self {
            case .selection: .selection
            case .success: .success
            case .settled: .impact(weight: .heavy)
            case .warning: .warning
            }
        }
    }
}
