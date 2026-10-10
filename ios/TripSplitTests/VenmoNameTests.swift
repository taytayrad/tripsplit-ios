import Testing
@testable import TripSplit

/// The Venmo username on Profile and in onboarding (Figma Profile F3).
struct VenmoNameTests {
    @Test func cleaningDropsTheAtAndSpaces() {
        #expect(VenmoName.clean(" @taylor-r ") == "taylor-r")
        #expect(VenmoName.clean("@@taylor r") == "taylorr")
        #expect(VenmoName.clean("") == "")
    }

    @Test(arguments: ["taylor-r", "Taylor_Radford", "abcde", String(repeating: "a", count: 30)])
    func valid(_ name: String) { #expect(VenmoName.isValid(name)) }

    @Test(arguments: ["abcd", String(repeating: "a", count: 31), "taylor.r", "taylör", "tay lor"])
    func invalid(_ name: String) { #expect(!VenmoName.isValid(name)) }
}
