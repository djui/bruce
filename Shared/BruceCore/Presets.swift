import Foundation

/// Internal door QR data ("stc://open-door?major=<gym>&minor=<door>") for gyms whose studio
/// payload carries no door ids (`integration_door_config` is empty). Not user-editable.
enum KnownDoors {
    struct Door: Hashable { let name: String; let major: String; let doorId: String }

    static let byStudio: [Int: Door] = [
        1724: Door(name: "STC Rosenlundsparken", major: "13994", doorId: "118661"),
        1764: Door(name: "STC Södermalm Timmermansgatan", major: "13816", doorId: "118551"),
    ]
}
