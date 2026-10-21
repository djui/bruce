import Foundation
import HealthKit
import Observation

/// Writes past visits to Apple Health as workouts (type, start, end, estimated active energy). Off until switched
/// on in Settings; then every sync exports the visits that ended since, including the whole history the first time.
/// Each workout carries `HKMetadataKeySyncIdentifier` "bruce-visit-<id>", so a re-export replaces instead of
/// duplicating. Visits that overlap a workout from another source (an Apple Watch recording) are skipped.
@MainActor @Observable
final class HealthSync {
    static let shared = HealthSync()

    var enabled = UserDefaults.standard.bool(forKey: "healthSync.enabled")
    var includeSolo = UserDefaults.standard.object(forKey: "healthSync.includeSolo") as? Bool ?? true
    var syncing = false
    var lastResult: String?
    private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: "healthSync.lastSync") as? Date

    @ObservationIgnored private var exported = Set((UserDefaults.standard.array(forKey: "healthSync.exported") as? [Int]) ?? [])
    @ObservationIgnored private let store = HKHealthStore()

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private let energy = HKQuantityType(.activeEnergyBurned)
    private let bodyMass = HKQuantityType(.bodyMass)

    /// Switches syncing on (asking for Health access) or off. Workouts already written stay in Health.
    func setEnabled(_ on: Bool, model: AppModel) async {
        guard on else { enabled = false; persist(); return }
        guard available else { lastResult = "Apple Health is not available on this device"; return }
        do {
            try await store.requestAuthorization(toShare: [.workoutType(), energy], read: [.workoutType(), bodyMass])
        } catch {
            lastResult = "Health access failed: \(error.localizedDescription)"
            return
        }
        guard store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
            lastResult = "Allow Brüce to write workouts in Settings › Health › Data Access & Devices"
            return
        }
        enabled = true
        persist()
        await sync(model: model)
    }

    func setIncludeSolo(_ on: Bool, model: AppModel) async {
        includeSolo = on
        persist()
        if on { await sync(model: model) }
    }

    /// Cheap when nothing is new: one (cached) visit history read and no Health writes.
    func sync(model: AppModel, force: Bool = false) async {
        guard enabled, available, !syncing, !AppModel.demo, model.tokenUsable else { return }
        guard store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
            lastResult = "Health access was turned off in Settings › Health"
            return
        }
        syncing = true
        defer { syncing = false }
        if model.categories.isEmpty { await model.loadCategoriesIfNeeded() }
        await model.fetchVisitHistory(force: force)
        let weight = await latestWeightKg() ?? WorkoutExport.defaultWeightKg
        let pending = model.exportWorkouts(weightKg: weight, includeSolo: includeSolo).filter { !exported.contains($0.visitId) }
        var added = 0, skipped = 0, failed = 0
        for w in pending {
            if await overlapsOtherWorkout(w) { exported.insert(w.visitId); skipped += 1; continue }
            do {
                try await save(w)
                exported.insert(w.visitId)
                added += 1
            } catch {
                failed += 1
            }
        }
        lastSync = Date()
        persist()
        var parts = ["\(added) workout\(added == 1 ? "" : "s") added"]
        if skipped > 0 { parts.append("\(skipped) already recorded by another app") }
        if failed > 0 { parts.append("\(failed) failed") }
        lastResult = pending.isEmpty ? "Up to date" : parts.joined(separator: ", ")
    }

    private func save(_ w: ExportWorkout) async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = w.kind.healthKitType
        config.locationType = w.race ? .outdoor : .indoor
        if w.kind == .swimming { config.swimmingLocationType = w.race ? .openWater : .pool }
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: w.start)
        let kcal = HKQuantity(unit: .kilocalorie(), doubleValue: w.kcal)
        try await builder.addSamples([HKCumulativeQuantitySample(type: energy, quantity: kcal, start: w.start, end: w.end)])
        var meta: [String: Any] = [
            HKMetadataKeySyncIdentifier: w.syncId,
            HKMetadataKeySyncVersion: 1,
            HKMetadataKeyIndoorWorkout: !w.race,
            HKMetadataKeyWorkoutBrandName: w.race ? w.title : (w.studio.isEmpty ? "Bruce" : w.studio),
            "BruceTitle": w.title,
        ]
        if let i = w.instructor { meta["BruceInstructor"] = i }
        try await builder.addMetadata(meta)
        try await builder.endCollection(at: w.end)
        _ = try await builder.finishWorkout()
    }

    /// A workout another app (Apple Watch, Strava, ...) recorded over at least half of this visit.
    private func overlapsOtherWorkout(_ w: ExportWorkout) async -> Bool {
        let predicate = HKQuery.predicateForSamples(withStart: w.start.addingTimeInterval(-1800), end: w.end.addingTimeInterval(1800))
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [], limit: 20)
        guard let found = try? await descriptor.result(for: store) else { return false }
        let me = Bundle.main.bundleIdentifier
        return found.contains { o in
            guard o.sourceRevision.source.bundleIdentifier != me else { return false }
            let overlap = min(o.endDate, w.end).timeIntervalSince(max(o.startDate, w.start))
            return overlap >= w.end.timeIntervalSince(w.start) / 2
        }
    }

    private func latestWeightKg() async -> Double? {
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: bodyMass)],
                                                 sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        return try? await descriptor.result(for: store).first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(enabled, forKey: "healthSync.enabled")
        d.set(includeSolo, forKey: "healthSync.includeSolo")
        d.set(Array(exported), forKey: "healthSync.exported")
        d.set(lastSync, forKey: "healthSync.lastSync")
    }
}

extension WorkoutKind {
    var healthKitType: HKWorkoutActivityType {
        switch self {
        case .strength: .traditionalStrengthTraining
        case .functional: .functionalStrengthTraining
        case .hiit: .highIntensityIntervalTraining
        case .crossTraining: .crossTraining
        case .cycling: .cycling
        case .running: .running
        case .rowing: .rowing
        case .swimming: .swimming
        case .yoga: .yoga
        case .pilates: .pilates
        case .barre: .barre
        case .stretching: .flexibility
        case .boxing: .boxing
        case .martialArts: .martialArts
        case .dance: .cardioDance
        case .climbing: .climbing
        case .mixedCardio: .mixedCardio
        case .skiing: .crossCountrySkiing
        }
    }
}
