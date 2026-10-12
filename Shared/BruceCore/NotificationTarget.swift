import Foundation

// Where a notification leads. `GET /v52/notification` items carry `meta{class_id, studio_id, photo, user_photo}`
// [42, 159, 178]: `class_id` is set on STANDBY_AVAILABLE, BOOKING_*, CLASS_MESSAGE, CHECK_IN_REMINDER and
// CLASS_INVITE; `studio_id` is often null even then. There is no booking id, standby id or link.

extension BruceAPI.BruceNotification {
    enum Kind { case freeSpot, cancellation, other }
    /// `type`: STANDBY_AVAILABLE ("Free spot"), BOOKING_CANCELLED, BOOKING_REMINDER, CLASS_MESSAGE,
    /// CHECK_IN_REMINDER, CLASS_INVITE, USER_STRIKE, USER_BLOCK, USER_STRIKE_UNBLOCKED, PAUSE_ENDING.
    var kind: Kind {
        switch type?.uppercased() {
        case "STANDBY_AVAILABLE": return .freeSpot
        case "BOOKING_CANCELLED": return .cancellation
        default: return .other
        }
    }

    /// What a notification is about, shown as the small badge on its icon.
    enum Subject { case classSession, studio, bruce }
    var subject: Subject {
        if meta?.classId != nil { return .classSession }
        if meta?.studioId != nil { return .studio }
        return .bruce
    }

    /// How the news reads at a glance; the apps tint the subject badge with it.
    enum Tone { case good, bad, neutral }

    /// The glyph for what happened (SF Symbol), drawn on the icon like the official app's bell, speech bubble and
    /// alarm clock, plus its tone and a VoiceOver label.
    struct Look { let symbol: String; let tone: Tone; let label: String }
    var look: Look {
        switch type?.uppercased() {
        case "STANDBY_AVAILABLE": return Look(symbol: "bell", tone: .good, label: "Free spot")
        case "BOOKING_REMINDER": return Look(symbol: "alarm", tone: .neutral, label: "Booking reminder")
        case "CHECK_IN_REMINDER": return Look(symbol: "checkmark.circle", tone: .neutral, label: "Time to check in")
        case "BOOKING_CANCELLED": return Look(symbol: "calendar.badge.minus", tone: .bad, label: "Booking cancelled")
        case "CLASS_MESSAGE": return Look(symbol: "text.bubble", tone: .neutral, label: "Message from the studio")
        case "CLASS_INVITE": return Look(symbol: "person.badge.plus", tone: .good, label: "Class invite")
        case "USER_STRIKE":
            // One type for late cancellations and late arrivals; only the title tells them apart.
            let late = (title ?? "").lowercased().contains("arrival")
            return Look(symbol: late ? "clock.badge.exclamationmark" : "exclamationmark.triangle", tone: .bad,
                        label: late ? "Late arrival" : "Late cancellation")
        case "USER_BLOCK": return Look(symbol: "nosign", tone: .bad, label: "Blocked from booking")
        case "USER_STRIKE_UNBLOCKED": return Look(symbol: "lock.open", tone: .good, label: "Unblocked")
        case "PAUSE_ENDING": return Look(symbol: "pause.circle", tone: .neutral, label: "Pause ending")
        default:
            // Untyped items (older payloads, demo data) fall back to the title.
            let t = (title ?? "").lowercased()
            if t.contains("cancel") { return Look(symbol: "calendar.badge.minus", tone: .bad, label: "Booking cancelled") }
            if t.contains("reminder") { return Look(symbol: "alarm", tone: .neutral, label: "Reminder") }
            if t.contains("check in") { return Look(symbol: "checkmark.circle", tone: .neutral, label: "Time to check in") }
            return Look(symbol: "bell", tone: .neutral, label: "Notice")
        }
    }

    /// VoiceOver label for the icon, e.g. "Free spot, about a class".
    var iconAccessibilityLabel: String {
        let about = switch subject { case .classSession: "about a class"; case .studio: "about a studio"; case .bruce: "from Bruce" }
        return "\(look.label), \(about)"
    }
}

extension AppModel {
    /// Opens what a notification is about: its class, else its studio (by id, or by the studio named at the end of
    /// "…, CrossFit Södermalm"), else the strikes or membership screen for account notices.
    func openNotification(_ n: BruceAPI.BruceNotification) {
        if let id = n.meta?.classId { dismissSheets(); push(.classDetail(id)); return }
        if let id = n.meta?.studioId ?? studioNamed(in: n.message ?? "")?.id { dismissSheets(); push(.studio(id)); return }
        switch n.type?.uppercased() {
        case "USER_STRIKE", "USER_BLOCK", "USER_STRIKE_UNBLOCKED": present(.strikes)
        case "PAUSE_ENDING": present(.membership)
        default: break
        }
    }

    private func studioNamed(in message: String) -> BruceAPI.Studio? {
        guard let tail = message.split(separator: ",").last?.trimmingCharacters(in: .whitespaces).lowercased(),
              !tail.isEmpty else { return nil }
        return studios.first { $0.name.lowercased() == tail }
    }
}
