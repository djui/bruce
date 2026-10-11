import CoreLocation
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// When-in-use location for distances, Home "Nearby gyms" and the check-in suggestion (iOS and macOS).
///
/// * The `CLLocationManager` is a stored property of this object, which the app keeps as a `@StateObject`
///   (strongly retained for the app's lifetime); delegate callbacks hop to the main actor.
/// * Permission is asked when Home first appears after login (`requestIfNeeded()`), or from
///   "Use my location" / Settings. Without permission everything falls back to the city centre.
/// * While the app is active and allowed, `startUpdatingLocation` delivers fixes (100 m filter); each fix is
///   pushed into `AppModel.userLocation`, which recomputes distances and reloads Home on a significant move.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    @Published private(set) var lastError: String?
    private let manager = CLLocationManager()
    weak var model: AppModel?

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
    }

    var authorized: Bool {
        #if os(iOS)
        return status == .authorizedWhenInUse || status == .authorizedAlways
        #else
        return status == .authorizedAlways || status == .authorized
        #endif
    }
    var undetermined: Bool { status == .notDetermined }
    var denied: Bool { status == .denied || status == .restricted }

    /// Ask once (system prompt shows the usage string); start updates if already allowed.
    func requestIfNeeded() {
        if undetermined { manager.requestWhenInUseAuthorization() } else if authorized { start() }
    }

    /// Explicit user action: ask, refresh, or open the system settings when denied.
    func request() {
        if denied { openSettings() } else { requestIfNeeded() }
    }

    func start() { if authorized { manager.startUpdatingLocation() } }
    func stop() { manager.stopUpdatingLocation() }

    func openSettings() {
        #if canImport(UIKit)
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
        #else
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") { NSWorkspace.shared.open(u) }
        #endif
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if self.authorized { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.lastError = nil
            guard let m = self.model else { return }
            let delta = m.userLocation.map { $0.distance(from: loc) } ?? .infinity
            // Only publish real moves: every assignment re-sorts distance-ordered lists.
            guard delta > 50 else { return }
            let moved = delta > 250
            m.userLocation = loc
            #if DEBUG
            print(String(format: "[location] %.5f,%.5f ±%.0fm", loc.coordinate.latitude, loc.coordinate.longitude, loc.horizontalAccuracy))
            #endif
            // Home "Nearby gyms" is computed server-side from the coordinates: reload on first / significant fix.
            if moved && m.isLoggedIn && !AppModel.demo { await m.loadHome() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in self.lastError = msg }
    }
}
