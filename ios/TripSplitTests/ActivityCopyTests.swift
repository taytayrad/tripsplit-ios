import Foundation
import Testing
@testable import TripSplit

/// Activity statements and dollar lines (docs/events.md). Money in these cases is integer cents.
struct ActivityCopyTests {
    static let you = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let alex = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let connor = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let tyler = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    static let sammy = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    static let jordan = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    static let taylor = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!

    func expect(_ event: ActivityCopy.Event, _ statement: String, dollar: String? = nil,
                viewer: UUID = ActivityCopyTests.you, viewerName: String = "",
                fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column) {
        let source = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
        let result = ActivityCopy.line(event, viewer: viewer, viewerName: viewerName)
        #expect(result.statement == statement, sourceLocation: source)
        #expect(result.dollarLine == dollar, sourceLocation: source)
    }

    // MARK: Statements (docs/events.md matrix)

    @Test func youCreatedTheTrip() {
        expect(.init(kind: .tripCreated, actorId: Self.you, actorName: "Alex Kim", tripName: "Coast Road"),
               "You created the trip \"Coast Road\"")
    }

    @Test func someoneElseCreatedTheTrip() {
        expect(.init(kind: .tripCreated, actorId: Self.alex, actorName: "Alex", tripName: "Coast Road"),
               "Alex created the trip \"Coast Road\"")
    }

    @Test func memberJoined() {
        expect(.init(kind: .memberJoined, actorId: Self.alex, actorName: "Alex", tripName: "Coast Road"),
               "Alex joined \"Coast Road\"")
    }

    @Test func youJoined() {
        expect(.init(kind: .memberJoined, actorId: Self.you, actorName: "Alex Kim", tripName: "Coast Road"),
               "You joined \"Coast Road\"")
    }

    @Test func expenseAddedNamesTheActorTitleAndTrip() {
        expect(.init(kind: .expenseAdded, actorId: Self.connor, actorName: "Connor", tripName: "Coast Road",
                      subject: "Airbnb", deltas: [Self.you: -3600]),
               "Connor added \"Airbnb\" in \"Coast Road\"", dollar: "You owe $36")
    }

    @Test func youAddedAnExpense() {
        expect(.init(kind: .expenseAdded, actorId: Self.you, actorName: "Alex Kim", tripName: "Night Market",
                      subject: "Lyft", deltas: [Self.you: 5000]),
               "You added \"Lyft\" in \"Night Market\"", dollar: "You get back $50")
    }

    @Test func expenseUpdatedUsesTheChange() {
        expect(.init(kind: .expenseUpdated, actorId: Self.tyler, actorName: "Tyler", tripName: "Lake House",
                      subject: "Costco", deltas: [Self.you: 11740]),
               "Tyler updated \"Costco\" in \"Lake House\"", dollar: "You get back $117.40")
    }

    @Test func expenseDeletedUsesTheReversalDelta() {
        // The stored delta is already the reversal. A share you owed $50 for comes back as +50.
        expect(.init(kind: .expenseDeleted, actorId: Self.tyler, actorName: "Tyler", tripName: "Lake House",
                      subject: "Costco", deltas: [Self.you: 5000]),
               "Tyler deleted \"Costco\" in \"Lake House\"", dollar: "You get back $50")
    }

    @Test func someonePaidYou() {
        // The payee's delta is negative. The line is "You received", not the expense rule's "You owe".
        expect(.init(kind: .paymentLogged, actorId: Self.sammy, actorName: "Sammy", tripName: "Orlando 2027",
                      deltas: [Self.sammy: 51844, Self.you: -51844],
                      payerId: Self.sammy, payeeId: Self.you, payerName: "Sammy", payeeName: "Alex Kim", amountCents: 51844),
               "Sammy paid you in \"Orlando 2027\"", dollar: "You received $518.44")
    }

    @Test func youPaid() {
        // Amount stays in the statement. The payer's delta is positive; there is still no dollar line.
        expect(.init(kind: .paymentLogged, actorId: Self.you, actorName: "Alex Kim", tripName: "Coast Road",
                      deltas: [Self.you: 3000, Self.connor: -3000],
                      payerId: Self.you, payeeId: Self.connor, payerName: "Alex Kim", payeeName: "Connor", amountCents: 3000),
               "You paid Connor $30 in \"Coast Road\"")
    }

