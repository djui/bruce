import Foundation
import UserNotifications

/// Opt-in local reminder one hour before cancelling a booked class starts to cost a strike (Settings › "Last free
/// cancel reminder"). It only reminds: nothing is ever cancelled or rebooked by the app. Off by default so it does
/// not double up with Bruce's own `booking_reminder` push to the official app.
enum CancelReminders {
    static let category = "CANCEL_REMINDER"
    static let idPrefix = "cancel-reminder-"
    /// Minutes before the free-cancel deadline.
    static let lead = 60
    private static let key = "cancelReminders"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Replaces the pending reminders with one per upcoming booking whose deadline is still more than `lead` away.
    /// Call after the bookings were (re)loaded; with the setting off it only clears what was scheduled before.
    static func sync(bookings: [BruceAPI.Booking], studioName: (Int) -> String, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard enabled else { return }
        for b in bookings.prefix(30) {
            guard !b.isCheckedIn, let c = b.class, let r = BookingRules(c) else { continue }
            let fire = r.lateCancel.addingTimeInterval(-Double(lead) * 60)
            guard fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Last free cancel in \(lead == 60 ? "1 h" : "\(lead) min")"
            content.body = "\(c.title), \(BruceDate.format(r.start, "EEE HH:mm")) at \(studioName(c.studioId)). From \(BruceDate.time(r.lateCancel)) a cancel costs 1 strike."
            content.sound = .default
            content.categoryIdentifier = category
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["classId": c.id]
            let comps = BruceDate.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(idPrefix)\(c.id)", content: content, trigger: trigger))
        }
    }
}
