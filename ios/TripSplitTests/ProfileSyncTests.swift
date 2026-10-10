import Foundation
import Supabase
import Testing
@testable import TripSplit

/// Autosave consistency on Profile (PR #35 review): the reviewer's two scenarios, plus a success then a failure.
struct ProfileSyncTests {
    static let base = Profile(id: UUID(), displayName: "Taylor Radford", venmoUsername: nil, hasZelle: false, hasAppleCash: false)

    func loadedSync() -> ProfileSync {
        var sync = ProfileSync()
        sync.loaded(Self.base, startedAt: sync.generation)
        return sync
    }

    @Test func aLoadOvertakenByANewerSaveIsDropped() {
        var sync = loadedSync()
        let loadStarted = sync.generation
        sync.shown?.hasZelle = true; _ = sync.begin()  // you tap Zelle while an older load is in flight
        var stale = Self.base; stale.hasZelle = false
        sync.loaded(stale, startedAt: loadStarted)
        #expect(sync.shown?.hasZelle == true)
    }

    @Test func overlappingFailuresRestoreTheConfirmedValue() {
        var sync = loadedSync()  // Zelle off on the server
        sync.shown?.hasZelle = true; let on = sync.begin()
        sync.shown?.hasZelle = false; let off = sync.begin()
        sync.failed(on)  // overtaken: changes nothing
        #expect(sync.shown?.hasZelle == false)
        sync.failed(off)
        #expect(sync.shown?.hasZelle == false)
        #expect(sync.confirmed?.hasZelle == false)
    }

    @Test func aFailureAfterASuccessRestoresTheSavedValue() {
        var sync = loadedSync()
        sync.shown?.hasZelle = true; _ = sync.begin()
        sync.saved(["has_zelle": .bool(true)])
        sync.shown?.hasZelle = false; let off = sync.begin()
        sync.failed(off)
        #expect(sync.shown?.hasZelle == true)  // the server has on
    }

    @Test func applyingSetsColumnsIncludingNull() {
        var withVenmo = Self.base; withVenmo.venmoUsername = "taylor-r"
        let p = ProfileSync.applying(["venmo_username": .null, "notify_paid": .bool(false), "display_name": .string("Tay R")], to: withVenmo)
        #expect(p.venmoUsername == nil)
        #expect(p.notifyPaid == false)
        #expect(p.displayName == "Tay R")
    }
}
