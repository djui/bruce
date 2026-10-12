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