    @Test func youPaidUsesTheShownName() {
        expect(.init(kind: .paymentLogged, actorId: Self.you, actorName: "Alex Kim", tripName: "Coast Road",
                      payerId: Self.you, payeeId: Self.connor, payerName: "Alex Kim", payeeName: "Connor Smith", amountCents: 3000),
               "You paid Connor S. $30 in \"Coast Road\"")
    }

    @Test func paymentBetweenOthers() {
        expect(.init(kind: .paymentLogged, actorId: Self.tyler, actorName: "Tyler", tripName: "Lake House",
                      deltas: [Self.tyler: 3000, Self.connor: -3000],
                      payerId: Self.tyler, payeeId: Self.connor, payerName: "Tyler", payeeName: "Connor", amountCents: 3000),
               "Tyler paid Connor in \"Lake House\"")
    }

    @Test func paymentDeletedAfterSomeonePaidYou() {
        expect(.init(kind: .paymentDeleted, actorId: Self.sammy, actorName: "Sammy", tripName: "Orlando 2027",
                      deltas: [Self.sammy: -51844, Self.you: 51844],
                      payerId: Self.sammy, payeeId: Self.you, amountCents: 51844),
               "Sammy removed a payment in \"Orlando 2027\"", dollar: "You get back $518.44")
    }

    @Test func paymentDeletedAfterYouPaid() {
        expect(.init(kind: .paymentDeleted, actorId: Self.you, actorName: "Alex Kim", tripName: "Coast Road",
                      deltas: [Self.you: -3000, Self.connor: 3000],
                      payerId: Self.you, payeeId: Self.connor, amountCents: 3000),
               "You removed a payment in \"Coast Road\"", dollar: "You owe $30")
    }

    @Test func paymentDeletedBetweenOthers() {
        expect(.init(kind: .paymentDeleted, actorId: Self.tyler, actorName: "Tyler", tripName: "Lake House",
                      deltas: [Self.tyler: -3000, Self.connor: 3000],
                      payerId: Self.tyler, payeeId: Self.connor, amountCents: 3000),
               "Tyler removed a payment in \"Lake House\"")
    }

    @Test func tripDeleted() {
        expect(.init(kind: .tripDeleted, actorId: Self.sammy, actorName: "Sammy", tripName: "Orlando 2027",
                      deltas: [Self.you: -5000]),
               "Sammy deleted the trip \"Orlando 2027\"")
    }

    @Test func youDeletedTheTrip() {
        expect(.init(kind: .tripDeleted, actorId: Self.you, actorName: "Alex Kim", tripName: "Orlando 2027"),
               "You deleted the trip \"Orlando 2027\"")
    }

    @Test func tripRestored() {
        expect(.init(kind: .tripUndeleted, actorId: Self.sammy, actorName: "Sammy", tripName: "Orlando 2027"),
               "Sammy restored the trip \"Orlando 2027\"")
    }

    @Test func youRestoredTheTrip() {
        expect(.init(kind: .tripUndeleted, actorId: Self.you, actorName: "Alex Kim", tripName: "Orlando 2027"),
               "You restored the trip \"Orlando 2027\"")
    }

    @Test func memberRemoved() {
        expect(.init(kind: .memberRemoved, actorId: Self.taylor, actorName: "Taylor", tripName: "Coast Road",
                      subject: "Jordan", removedId: Self.jordan),
               "Taylor removed Jordan from \"Coast Road\"")
    }

    @Test func memberLeft() {
        expect(.init(kind: .memberRemoved, actorId: Self.jordan, actorName: "Jordan", tripName: "Coast Road",
                      subject: "Jordan", removedId: Self.jordan),
               "Jordan left \"Coast Road\"")
    }

    @Test func youLeft() {
        expect(.init(kind: .memberRemoved, actorId: Self.you, actorName: "Alex Kim", tripName: "Coast Road",
                      subject: "Alex Kim", removedId: Self.you),
               "You left \"Coast Road\"")
    }

