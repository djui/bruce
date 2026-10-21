import Foundation

// MARK: - Workout export: past visits as workouts (Apple Health on iOS; the mapping is platform neutral)

/// What kind of workout a visit was, guessed from its class categories and title (Bruce has no workout type).
enum WorkoutKind: String, CaseIterable, Codable {
    case strength, functional, hiit, crossTraining, cycling, running, rowing, swimming
    case yoga, pilates, barre, stretching, boxing, martialArts, dance, climbing, mixedCardio
    /// Only for ski races (Races.swift); no class is classified as skiing.
    case skiing

    /// Rough MET value (Compendium of Physical Activities, 2024) for a class of this kind.
    var met: Double {
        switch self {
        case .strength: 5.0
        case .functional: 6.0
        case .hiit: 8.0
        case .crossTraining: 7.5
        case .cycling: 8.5
        case .running: 9.0
        case .rowing: 7.0
        case .swimming: 6.0
        case .yoga: 3.0
        case .pilates: 3.5
        case .barre: 4.0
        case .stretching: 2.5
        case .boxing: 7.8
        case .martialArts: 7.0
        case .dance: 6.0
        case .climbing: 7.0
        case .mixedCardio: 6.5
        case .skiing: 9.0
        }
    }

    /// The workout a race is, by its type (Races.swift).
    static func forRace(_ type: RaceType, sport: RaceSport?) -> WorkoutKind {
        switch type {
        case .running: .running
        case .hyrox: .hiit
        case .obstacle: .crossTraining
        case .triathlon: .mixedCardio
        case .endurance:
            switch sport {
            case .ski: .skiing
            case .bike: .cycling
            case .swim: .swimming
            case nil: .mixedCardio
            }
        }
    }

    /// Ordered keyword rules over the lowercased class title and category titles; the first hit wins.
    private static let rules: [(WorkoutKind, [String])] = [
        (.hiit, ["hyrox", "hiit", "interval", "tabata", "bootcamp", "high intensity"]),
        (.crossTraining, ["crossfit", "cross training", "wod"]),
        (.cycling, ["cycl", "spin", "indoor bike", "rpm"]),
        (.rowing, ["rowing", "erg"]),
        (.running, ["running", "run ", "treadmill", "löp"]),
        (.swimming, ["swim", "aqua"]),
        (.pilates, ["pilates", "reformer"]),
        (.barre, ["barre"]),
        (.yoga, ["yoga", "vinyasa", "ashtanga"]),
        (.stretching, ["stretch", "mobility", "meditation", "breath"]),
        (.boxing, ["box", "kickbox"]),
        (.martialArts, ["martial", "mma", "bjj", "jiu", "karate", "judo", "muay thai"]),
        (.dance, ["dance", "zumba", "sh'bam"]),
        (.climbing, ["climb", "boulder"]),
        (.strength, ["strength", "pump", "kettlebell", "weights", "lift", "gym", "styrka"]),
        (.functional, ["functional", "circuit", "core", "conditioning", "athletic"]),
    ]

    static func classify(title: String?, categories: [String]) -> WorkoutKind {
        // The class title is more specific than its categories ("Hyrox" in "Strength").
        for text in [title ?? ""] + categories {
            let t = text.lowercased()
            if let hit = rules.first(where: { $0.1.contains { t.contains($0) } }) { return hit.0 }
        }
        return .mixedCardio
    }

    /// Categories that are not workouts: these visits are never exported.
    static func isWellness(_ category: String) -> Bool {
        let t = category.lowercased()
        return ["sauna", "spa", "massage", "wellness", "float", "beauty", "relax", "cryo"].contains { t.contains($0) }
    }
}

/// One visit as a workout, ready for Apple Health (or Strava later).
struct ExportWorkout: Identifiable, Hashable {
    let visitId: Int
    let kind: WorkoutKind
    let start: Date
    let end: Date
    let title: String
    let studio: String
    let instructor: String?
    let kcal: Double
    /// A drop-in or opening-hour visit, whose duration is assumed.
    let solo: Bool
    /// A race (Races.swift): outdoors, with a negative `visitId` made from the race key.
    var race = false
    var id: Int { visitId }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
    /// Health's sync identifier: a re-export replaces instead of duplicating.
    var syncId: String { race ? "bruce-race-\(-visitId)" : "bruce-visit-\(visitId)" }
}

