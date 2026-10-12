import SwiftUI
import Testing
@testable import TripSplit

/// Reduce Motion is decided in one place (TRIP-31).
struct MotionTests {
    @Test func reduceMotionOff() {
        #expect(Motion.quick.animation(reduceMotion: false) == .default)
        #expect(Motion.standard.animation(reduceMotion: false) == .default)
        #expect(Motion.celebrate.animation(reduceMotion: false) == .spring(response: 0.35, dampingFraction: 0.55))
    }

    @Test func reduceMotionOn() {
        #expect(Motion.celebrate.animation(reduceMotion: true) == nil)
        #expect(Motion.quick.animation(reduceMotion: true) == .easeInOut(duration: 0.2))
        #expect(Motion.standard.animation(reduceMotion: true) == .easeInOut(duration: 0.2))
    }
}
