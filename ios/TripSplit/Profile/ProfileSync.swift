import Foundation
import Supabase

/// Your profile on screen versus what the server has confirmed, while autosaves are in flight (PR #35 review).
/// Every save gets the next generation. Only the newest generation decides what's shown:
/// - a load applies only if no save started while it was loading;
/// - a successful save moves the confirmed profile forward;
/// - a failed save resets the screen to the confirmed profile, and only when it's the newest save, so an older
///   failure can't overwrite a newer choice.
struct ProfileSync {
    var shown: Profile?
    private(set) var confirmed: Profile?
    private(set) var generation = 0

    /// A save is starting (after its change is already shown).
    mutating func begin() -> Int { generation += 1; return generation }

    mutating func saved(_ fields: [String: AnyJSON]) {
        confirmed = confirmed.map { Self.applying(fields, to: $0) }
    }

    mutating func failed(_ save: Int) {
        if save == generation, let confirmed { shown = confirmed }
    }

    /// A load that started at generation `startedAt` came back.
    mutating func loaded(_ profile: Profile, startedAt: Int) {
        guard startedAt == generation else { return }
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