enum WorkoutExport {
    /// Body weight when Health has none (kcal = MET × kg × hours).
    static let defaultWeightKg = 75.0
    /// Assumed length of a solo (gym) visit, which only has a check-in time.
    static let soloMinutes = 60

    static func kcal(_ kind: WorkoutKind, minutes: Int, weightKg: Double) -> Double {
        (kind.met * weightKg * Double(minutes) / 60).rounded()
    }

    /// Past visits as workouts, oldest first. Classes use their start and end time; solo visits start at check-in
    /// and last `soloMinutes`. Wellness visits (sauna, spa) and visits that have not ended yet are left out.
    static func workouts(_ visits: [BruceAPI.Visit], weightKg: Double, includeSolo: Bool, now: Date = Date(),
                         categoryTitle: (Int) -> String?, studioName: (BruceAPI.Visit) -> String,
                         mainCategory: (Int) -> Int?) -> [ExportWorkout] {
        visits.compactMap { v -> ExportWorkout? in
            var cats = v.categoryIds.compactMap(categoryTitle)
            let start: Date, end: Date
            if v.isSolo {
                guard includeSolo, let s = v.checkedIn ?? v.classStart else { return nil }
                if let ref = v.studioRef, let main = mainCategory(ref), let t = categoryTitle(main) { cats.append(t) }
                start = s
                end = s.addingTimeInterval(TimeInterval(soloMinutes * 60))
            } else {
                guard let s = v.classStart, let e = v.classEnd, e > s, e.timeIntervalSince(s) <= 4 * 3600 else { return nil }
                start = s
                end = e
            }
            guard end <= now, !cats.contains(where: WorkoutKind.isWellness) else { return nil }
            let kind: WorkoutKind = v.isSolo && cats.isEmpty ? .strength
                : WorkoutKind.classify(title: v.isSolo ? nil : v.visitClass?.title, categories: cats)
            let minutes = Int(end.timeIntervalSince(start) / 60)
            return ExportWorkout(visitId: v.id, kind: kind, start: start, end: end,
                                 title: v.isSolo ? "Solo training" : (v.visitClass?.title ?? "Class"),
                                 studio: studioName(v), instructor: v.instructor,
                                 kcal: kcal(kind, minutes: minutes, weightKg: weightKg), solo: v.isSolo)
        }
        .sorted { $0.start < $1.start }
    }

    /// The member's races with a result as workouts (Apple Health): from the start wave (else 09:00) on their race
    /// day, as long as the finish time; outdoors, kcal by the race's kind. A DNF or a zero time is left out. The id
    /// is a stable hash of the race key, negative so it never meets a visit id.
    static func raceWorkouts(_ entries: [MyRaceEntry], weightKg: Double, now: Date = Date()) -> [ExportWorkout] {
        entries.compactMap { e -> ExportWorkout? in
            guard let res = e.mine.result, !res.dnf, res.seconds > 0, e.isPast(now: now) else { return nil }
            guard let start = RaceClock.date(e.day, e.mine.wave) ?? RaceClock.date(e.day, "09:00") else { return nil }
            let end = start.addingTimeInterval(TimeInterval(res.seconds))
            guard end <= now else { return nil }
            let kind = WorkoutKind.forRace(e.race.type, sport: e.race.sport)
            let minutes = res.seconds / 60
            return ExportWorkout(visitId: -raceId(e.mine.key), kind: kind, start: start, end: end,
                                 title: [e.race.name, e.startText].compactMap { $0 }.joined(separator: " · "),
                                 studio: e.race.placeLine.replacingOccurrences(of: " | ", with: ", "), instructor: nil,
                                 kcal: kcal(kind, minutes: minutes, weightKg: weightKg), solo: false, race: true)
        }
        .sorted { $0.start < $1.start }
    }
    /// A stable positive number for a race key (FNV-1a, 31 bits), the same on every run and device.
    static func raceId(_ key: String) -> Int {
        var h: UInt32 = 2_166_136_261
        for b in key.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return Int(h & 0x7FFF_FFFF) | 1
    }
}

extension AppModel {
    func exportWorkouts(weightKg: Double, includeSolo: Bool) -> [ExportWorkout] {
        WorkoutExport.workouts(visitHistory ?? [], weightKg: weightKg, includeSolo: includeSolo,
                               categoryTitle: { id in self.categories.first { $0.id == id }?.title },
                               studioName: { self.studioName(for: $0) },
                               mainCategory: { self.mainCategory(ofStudio: $0) })
        + WorkoutExport.raceWorkouts(myRaceEntries, weightKg: weightKg)
    }
}
