import Testing
@testable import TripSplit

struct OnboardingTests {
    @Test(arguments: [nil, "", " \n\t "] as [String?])
    func anExistingBlankAccountMustSupplyAName(_ name: String?) {
        #expect(AppModel.Stage.afterSignIn(displayName: name, onboarded: true) == .payMethods)
    }

    @Test func aNewAccountStillCompletesOnboarding() {
        #expect(AppModel.Stage.afterSignIn(displayName: "Sam Taylor", onboarded: false) == .notifications)
    }

    @Test func aNamedReturningAccountIsReady() {
        #expect(AppModel.Stage.afterSignIn(displayName: "Sam Taylor", onboarded: true) == .ready)
    }
}
