import Foundation

/// Internal door QR data ("stc://open-door?major=<gym>&minor=<door>") for gyms whose studio
/// payload carries no door ids (`integration_door_config` is empty). Not user-editable.
enum KnownDoors {
    struct Door: Hashable { let name: String; let major: String; let doorId: String }

    static let byStudio: [Int: Door] = [
        1724: Door(name: "STC Rosenlundsparken", major: "13994", doorId: "118661"),
        1764: Door(name: "STC Södermalm Timmermansgatan", major: "13816", doorId: "118551"),
    ]

    /// Built-in door, else one learned from a door QR the user scanned there (`LearnedDoors`).
    static func door(for studioId: Int) -> Door? { byStudio[studioId] ?? LearnedDoors.door(for: studioId) }
}

/// Doors remembered from the user's own successful door-QR check-ins, so a later check-in from the list
/// (without scanning) can send the same `meta` the original sends [c1:163]. Local only (UserDefaults);
/// door ids are printed on the door and not secret. Off in demo mode.
enum LearnedDoors {
    static let key = "learnedDoors"

    static func door(for studioId: Int) -> KnownDoors.Door? {
        guard !AppModel.demo, let all = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]],
              let v = all[String(studioId)], v.count == 2 else { return nil }
        return KnownDoors.Door(name: "", major: v[0], doorId: v[1])
    }

    static func remember(_ door: KnownDoors.Door, studioId: Int) {
        guard !AppModel.demo, studioId > 0, KnownDoors.byStudio[studioId] == nil else { return }
        var all = (UserDefaults.standard.dictionary(forKey: key) as? [String: [String]]) ?? [:]
        all[String(studioId)] = [door.major, door.doorId]
        UserDefaults.standard.set(all, forKey: key)
    }
}
