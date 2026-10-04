import Foundation
import Testing
@testable import TripSplit

/// Phase 4's pure rules: Your Balance (M3–M5, and the chip equals the rows), a person's screen (M2, M9, M10),
/// the pay bar, and where a logged payment goes (A1–A5). Amounts in cents; the server stays the source of truth.
struct SettlingTests {
    static let you = UUID(), alex = UUID(), jordan = UUID(), connor = UUID(), tyler = UUID()
    static let names = [alex: "Alex", jordan: "Jordan", connor: "Connor", tyler: "Tyler"]
    static func name(_ id: UUID) -> String { names[id] ?? "?" }
    static func day(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }

    static func trip(_ name: String, _ people: [UUID], start: String? = nil, created: String = "2026-09-01") -> Trip {
        Trip(id: UUID(), name: name, stamp: .random(), startDate: start, endDate: start, inviteToken: "", createdBy: you,
             createdAt: day(created),
             tripMembers: people.enumerated().map { Member(userId: $1, position: $0, removedAt: nil, profiles: PersonName(id: $1, displayName: name)) })
    }

    static func expense(_ title: String, on trip: Trip, cents: Int, paidBy payer: UUID, shares: [UUID: Int], day d: String = "2026-10-01") -> Expense {
        Expense(id: UUID(), tripId: trip.id, description: title, icon: .general, amountCents: cents, payerId: payer, splitKind: .exact,
                spentOn: d, createdBy: payer, createdAt: day(d),
                expenseShares: shares.map { ExpenseShare(userId: $0, shareCents: $1, splitInput: nil) })
    }

    static func payment(on trip: Trip, from payer: UUID, to payee: UUID, cents: Int, method: PayMethod) -> Payment {
        Payment(id: UUID(), tripId: trip.id, payerId: payer, payeeId: payee, amountCents: cents, method: method, createdAt: day("2026-10-02"))
    }

    // MARK: Your Balance

    // M3: you owe Alex 90, Jordan 90, Connor 12; Tyler owes you 64. Header -128.
    @Test func yourBalanceGroupsPeopleAndTheChipEqualsTheRows() {
        let t = UUID(), u = UUID(), v = UUID()
        let pairs = [PairBalance(tripId: t, otherUserId: Self.alex, cents: -9000),
                     PairBalance(tripId: t, otherUserId: Self.jordan, cents: -9000),
                     PairBalance(tripId: u, otherUserId: Self.connor, cents: -1200),
                     PairBalance(tripId: v, otherUserId: Self.tyler, cents: 6400)]
        let s = BalanceSummary(pairs: pairs, name: Self.name)
        #expect(s.total == -12800)
        #expect(s.youOwe.map(\.name) == ["Alex", "Jordan", "Connor"])
        #expect(s.youOwe.map(\.cents) == [-9000, -9000, -1200])
        #expect(s.owesYou.map(\.name) == ["Tyler"])
        #expect(s.total == (s.youOwe + s.owesYou).map(\.cents).reduce(0, +))
        #expect(s.tripCount == 3)
    }

    // M4: two trips with Alex are one row.
    @Test func twoTripsWithOnePersonAreOneRow() {
        let s = BalanceSummary(pairs: [PairBalance(tripId: UUID(), otherUserId: Self.alex, cents: -6000),
                                       PairBalance(tripId: UUID(), otherUserId: Self.alex, cents: -3000)], name: Self.name)
        #expect(s.youOwe.map(\.cents) == [-9000])
        #expect(s.tripCount == 2)
    }

    // M5: owing Alex on one trip and being owed the same on another lists nobody.
    @Test func aPersonWhoNetsToZeroIsNotListed() {
        let s = BalanceSummary(pairs: [PairBalance(tripId: UUID(), otherUserId: Self.alex, cents: -2000),
                                       PairBalance(tripId: UUID(), otherUserId: Self.alex, cents: 2000)], name: Self.name)
        #expect(s.youOwe.isEmpty && s.owesYou.isEmpty)
        #expect(s.total == 0)
        #expect(s.tripCount == 0)
    }

