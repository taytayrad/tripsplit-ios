import Foundation
import Testing
@testable import TripSplit

/// The net model's client rules (docs/money-rules.md): Settle up tickets from the server's suggestions, member
/// amounts, splitting a payment across trips, the trip ledger, and which pay methods show. The server suggests
/// and checks every payment; these only group and word them.
struct SettlingTests {
    static let you = UUID(), atish = UUID(), tyler = UUID(), sam = UUID(), jo = UUID()
    static func day(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }

    static func trip(_ name: String, start: String? = nil, created: String = "2026-09-01") -> Trip {
        Trip(id: UUID(), name: name, stamp: .random(), startDate: start, endDate: start, inviteToken: "", createdBy: you,
             createdAt: day(created), tripMembers: [])
    }

    static func s(_ trip: Trip, _ payer: UUID, _ payee: UUID, _ cents: Int, seq: Int = 1) -> Settlement {
        Settlement(tripId: trip.id, seq: seq, payerId: payer, payeeId: payee, cents: cents)
    }

    static func profile(_ id: UUID, venmo: String? = nil, zelle: Bool = false, appleCash: Bool = false) -> Profile {
        Profile(id: id, displayName: "", venmoUsername: venmo, hasZelle: zelle, hasAppleCash: appleCash)
    }

    // MARK: Tickets

    // G1: on Coast Road you pay Tyler $30; Atish is settled, so Atish has no ticket.
    @Test func g1OneTicketForTheOnePersonYouPay() {
        let cr = Self.trip("Coast Road")
        let tickets = SettleUp.tickets([Self.s(cr, Self.you, Self.tyler, 3000)], me: Self.you, trip: cr.id, tripsOldestFirst: [cr.id])
        #expect(tickets == [SettleTicket(personId: Self.tyler, direction: .pay, parts: [.init(tripId: cr.id, cents: 3000)])])
    }

    @Test func suggestionsBetweenOtherPeopleAreNotYourTickets() {
        let cr = Self.trip("Coast Road")
        let tickets = SettleUp.tickets([Self.s(cr, Self.atish, Self.tyler, 1000)], me: Self.you, trip: nil, tripsOldestFirst: [cr.id])
        #expect(tickets.isEmpty)
    }

    @Test func youOweTicketsComeFirstBiggestFirstThenYouLent() {
        let cr = Self.trip("Coast Road")
        let rows = [Self.s(cr, Self.jo, Self.you, 800), Self.s(cr, Self.you, Self.sam, 1200), Self.s(cr, Self.you, Self.tyler, 3000)]
        let tickets = SettleUp.tickets(rows, me: Self.you, trip: cr.id, tripsOldestFirst: [cr.id])
        #expect(tickets.map(\.personId) == [Self.tyler, Self.sam, Self.jo])
        #expect(tickets.map(\.direction) == [.pay, .pay, .record])
    }

    // All trips: Tyler on Coast Road ($30) and Lake House ($15) is one $45 ticket, oldest trip first.
    @Test func allTripsSumsAPersonAcrossTripsOldestFirst() {
        let cr = Self.trip("Coast Road", start: "2026-10-03"), lh = Self.trip("Lake House", start: "2026-09-12")
        let rows = [Self.s(cr, Self.you, Self.tyler, 3000), Self.s(lh, Self.you, Self.tyler, 1500)]
        let order = SettleUp.oldestFirst([cr, lh])
        #expect(order == [lh.id, cr.id])
        let all = SettleUp.tickets(rows, me: Self.you, trip: nil, tripsOldestFirst: order)
        #expect(all.count == 1)
        #expect(all[0].cents == 4500)
        #expect(all[0].tripIds == [lh.id, cr.id])
        let one = SettleUp.tickets(rows, me: Self.you, trip: cr.id, tripsOldestFirst: order)
        #expect(one.map(\.cents) == [3000])
    }

    @Test func undatedTripsSortByTheirCreatedDay() {
        let a = Self.trip("A", created: "2026-08-01"), b = Self.trip("B", start: "2026-09-01"), c = Self.trip("C", created: "2026-10-01")
        #expect(SettleUp.oldestFirst([c, b, a]) == [a.id, b.id, c.id])
    }

    // A payment page follows live balances: a trip that settled meanwhile drops out, a smaller balance shrinks.
    @Test func theCurrentTicketFollowsLiveSuggestions() {
        let cr = Self.trip("Coast Road"), lh = Self.trip("Lake House")
        let ticket = SettleTicket(personId: Self.tyler, direction: .pay, parts: [.init(tripId: lh.id, cents: 1500), .init(tripId: cr.id, cents: 3000)])
        let now = [Self.s(cr, Self.you, Self.tyler, 1000), Self.s(cr, Self.atish, Self.tyler, 2000)]
        #expect(SettleUp.current(ticket, now, me: Self.you) == [.init(tripId: cr.id, cents: 1000)])
        #expect(SettleUp.current(ticket, [], me: Self.you).isEmpty)
    }

    // MARK: Member amounts and settled

