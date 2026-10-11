import Foundation
import Supabase

/// Your profile while autosaves are in flight (PR #35 review). What's shown is never stored: it's the confirmed
/// profile (what the server last said) with every pending edit laid on top, in order. So:
/// - an edit shows the moment it's made, and no load can hide it while its save is pending;
/// - a successful save moves its fields into the confirmed profile;
/// - a failed save drops out of the overlay, so only its own fields go back. It still matters (Retry) unless
///   newer pending saves rewrite every field it changed;
/// - `epoch` moves whenever a save settles. A load applies only if none settled while it was loading, so a read
///   from before a write can't replace what came after it.
struct ProfileSync {
    private(set) var confirmed: Profile?
    private var pending: [(id: Int, fields: [String: AnyJSON])] = []
    private var lastId = 0
    private(set) var epoch = 0

    // ponytail: re-encodes the profile once per pending save on each read; pending is almost always empty.
    var shown: Profile? { pending.reduce(confirmed) { profile, save in profile.map { Self.applying(save.fields, to: $0) } } }
    var isSettled: Bool { pending.isEmpty }

    /// Signed out: forget the profile and every pending edit, but keep counting save ids, so a save from before
    /// can never be mistaken for one made after (PR #35 review). Its completion then finds nothing and changes nothing.
    mutating func reset() {
        confirmed = nil
        pending = []
        epoch += 1
    }

    mutating func begin(_ fields: [String: AnyJSON]) -> Int {
        lastId += 1
        pending.append((lastId, fields))
        return lastId
    }

    mutating func saved(_ id: Int) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }  // from an earlier session
        epoch += 1
        let fields = pending.remove(at: i).fields
        confirmed = confirmed.map { Self.applying(fields, to: $0) }
    }

    /// Whether the failure still matters: false when newer pending saves rewrite every field it changed.
    mutating func failed(_ id: Int) -> Bool {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return false }  // from an earlier session
        epoch += 1
        let fields = Set(pending.remove(at: i).fields.keys)
        let rewritten = Set(pending.filter { $0.id > id }.flatMap(\.fields.keys))
        return !fields.isSubset(of: rewritten)
    }

    /// A load that started at `startedAt` (the epoch then) came back.
    mutating func loaded(_ profile: Profile, startedAt: Int) {
        guard startedAt == epoch else { return }
        confirmed = profile
    }

    /// `profile` with `fields` (`profiles` columns) set, as the database has it after the save.
    static func applying(_ fields: [String: AnyJSON], to profile: Profile) -> Profile {
        guard let object = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))) as? [String: Any],
              let changes = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(fields))) as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: object.merging(changes, uniquingKeysWith: { $1 })),
              let result = try? JSONDecoder().decode(Profile.self, from: data)
        else { return profile }
        return result
    }
}