    // Settled people stay reachable, so a payment that settled them can still be seen and deleted.
    @Test func settledPeopleAreEveryoneElseYouShareATripWith() {
        let s = BalanceSummary(pairs: [PairBalance(tripId: UUID(), otherUserId: Self.alex, cents: -2000)], name: Self.name,
                               people: [Self.alex, Self.tyler, Self.jordan])
        #expect(s.youOwe.map(\.name) == ["Alex"])
        #expect(s.settled.map(\.name) == ["Jordan", "Tyler"])
        #expect(s.settled.allSatisfy { $0.cents == 0 })
    }

    @Test func tripNetsAreTheSumOfTheirPairs() {
        let t = UUID()
        let nets = BalanceSummary.tripNets([PairBalance(tripId: t, otherUserId: Self.alex, cents: 2806),
                                            PairBalance(tripId: t, otherUserId: Self.jordan, cents: 2808)])
        #expect(nets == [t: 5614])  // M1: you +56.14
    }

    // MARK: A person's screen

    // M10: Alex paid $60 dinner, you paid $30 gas, both equal three ways. You owe Alex $10.
    @Test func chargesShowEachSidesPartAndAddUpToTheTripNet() {
        let cr = Self.trip("Coast Road", [Self.you, Self.alex, Self.jordan])
        let dinner = Self.expense("Dinner", on: cr, cents: 6000, paidBy: Self.alex, shares: [Self.you: 2000, Self.alex: 2000, Self.jordan: 2000], day: "2026-09-30")
        let gas = Self.expense("Gas", on: cr, cents: 3000, paidBy: Self.you, shares: [Self.you: 1000, Self.alex: 1000, Self.jordan: 1000])
        let ledger = PersonLedger(me: Self.you, other: Self.alex, otherName: "Alex", tripsNewestFirst: [cr], expenses: [gas, dinner],
                                  payments: [], pairs: [PairBalance(tripId: cr.id, otherUserId: Self.alex, cents: -1000)])
        #expect(ledger.total == -1000)
        #expect(ledger.groups.map(\.name) == ["Coast Road"])
        #expect(ledger.groups[0].lines.map(\.title) == ["Dinner", "Gas"])
        #expect(ledger.groups[0].lines.map(\.cents) == [-2000, 1000])
        #expect(ledger.groups[0].lines.map(\.effect).reduce(0, +) == ledger.groups[0].net)
    }

    // M2: you paid for Alex and Jordan only. Expenses that don't involve Alex aren't on Alex's screen.
    @Test func expensesBetweenOtherPeopleAreLeftOut() {
        let cr = Self.trip("Coast Road", [Self.you, Self.alex, Self.jordan])
        let snacks = Self.expense("Snacks", on: cr, cents: 3000, paidBy: Self.you, shares: [Self.alex: 1500, Self.jordan: 1500])
        let jordans = Self.expense("Parking", on: cr, cents: 2000, paidBy: Self.jordan, shares: [Self.jordan: 1000, Self.alex: 1000])
        let ledger = PersonLedger(me: Self.you, other: Self.alex, otherName: "Alex", tripsNewestFirst: [cr], expenses: [snacks, jordans],
                                  payments: [], pairs: [PairBalance(tripId: cr.id, otherUserId: Self.alex, cents: 1500)])
        #expect(ledger.groups[0].lines.map(\.title) == ["Snacks"])
        #expect(ledger.groups[0].lines.map(\.cents) == [1500])
    }