    // G2: M1's suggestions give every member's net.
    @Test func memberNetsFollowFromTheSuggestions() {
        let cr = Self.trip("Coast Road")
        let rows = [Self.s(cr, Self.atish, Self.you, 2808, seq: 1), Self.s(cr, Self.tyler, Self.you, 2806, seq: 2)]
        let nets = SettleUp.memberNets(trip: cr.id, rows)
        #expect(nets[Self.you] == 5614)
        #expect(nets[Self.atish] == -2808)
        #expect(nets[Self.tyler] == -2806)
        #expect(nets[Self.sam] == nil)
        #expect(!SettleUp.isSettled(trip: cr.id, rows))
        #expect(SettleUp.isSettled(trip: cr.id, []))
    }

    @Test func memberAmountsAreInWords() {
        #expect(MemberAmount(cents: -3000, isYou: true).label == "You owe")
        #expect(MemberAmount(cents: 800, isYou: true).label == "You lent")
        #expect(MemberAmount(cents: 3000, isYou: false).label == "Gets back")
        #expect(MemberAmount(cents: -1200, isYou: false).label == "Owes")
        #expect(MemberAmount(cents: 0, isYou: false).label == "Settled")
    }

    // MARK: Splitting a payment

    // P4: $45 to Tyler across Lake House ($15, older) and Coast Road ($30).
    @Test func p4TheTotalIsOnePaymentPerTrip() {
        let lh = UUID(), cr = UUID()
        let parts = [SettleTicket.Part(tripId: lh, cents: 1500), SettleTicket.Part(tripId: cr, cents: 3000)]
        #expect(SettleUp.split(4500, across: parts) == [PaymentPart(trip_id: lh, cents: 1500), PaymentPart(trip_id: cr, cents: 3000)])
        #expect(SettleUp.split(2000, across: parts) == [PaymentPart(trip_id: lh, cents: 1500), PaymentPart(trip_id: cr, cents: 500)])
        #expect(SettleUp.split(1000, across: parts) == [PaymentPart(trip_id: lh, cents: 1000)])
        #expect(SettleUp.split(4600, across: parts) == nil)
        #expect(SettleUp.split(0, across: parts) == nil)
    }

    @Test func theAmountCheckSaysWhy() {
        #expect(PaymentLimit.problem(cents: 4000, max: 3000, direction: .pay, otherName: "Tyler") == "That’s more than the $30 you owe Tyler.")
        #expect(PaymentLimit.problem(cents: 900, max: 800, direction: .record, otherName: "Jo") == "That’s more than the $8 Jo owes you.")
        #expect(PaymentLimit.problem(cents: nil, max: 3000, direction: .pay, otherName: "Tyler") == "Enter an amount.")
        #expect(PaymentLimit.problem(cents: 3000, max: 0, direction: .pay, otherName: "Tyler") == "You don’t owe Tyler anything now.")
        #expect(PaymentLimit.problem(cents: 2000, max: 3000, direction: .pay, otherName: "Tyler") == nil)
    }

    // MARK: Pay methods

    @Test func payingShowsOnlySharedMethodsAndAlwaysCash() {
        let me = Self.profile(Self.you, venmo: "me", zelle: true, appleCash: false)
        let them = Self.profile(Self.tyler, venmo: "tyler-b", zelle: true, appleCash: true)
        #expect(PayOptions.methods(direction: .pay, me: me, them: them) == [.venmo, .zelle, .cash])
        #expect(PayOptions.initial(direction: .pay, me: me, them: them) == .venmo)
        let noApps = Self.profile(Self.tyler, venmo: "")
        #expect(PayOptions.methods(direction: .pay, me: me, them: noApps) == [.cash])
    }

    @Test func recordingCanUseAnyMethodAndStartsOnCash() {
        #expect(PayOptions.methods(direction: .record, me: nil, them: nil) == [.venmo, .zelle, .appleCash, .cash])
        #expect(PayOptions.initial(direction: .record, me: nil, them: nil) == .cash)
    }

    // MARK: Ledger

    @Test func theLedgerIsExpensesAndPaymentsNewestFirst() {
        let cr = Self.trip("Coast Road")
        let stay = Expense(id: UUID(), tripId: cr.id, description: "Stay", icon: .lodging, amountCents: 6000, payerId: Self.tyler,
                           splitKind: .equal, spentOn: "2026-10-03", createdBy: Self.tyler, createdAt: Self.day("2026-10-03"), expenseShares: [])
        let dinner = Expense(id: UUID(), tripId: cr.id, description: "Dinner", icon: .restaurant, amountCents: 3000, payerId: Self.atish,
                             splitKind: .equal, spentOn: "2026-10-04", createdBy: Self.atish, createdAt: Self.day("2026-10-04"), expenseShares: [])
        let paid = Payment(id: UUID(), tripId: cr.id, payerId: Self.you, payeeId: Self.tyler, amountCents: 3000, method: .venmo,
                           paidOn: "2026-10-05", createdAt: Self.day("2026-10-05"))
        #expect(TripLedger.items(expenses: [stay, dinner], payments: [paid]).map(\.id) == [paid.id, dinner.id, stay.id])
    }
}
