import Foundation

// Platform-neutral helpers shared by Bruce-MacOS and Bruce-iOS (booking rules, formatting, static copy).

/// Booking-rule times derived from class fields (see API.md "Booking rules").
struct BookingRules {
    let start: Date
    let end: Date?
    let checkInFrom: Date
    let lateCheckIn: Date        // start - late_check_in_minutes
    let lateCancel: Date         // start - unbookable_latest (s), i.e. unbookable_latest_time
    let shortNotice: Date        // start - 3 h (confirmed by the user; fixed policy, not in the payload)
    let lastMinute: Date         // start - 1 h (confirmed by the user; fixed policy, not in the payload)

    init?(_ c: BruceAPI.BruceClass) {
        guard let s = c.start else { return nil }
        start = s; end = c.end
        checkInFrom = s.addingTimeInterval(-Double(c.earlyCheckInMinutes ?? 30) * 60)
        lateCheckIn = s.addingTimeInterval(-Double(c.lateCheckInMinutes ?? 5) * 60)
        lateCancel = c.unbookableLatestTime.flatMap(BruceDate.parse)
            ?? s.addingTimeInterval(-Double(c.unbookableLatest ?? 43_200))
        shortNotice = s.addingTimeInterval(-3 * 3600)
        lastMinute = s.addingTimeInterval(-3600)
    }

    static func long(_ d: Date) -> String { BruceDate.format(d, "HH:mm, EEEE, d MMMM") }
}

func classDateLine(_ c: BruceAPI.BruceClass) -> String {
    guard let s = c.start else { return "" }
    let cal = BruceDate.calendar
    let day = cal.isDateInToday(s) ? "Today" : cal.isDateInTomorrow(s) ? "Tomorrow" : BruceDate.format(s, "EEEE")
    return "\(day), \(BruceDate.format(s, "d MMMM")), \(BruceDate.time(s)) - \(BruceDate.time(c.end))"
}

func formatDistance(_ meters: Int) -> String {
    meters < 1000 ? "\(meters / 10 * 10) m" : String(format: "%.1f km", Double(meters) / 1000).replacingOccurrences(of: ".", with: ",")
}

/// "YYYYMMDD-****" style: show the birth-date part only, never the last four digits.
func maskedNationalID(_ s: String?) -> String {
    guard let s, s.count >= 8 else { return "••••••••-****" }
    return String(s.prefix(8)) + "-****"
}

func wellnessQuota(_ tier: String) -> Int {
    switch tier.uppercased() { case "BLACK": return 4; case "EPIC": return 8; default: return 0 }
}

struct PlanInfo {
    let code: String
    let blurb: String
    let annual: Int      // SEK / month, 12-month commitment
    let monthly: Int     // SEK / month, no commitment
    let studios: Int
    let bookings: Int
    let wellness: Int
    /// Fallbacks from the app screenshots (Oct 2026, Stockholm); live prices come from GET /v52/membership/info.
    static let all: [PlanInfo] = [
        PlanInfo(code: "BASE", blurb: "Best for those who want simple, reliable training and a consistent weekly routine.",
                 annual: 599, monthly: 699, studios: 304, bookings: 3, wellness: 0),
        PlanInfo(code: "BLACK", blurb: "Best for those who want more choice, greater flexibility, and the option to mix training with wellness.",
                 annual: 999, monthly: 1099, studios: 375, bookings: 4, wellness: 4),
        PlanInfo(code: "EPIC", blurb: "Best for those who want total freedom, maximum access, and a fully flexible fitness and wellness lifestyle.",
                 annual: 1499, monthly: 1699, studios: 380, bookings: 5, wellness: 8),
    ]
}

func isValidEmail(_ s: String) -> Bool {
    s.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
}

let howItWorksText = [
    "As a Bruce Studios member, you can share invites for a free workout within your membership level. Users with credits but no membership can not send any invites.",
    "Each invite code is unique and can only be used once by the person who is not yet a Bruce Studios member. The free workout can be an instructor-led class or an open training at, for example, a gym.",
    "The free workout can be used no later than 30 days after the code has been registered. Anyone who is not yet a member can be invited to a free workout once every 3 months.",
    "If a friend you invite gets a Bruce Studios membership, your invites will be filled up to 3 new ones.",
    "(A few studios are exceptions to invite codes and can't be booked for free workouts within this program.)",
]

let helpArticles = ["Identification – BankID", "Cancellation rules - Membership", "Studentrabatt", "Pausa medlemskap"]
let helpTopics = ["About us and our memberships", "Annual Membership", "Booking and checking in to classes", "Bruce Studios x STC",
                  "Change, pause or cancel membership", "Invites, discounts and gift cards", "Occupational health",
                  "Payments & receipts", "Trial", "Workout limits"]

let pushInfoText = [
    "By using these settings, you can decide what types of notifications you want to receive. Most of them are sent directly to your phone, but the most important ones are also sent to your email address.",
    "Note: The settings do not affect the notification center on the home screen.",
]
