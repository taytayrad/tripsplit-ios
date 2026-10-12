import Testing
@testable import TripSplit

/// What VoiceOver reads for a net (TRIP-34): the screen's words, as one sentence, never a sign.
struct NetSentenceTests {
    @Test func owedAndOwe() {
        #expect(NetSentence.text(9000, name: "Alex") == "You’re owed Alex $90")
        #expect(NetSentence.text(-9000, name: "Alex") == "You owe Alex $90")
        #expect(NetSentence.text(5614, name: nil) == "You’re owed $56.14")
    }
}
