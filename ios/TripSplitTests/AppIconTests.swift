import Testing
import UIKit
@testable import TripSplit

struct AppIconTests {
    @Test @MainActor func allChoicesAreBundled() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let icons = try #require(bundle.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")
        let alternates = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
        #expect(Set(alternates.keys) == Set(AppIconChoice.allCases.compactMap(\.alternateName)))
        #expect(AppIconChoice.d1.alternateName == nil)
        for choice in AppIconChoice.allCases {
            #expect(UIImage(named: choice.previewName, in: bundle, compatibleWith: nil) != nil)
            let entry = choice.alternateName.flatMap { alternates[$0] as? [String: Any] } ?? primary
            let expectedName = choice.alternateName ?? "AppIcon"
            #expect(entry["CFBundleIconName"] as? String == expectedName)
        }
    }
}
