import Foundation
import Testing
@testable import TripSplit

struct DeviceTokenTests {
    @Test func theTokenIsLowercaseHex() {
        #expect(AppDelegate.hex(Data([0x00, 0x0f, 0xab, 0xff])) == "000fabff")
    }
}