    // M9: Alex logs $28.06 to you after M1. The payment is a neutral line, and the trip is settled with Alex.
    @Test func paymentsAreNeutralLinesThatSettleTheTrip() {
        let cr = Self.trip("Coast Road", [Self.you, Self.alex, Self.jordan])
        let costco = Self.expense("Costco", on: cr, cents: 8420, paidBy: Self.you, shares: [Self.you: 2806, Self.alex: 2806, Self.jordan: 2808])
        let paid = Self.payment(on: cr, from: Self.alex, to: Self.you, cents: 2806, method: .recorded)
        let ledger = PersonLedger(me: Self.you, other: Self.alex, otherName: "Alex", tripsNewestFirst: [cr], expenses: [costco],
                                  payments: [paid], pairs: [])
        let lines = ledger.groups[0].lines
        #expect(lines.map(\.title) == ["Costco", "Alex paid you"])
        #expect(lines.map(\.isPayment) == [false, true])
        #expect(lines[1].cents == 2806)
        #expect(lines.map(\.effect).reduce(0, +) == 0)
        #expect(ledger.total == 0)
    }

    @Test func paymentLinesNameTheMethod() {
        let cr = Self.trip("Coast Road", [Self.you, Self.jordan])
        let ledger = PersonLedger(me: Self.you, other: Self.jordan, otherName: "Jordan", tripsNewestFirst: [cr], expenses: [],
                                  payments: [Self.payment(on: cr, from: Self.you, to: Self.jordan, cents: 6000, method: .venmo),
                                             Self.payment(on: cr, from: Self.jordan, to: Self.you, cents: 500, method: .cash)],
                                  pairs: [])
        #expect(ledger.groups[0].lines.map(\.title) == ["You paid · Venmo", "Jordan paid you · Cash"])
    }

    // PRD › Prototype decisions: newest trip first; settled trips hide behind "Show settled trips", except one
    // that just reached $0 while the screen is open.
    @Test func settledTripsHideUnlessJustSettledOrShown() {
        let lh = Self.trip("Lake House", [Self.you, Self.jordan], created: "2026-09-12")
        let cr = Self.trip("Coast Road", [Self.you, Self.jordan], created: "2026-10-03")
        let boat = Self.expense("Boat rental", on: lh, cents: 6000, paidBy: Self.jordan, shares: [Self.you: 3000, Self.jordan: 3000])
        let gas = Self.expense("Gas", on: cr, cents: 3000, paidBy: Self.jordan, shares: [Self.you: 1500, Self.jordan: 1500])
        let paid = Self.payment(on: lh, from: Self.you, to: Self.jordan, cents: 3000, method: .venmo)
        let ledger = PersonLedger(me: Self.you, other: Self.jordan, otherName: "Jordan", tripsNewestFirst: [cr, lh], expenses: [boat, gas],
                                  payments: [paid], pairs: [PairBalance(tripId: cr.id, otherUserId: Self.jordan, cents: -1500)])
        #expect(ledger.groups.map(\.name) == ["Coast Road", "Lake House"])
        #expect(ledger.visible(showSettled: false, keep: []).map(\.name) == ["Coast Road"])
        #expect(ledger.visible(showSettled: false, keep: [lh.id]).map(\.name) == ["Coast Road", "Lake House"])
        #expect(ledger.visible(showSettled: true, keep: []).map(\.name) == ["Coast Road", "Lake House"])
        #expect(ledger.hiddenCount(keep: []) == 1)
        #expect(ledger.openTripCount == 1)
    }

    // A member removed with keep can't read the trip, but its pair rows and their own payments still arrive.
    @Test func aTripYouCantReadStillShowsItsBalanceAndPayments() {
        let gone = UUID()
        let paid = Payment(id: UUID(), tripId: gone, payerId: Self.you, payeeId: Self.alex, amountCents: 1000, method: .cash, createdAt: Self.day("2026-10-02"))
        let ledger = PersonLedger(me: Self.you, other: Self.alex, otherName: "Alex", tripsNewestFirst: [], expenses: [],
                                  payments: [paid], pairs: [PairBalance(tripId: gone, otherUserId: Self.alex, cents: -2000)])
        #expect(ledger.groups.map(\.id) == [gone])
        #expect(ledger.groups[0].name == PersonLedger.unreadableTripName)
        #expect(ledger.groups[0].net == -2000)
        #expect(ledger.groups[0].lines.map(\.title) == ["You paid · Cash"])
    }

