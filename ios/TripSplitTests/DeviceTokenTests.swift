import Foundation
import Testing
@testable import TripSplit

struct DeviceTokenTests {
    @Test func theTokenIsLowercaseHex() {
        #expect(AppDelegate.hex(Data([0x00, 0x0f, 0xab, 0xff])) == "000fabff")
    }

    @Test func notificationPayloadAcceptsOnlyAnEventUUID() {
        let id = UUID()
        #expect(AppDelegate.eventId(["activity_event_id": id.uuidString]) == id)
        #expect(AppDelegate.eventId([:]) == nil)
        #expect(AppDelegate.eventId(["activity_event_id": "x&select=*"]) == nil)
        #expect(AppDelegate.eventId(["activity_event_id": 42]) == nil)
        #expect(AppDelegate.eventId(["trip_id": id.uuidString]) == nil)
    }

    @MainActor @Test func coldLaunchTapWaitsForTheAppThenTapsDeliverImmediately() {
        let delegate = AppDelegate()
        let first = UUID(), latest = UUID(), repeated = UUID()
        var received: [UUID] = []
        delegate.receiveNotification(first)
        delegate.receiveNotification(latest)
        delegate.onNotification = { received.append($0) }
        #expect(received == [latest])
        delegate.receiveNotification(repeated)
        delegate.receiveNotification(repeated)
        #expect(received == [latest, repeated, repeated])
        delegate.onNotification = { received.append($0) }
        #expect(received == [latest, repeated, repeated])
    }
}
