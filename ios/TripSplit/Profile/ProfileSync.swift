import Foundation
import Supabase

/// Your profile on screen versus what the server has confirmed, while autosaves are in flight (PR #35 review).
/// - Each save gets an id; only the newest one (`latestSave`) can reset the screen or ask to retry.
/// - `epoch` moves on whenever a save starts or finishes. A load applies only if the epoch hasn't moved while it
///   was loading, so a read that began before a write settled can't overwrite what came after it.
/// - A successful save moves the confirmed profile forward; the newest save failing resets the screen to it, so an
///   older failure can't overwrite a newer choice.
/// Changes are shown before they're saved (set `shown`, then `begin`).
struct ProfileSync {
    var shown: Profile?
    private(set) var confirmed: Profile?
    private(set) var latestSave = 0
    private(set) var epoch = 0

    mutating func begin() -> Int {
        latestSave += 1; epoch += 1
        return latestSave
    }

    mutating func saved(_ fields: [String: AnyJSON]) {
        epoch += 1
        confirmed = confirmed.map { Self.applying(fields, to: $0) }
    }

    mutating func failed(_ save: Int) {
        epoch += 1
        if save == latestSave, let confirmed { shown = confirmed }
    }

    /// A load that started at `startedAt` (the epoch then) came back.
    mutating func loaded(_ profile: Profile, startedAt: Int) {
        guard startedAt == epoch else { return }
        confirmed = profile
        shown = profile
    }

    /// `profile` with `fields` (`profiles` columns) set, as the database has it after the save.
    static func applying(_ fields: [String: AnyJSON], to profile: Profile) -> Profile {
        guard let object = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))) as? [String: Any],
              let changes = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(fields))) as? [String: Any],
              case let merged = object.merging(changes, uniquingKeysWith: { $1 }),
              let data = try? JSONSerialization.data(withJSONObject: merged),
              let result = try? JSONDecoder().decode(Profile.self, from: data)
        else { return profile }
        return result
    }
}