    @Test func youRemovedSomeone() {
        expect(.init(kind: .memberRemoved, actorId: Self.you, actorName: "Alex Kim", tripName: "Coast Road",
                      subject: "Jordan", removedId: Self.jordan),
               "You removed Jordan from \"Coast Road\"")
    }

    @Test func someoneRemovedYou() {
        expect(.init(kind: .memberRemoved, actorId: Self.taylor, actorName: "Taylor", tripName: "Coast Road",
                      subject: "Alex Kim", removedId: Self.you),
               "Taylor removed you from \"Coast Road\"")
    }

    @Test func shownNamesInARemoval() {
        expect(.init(kind: .memberRemoved, actorId: Self.taylor, actorName: "Taylor Smith", tripName: "Coast Road",
                      subject: "Jordan Lee", removedId: Self.jordan),
               "Taylor S. removed Jordan L. from \"Coast Road\"")
    }

    /// The event stores the removed person's name, not their id. Matching names mean they left.
    @Test func leaveWhenTheSubjectIsTheActorsName() {
        expect(.init(kind: .memberRemoved, actorId: Self.jordan, actorName: "Jordan", tripName: "Coast Road",
                      subject: "Jordan"),
               "Jordan left \"Coast Road\"")
    }

    @Test func removedYouWhenTheSubjectIsYourName() {
        expect(.init(kind: .memberRemoved, actorId: Self.taylor, actorName: "Taylor", tripName: "Coast Road",
                      subject: "Alex Kim"),
               "Taylor removed you from \"Coast Road\"", viewerName: "Alex Kim")
    }

    @Test func missingActorNameReadsAsSomeone() {
        expect(.init(kind: .memberJoined, actorId: Self.alex, actorName: "", tripName: "Coast Road"),
               "Someone joined \"Coast Road\"")
    }

    // MARK: Lyft $100 (docs/events.md). Same rules for added, updated, and deleted.

    struct LyftLine: Sendable, CustomTestStringConvertible {
        var note: String
        var delta: Int
        var youPaid: Bool
        /// Nil when you are not in the split.
        var share: Int?
        var line: String?
        var testDescription: String { note }
    }

    static let lyft: [LyftLine] = [
        .init(note: "You paid; you and Alex equally", delta: 5000, youPaid: true, share: 5000, line: "You get back $50"),
        .init(note: "You paid; only you in the split", delta: 0, youPaid: true, share: 10000, line: "You paid $100"),
        .init(note: "You paid; Alex and Jordan only", delta: 10000, youPaid: true, share: nil, line: "You get back $100"),
        .init(note: "Alex paid; you and Alex equally", delta: -5000, youPaid: false, share: 5000, line: "You owe $50"),
        .init(note: "Alex paid; you not in the split", delta: 0, youPaid: false, share: nil, line: nil),
    ]

    @Test(arguments: [ActivityKind.expenseAdded, .expenseUpdated, .expenseDeleted], ActivityCopyTests.lyft)
    func lyftDollarLines(_ kind: ActivityKind, _ lyft: LyftLine) {
        let verb = switch kind {
        case .expenseAdded: "added"
        case .expenseUpdated: "updated"
        case .expenseDeleted: "deleted"
        default: ""
        }
        let event = ActivityCopy.Event(
            kind: kind, actorId: Self.connor, actorName: "Connor", tripName: "Night Market", subject: "Lyft",
            deltas: lyft.delta == 0 ? [:] : [Self.you: lyft.delta],
            expensePayerId: lyft.youPaid ? Self.you : Self.alex,
            expenseAmountCents: 10000, viewerShareCents: lyft.share)
        expect(event, "Connor \(verb) \"Lyft\" in \"Night Market\"", dollar: lyft.line)
    }

    @Test func ownCostNeedsTheWholeShare() {
        // Delta 0, you paid, but your share is only part of it: no dollar line.
        expect(.init(kind: .expenseAdded, actorId: Self.you, actorName: "Alex", tripName: "Night Market",
                      subject: "Lyft", expensePayerId: Self.you, expenseAmountCents: 10000, viewerShareCents: 5000),
               "You added \"Lyft\" in \"Night Market\"")
    }
}
