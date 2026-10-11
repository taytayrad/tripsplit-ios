import Foundation
import Supabase
import Testing
@testable import TripSplit

/// Profile autosave consistency (PR #35 reviews). Each test is one of the reported sequences.
struct ProfileSyncTests {
    static let base = Profile(id: UUID(), displayName: "Taylor Radford", venmoUsername: nil, hasZelle: false, hasAppleCash: false)

    static func with(_ change: (inout Profile) -> Void) -> Profile { var p = base; change(&p); return p }

    func loaded() -> ProfileSync {
        var sync = ProfileSync()
        sync.loaded(Self.base, startedAt: sync.epoch)
        return sync
    }

    @Test func anEditShowsAtOnce() {
        var sync = loaded()
        _ = sync.begin(["display_name": .string("Tay R")])
        #expect(sync.shown?.displayName == "Tay R")
        #expect(sync.confirmed?.displayName == "Taylor Radford")
    }

    /// Review 1: a load that started before a save settled is dropped.
    @Test func aLoadFromBeforeASaveSettledIsDropped() {
        var sync = loaded()
        let loadStarted = sync.epoch
        let zelle = sync.begin(["has_zelle": .bool(true)])
        sync.saved(zelle)
        sync.loaded(Self.base, startedAt: loadStarted)  // the old read lands last
        #expect(sync.shown?.hasZelle == true)
    }

    /// Review 2: Zelle off, tap on then off, both saves fail; Zelle stays off.
    @Test func overlappingFailuresOnOneField() {
        var sync = loaded()
        let on = sync.begin(["has_zelle": .bool(true)])
        let off = sync.begin(["has_zelle": .bool(false)])
        #expect(sync.failed(on) == false)  // the newer save rewrites the same field
        #expect(sync.shown?.hasZelle == false)
        #expect(sync.failed(off) == true)
        #expect(sync.shown?.hasZelle == false)
    }

    @Test func aFailureAfterASuccessShowsTheSavedValue() {
        var sync = loaded()
        let on = sync.begin(["has_zelle": .bool(true)]); sync.saved(on)
        let off = sync.begin(["has_zelle": .bool(false)])
        #expect(sync.failed(off) == true)
        #expect(sync.shown?.hasZelle == true)  // the server has on
    }

    /// Review 3: a refresh reads off mid-save, the save succeeds, its reload shows on, then the refresh lands.
    @Test func aReadBegunDuringAPendingSaveIsDropped() {
        var sync = loaded()
        let zelle = sync.begin(["has_zelle": .bool(true)])
        let refreshStarted = sync.epoch
        sync.saved(zelle)
        sync.loaded(Self.with { $0.hasZelle = true }, startedAt: sync.epoch)
        sync.loaded(Self.base, startedAt: refreshStarted)
        #expect(sync.shown?.hasZelle == true)
        #expect(sync.confirmed?.hasZelle == true)
    }

    /// Review 4: a refresh returns the old name while the save is pending; the save succeeds and its reload fails.
    @Test func aPendingEditSurvivesARefreshThatReturnsMidSave() {
        var sync = loaded()
        let name = sync.begin(["display_name": .string("Tay R")])
        sync.loaded(Self.base, startedAt: sync.epoch)  // starts and returns while the PATCH is pending
        #expect(sync.shown?.displayName == "Tay R")
        sync.saved(name)  // the reload after it fails, so nothing else arrives
        #expect(sync.shown?.displayName == "Tay R")
    }

    /// Review 5: the name save fails while a newer Zelle save is pending. The name failure still matters.
    @Test func anOlderFailureOnAnotherFieldIsReported() {
        var sync = loaded()
        let name = sync.begin(["display_name": .string("Tay R")])
        let zelle = sync.begin(["has_zelle": .bool(true)])
        #expect(sync.failed(name) == true)
        #expect(sync.shown?.displayName == "Taylor Radford")  // only the name goes back
        #expect(sync.shown?.hasZelle == true)
        sync.saved(zelle)
        #expect(sync.shown?.displayName == "Taylor Radford")
        #expect(sync.shown?.hasZelle == true)
    }

    /// Review 6: a save from before sign-out finishes after you've signed back in and started editing.
    @Test func aSaveFromAnEarlierSessionChangesNothing() {
        var sync = loaded()
        let old = sync.begin(["has_zelle": .bool(true)])
        sync.reset()  // sign out, then back in
        sync.loaded(Self.base, startedAt: sync.epoch)
        let name = sync.begin(["display_name": .string("Tay R")])
        #expect(name != old)
        let loadStarted = sync.epoch  // the new session's load is in flight
        #expect(sync.failed(old) == false)  // the old failure neither matters nor touches the new edit
        sync.saved(old)
        #expect(sync.epoch == loadStarted)  // and doesn't drop the new session's load
        #expect(sync.shown?.displayName == "Tay R")
        #expect(sync.failed(name) == true)  // the new save's own failure is still reported
    }

    @Test func applyingSetsColumnsIncludingNull() {
        let p = ProfileSync.applying(["venmo_username": .null, "notify_paid": .bool(false), "display_name": .string("Tay R")],
                                     to: Self.with { $0.venmoUsername = "taylor-r" })
        #expect(p.venmoUsername == nil)
        #expect(p.notifyPaid == false)
        #expect(p.displayName == "Tay R")
    }
}
