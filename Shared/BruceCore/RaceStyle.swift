import SwiftUI

// Colours and symbols for race cards on iPhone and Mac (Races.swift): the app's own gradients per race type, never a
// race's or organiser's colours.

/// Card colours per race type: the app's own gradients.
enum RaceStyle {
    static func colors(_ t: RaceType) -> [Color] {
        switch t {
        case .running: [Color(red: 0.10, green: 0.21, blue: 0.40), Color(red: 0.24, green: 0.49, blue: 0.80)]
        case .hyrox: [Color(red: 0.27, green: 0.33, blue: 0.10), Color(red: 0.56, green: 0.66, blue: 0.21)]
        case .obstacle: [Color(red: 0.35, green: 0.20, blue: 0.09), Color(red: 0.78, green: 0.46, blue: 0.20)]
        case .endurance: [Color(red: 0.16, green: 0.18, blue: 0.43), Color(red: 0.41, green: 0.47, blue: 0.82)]
        case .triathlon: [Color(red: 0.06, green: 0.24, blue: 0.25), Color(red: 0.15, green: 0.60, blue: 0.55)]
        }
    }
    static func gradient(_ t: RaceType) -> LinearGradient {
        LinearGradient(colors: colors(t), startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Dot in the type chips.
    static func dot(_ t: RaceType) -> Color { colors(t)[1] }
    static func statusSymbol(_ s: RaceStatus) -> String {
        switch s {
        case .open: "checkmark.circle"
        case .opensSoon: "calendar.badge.clock"
        case .soldOut: "xmark.circle"
        case .lottery: "shuffle"
        case .checkSite: "questionmark.circle"
        }
    }
}