    // Payments on a deleted trip stay readable, but a deleted trip has no pair rows. It must not come back as
    // "A trip you were removed from" (deleted trips' amounts are hidden).
    @Test func aDeletedTripsPaymentsDontComeBack() {
        let deleted = UUID()
        let paid = Payment(id: UUID(), tripId: deleted, payerId: Self.you, payeeId: Self.alex, amountCents: 1000, method: .cash, createdAt: Self.day("2026-10-02"))
        let ledger = PersonLedger(me: Self.you, other: Self.alex, otherName: "Alex", tripsNewestFirst: [], expenses: [], payments: [paid], pairs: [])
        #expect(ledger.groups.isEmpty)
    }

    // MARK: Pay bar

    static func profile(_ id: UUID, venmo: String? = nil, zelle: Bool = false, appleCash: Bool = false) -> Profile {
        Profile(id: id, displayName: "", venmoUsername: venmo, hasZelle: zelle, hasAppleCash: appleCash)
    }

    // PRD › Settling: a method shows only when both of you have it; Cash always; Record when they owe you.
    @Test func payBarShowsOnlySharedMethodsAndAlwaysCash() {
        let me = Self.profile(Self.you, venmo: "taylor", zelle: true, appleCash: true)
        let them = Self.profile(Self.jordan, venmo: "jordan-k", zelle: true, appleCash: false)
        #expect(PayBar.actions(me: me, them: them, total: -9000) == [.venmo(username: "jordan-k"), .zelle, .cash])
        #expect(PayBar.actions(me: Self.profile(Self.you), them: them, total: -9000) == [.cash])
    }

    @Test func payBarRecordsWhenTheyOweYouAndIsGoneWhenSettled() {
        let me = Self.profile(Self.you, venmo: "taylor"), them = Self.profile(Self.alex, venmo: "alex")
        #expect(PayBar.actions(me: me, them: them, total: 2806) == [.record])
        #expect(PayBar.actions(me: me, them: them, total: 0).isEmpty)
    }

    @Test func aBlankVenmoUsernameIsNotAMethod() {
        #expect(PayBar.actions(me: Self.profile(Self.you, venmo: ""), them: Self.profile(Self.alex, venmo: "alex"), total: -100) == [.cash])
    }

    // MARK: Allocation (A1–A5)

    // You owe Jordan: Lake House (Sep 12) $30, Coast Road (Oct 3) $60.
    static let lh = Allocation.OpenTrip(id: UUID(), name: "Lake House", owed: 3000, startDay: "2026-09-12", created: day("2026-09-01"))
    static let cr = Allocation.OpenTrip(id: UUID(), name: "Coast Road", owed: 6000, startDay: "2026-10-03", created: day("2026-08-01"))

    @Test func a1PayingEverythingPaysOffBothOldestFirst() {
        let parts = Allocation.plan(9000, across: [Self.cr, Self.lh])
        #expect(parts?.map(\.cents) == [3000, 6000])
        #expect(parts?.map(\.name) == ["Lake House", "Coast Road"])
        #expect(Allocation.note(parts ?? []) == "Pays off Lake House ($30) and Coast Road ($60).")
    }

    @Test func a2APartialPaymentFillsTheOldestTripFirst() {
        let parts = Allocation.plan(5000, across: [Self.cr, Self.lh])
        #expect(parts?.map(\.cents) == [3000, 2000])
        #expect(Allocation.note(parts ?? []) == "Pays off Lake House ($30) first, then $20 toward Coast Road.")
    }

    @Test func a3AnAmountWithinOneTripNeedsNoNote() {
        let parts = Allocation.plan(2000, across: [Self.cr, Self.lh])
        #expect(parts?.map(\.cents) == [2000])
        #expect(parts?.map(\.name) == ["Lake House"])
        #expect(Allocation.note(parts ?? []) == nil)
    }

