import Foundation
import Testing
@testable import TripSplit

/// Hiding settled trips (PRD › Decisions › Hiding settled trips) and invite links.
struct TripLogicTests {
    static let calendar = Calendar(identifier: .gregorian)
    static func day(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }
    let today = day("2026-10-10")

    @Test func pastTripAtZeroHides() {
        #expect(TripVisibility.isHidden(endDate: Self.day("2026-10-06"), netCents: 0, today: today))
    }

    @Test func pastTripWithABalanceStays() {
        #expect(!TripVisibility.isHidden(endDate: Self.day("2026-10-06"), netCents: -9000, today: today))
    }

    @Test func tripWithoutDatesNeverHides() {
        #expect(!TripVisibility.isHidden(endDate: nil, netCents: 0, today: today))
    }

    @Test func tripEndingTodayStays() {
        #expect(!TripVisibility.isHidden(endDate: today, netCents: 0, today: today))
    }

    @Test func upcomingTripAtZeroStays() {
        #expect(!TripVisibility.isHidden(endDate: Self.day("2026-11-01"), netCents: 0, today: today))
    }

    static let token = "0f9b7c2a4d8e4f1a9b3c5d7e9f1a2b3c"

    @Test func theInvitePageIsTheOneWeDeploy() {
        #expect(InviteLink.page.absoluteString == "https://taytayrad.github.io/tripsplit-invite/join/")
    }

    @Test func shareURLPointsAtTheInvitePage() {
        let url = InviteLink.shareURL(token: Self.token, page: URL(string: "https://example.com/join/")!)
        #expect(url.absoluteString == "https://example.com/join/#\(Self.token)")
    }

    @Test(arguments: [
        "tripsplit://join/0f9b7c2a4d8e4f1a9b3c5d7e9f1a2b3c",
        "https://taytayrad.github.io/tripsplit-invite/join/#0f9b7c2a4d8e4f1a9b3c5d7e9f1a2b3c",
    ])
    func tokenFromLinks(_ link: String) {
        #expect(InviteLink.token(from: URL(string: link)!) == Self.token)
    }

    @Test(arguments: [
        "tripsplit://join/",
        "tripsplit://join/not-a-token",
        "tripsplit://other/0f9b7c2a4d8e4f1a9b3c5d7e9f1a2b3c",
        "https://example.com/something/#0f9b7c2a4d8e4f1a9b3c5d7e9f1a2b3c",
        "https://taytayrad.github.io/tripsplit-invite/join/",
        "https://example.com/join/#0f9b7c2a4d8e4f1a9b3c5d7e9f1a2b3c",
        "http://taytayrad.github.io/tripsplit-invite/join/#0f9b7c2a4d8e4f1a9b3c5d7e9f1a2b3c",
    ])
    func rejectsOtherLinks(_ link: String) {
        #expect(InviteLink.token(from: URL(string: link)!) == nil)
    }
}
