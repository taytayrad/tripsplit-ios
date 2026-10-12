import Foundation
import Testing
@testable import TripSplit

/// The shared failed-save alert (TRIP-33, Figma X7).
struct FailureTests {
    @Test func messageIsTheSharedSentence() {
        #expect(Failure(title: "Couldn’t save") {}.message == "Check your connection and try again.")
    }

    @Test func offlineFailureStartsWithTheSameSentence() {
        let f = Failure(title: "Couldn’t log the payment", error: URLError(.notConnectedToInternet)) {}
        #expect(f.message.hasPrefix("Check your connection and try again."))
    }
}