    @Test func a4MoreThanIsOwedIsRejected() {
        #expect(Allocation.plan(10000, across: [Self.cr, Self.lh]) == nil)
        #expect(Allocation.plan(0, across: [Self.cr, Self.lh]) == nil)
    }

    @Test func a5RecordingTheWholeSingleTripBalance() {
        let one = Allocation.OpenTrip(id: UUID(), name: "Coast Road", owed: 2806, startDay: nil, created: Self.day("2026-10-03"))
        #expect(Allocation.plan(2806, across: [one])?.map(\.cents) == [2806])
    }

    // Trips without dates sort by when they were created (money-rules › Allocation).
    @Test func tripsWithoutDatesSortByCreatedDate() {
        let undated = Allocation.OpenTrip(id: UUID(), name: "Night Market", owed: 1000, startDay: nil, created: Self.day("2026-09-01"))
        #expect(Allocation.plan(4000, across: [Self.lh, undated])?.map(\.name) == ["Night Market", "Lake House"])
    }

    // log_payment orders by coalesce(start_date, created_at::date), created_at, with the date in UTC. A trip
    // created at 8:30 PM Pacific on Sep 11 is Sep 12 in UTC: it ties with a trip starting Sep 12, and the tie goes
    // to the trip created first.
    @Test func undatedTripsUseTheUTCDateOfCreationLikeTheServer() {
        let evening = Allocation.OpenTrip(id: UUID(), name: "Night Market", owed: 1000, startDay: nil,
                                          created: ISO8601DateFormatter().date(from: "2026-09-12T03:30:00Z")!)
        #expect(Allocation.plan(4000, across: [evening, Self.lh])?.map(\.name) == ["Lake House", "Night Market"])
    }

    @Test func threeTripsListEveryOneItPaysOff() {
        let undated = Allocation.OpenTrip(id: UUID(), name: "Night Market", owed: 1000, startDay: nil, created: Self.day("2026-09-01"))
        let parts = Allocation.plan(5000, across: [Self.cr, Self.lh, undated]) ?? []
        #expect(Allocation.note(parts) == "Pays off Night Market ($10) and Lake House ($30) first, then $10 toward Coast Road.")
    }

    // MARK: Log sheet

    @Test func theLogSheetSaysWhyItWontLogMore() {
        #expect(LogPayment.problem(cents: 10000, max: 9000, direction: .pay, otherName: "Jordan") == "That’s more than the $90 you owe Jordan.")
        #expect(LogPayment.problem(cents: 3000, max: 2806, direction: .record, otherName: "Alex") == "That’s more than the $28.06 Alex owes you.")
        #expect(LogPayment.problem(cents: 9000, max: 9000, direction: .pay, otherName: "Jordan") == nil)
        #expect(LogPayment.problem(cents: nil, max: 9000, direction: .pay, otherName: "Jordan") == "Enter an amount.")
        #expect(LogPayment.problem(cents: 0, max: 9000, direction: .pay, otherName: "Jordan") == "Enter an amount.")
    }

    // The cap keeps the sheet's direction: if the balance flips while it's open, nothing is owed that way.
    @Test func theCapFollowsTheSheetsDirection() {
        #expect(LogPayment.max(total: -9000, direction: .pay) == 9000)
        #expect(LogPayment.max(total: 3000, direction: .pay) == 0)
        #expect(LogPayment.max(total: 3000, direction: .record) == 3000)
        #expect(LogPayment.max(total: -9000, direction: .record) == 0)
        #expect(LogPayment.problem(cents: 3000, max: 0, direction: .pay, otherName: "Jordan") == "You don’t owe Jordan anything now.")
        #expect(LogPayment.problem(cents: 3000, max: 0, direction: .record, otherName: "Alex") == "Alex doesn’t owe you anything now.")
    }
}
