import Foundation

// User-facing help and policy texts for both apps, written for this project in our own words.
// Wherever the API returns the underlying facts (prices, pause allowance, unlocks, invite codes, plan
// limits), the text is built from those values. `Policy` holds the few rules the API does not expose.

/// Membership rules that no observed endpoint returns. Used only as wording, never to enforce anything.
enum Policy {
    /// Strikes that lead to a booking block (`user_block/info` only reports `strike_count`).
    static let strikesToBlock = 3
    /// Length of a booking block in days (the API gives `block_end_date` only while a block is active).
    static let blockDays = 14
    /// One strike expires this many days after it was given (help centre, June 2026; the same in SE, NO and DK).
    static let strikeExpiryDays = 30
    /// Strikes for a no-show (booked, never checked in), the same as a cancellation under 1 hour before.
    static let noShowStrikes = 3
    /// Fallback yearly pause allowance when `membership/user_info` has no `pause_days_total`/`total_pause_periods`.
    static let pauseDays = 60
    static let pausePeriods = 2
}

enum Copy {
    // MARK: Welcome

    static let tagline = "BOOK. TRAIN. CHECK IN."

    // MARK: Strikes

    private static func day(_ iso: String?) -> String? {
        iso.flatMap(BruceDate.parse).map { BruceDate.format($0, "d MMMM") }
    }

    /// Footer under Book / Cancel. `unlockPrice` is the city's `user_strike_block_un_lock_price` in kr.
    static func strikeFooter(unlockPrice: Int?) -> String {
        var s = "Reaching \(Policy.strikesToBlock) strikes pauses class booking for \(Policy.blockDays) days; one strike expires every \(Policy.strikeExpiryDays) days."
        if let p = unlockPrice { s += " You can lift a block early for \(p) kr." }
        return s
    }

    /// What cancelling costs right now, for the Cancel sheet and My classes ("Cancelling now costs 2 strikes").
    static func cancelCost(strikes: Int) -> String {
        strikes <= 0 ? "Cancelling now is free." : "Cancelling now costs \(strikes) strike\(strikes == 1 ? "" : "s")."
    }

    /// Summary on the Strikes screen, from `user_block/info` and the city's unblock price.
    static func strikeSummary(_ b: BruceAPI.BlockInfo?, unlockPrice: Int?) -> String {
        var parts: [String] = []
        if b?.blocked == true {
            parts.append(day(b?.blockEndDate).map { "Class booking is blocked until \($0)." } ?? "Class booking is currently blocked.")
        } else {
            parts.append("At \(Policy.strikesToBlock) strikes, class booking pauses for \(Policy.blockDays) days.")
        }
        let left = b?.freeUnlocksRemaining ?? 0
        if let total = b?.totalFreeUnlocks {
            parts.append("Free unlocks left: \(left) of \(total).")
        } else {
            parts.append("Free unlocks left: \(left).")
        }
        if let p = unlockPrice { parts.append("After that, lifting a block costs \(p) kr.") }
        parts.append("One strike expires every \(Policy.strikeExpiryDays) days.")
        return parts.joined(separator: " ")
    }

    // Bruce's rules since June 2026 (help centre: cancellation rules, booking block), the same in Sweden, Norway and
    // Denmark; only the unlock price differs and comes from the city. A no-show now costs as much as a block.
    static let strikeFree = ["Cancelling 12 hours or more before the class starts.",
                             "Checking in within the studio's check-in window."]
    static let strikeOne: [(String?, String)] = [("Late cancellation", ": 3 to 12 hours before start, 1 strike"),
                                                ("Late check-in", ": after the check-in window, 1 strike")]
    static let strikeTwo: [(String?, String)] = [("Short-notice cancellation", ": 1 to 3 hours before start, 2 strikes")]
    static let strikeThree: [(String?, String)] = [("Last-minute cancellation", ": under 1 hour before start, 3 strikes"),
                                                  ("No-show", ": booked but never checked in, 3 strikes")]
    static let noShow = "Booked, but never checked in."

    // MARK: Calendar

    /// Under "Add to Calendar": a one-off event is a copy, the feed follows changes.
    static let calendarOneOff = "A single event won't follow changes to the class. Subscribe keeps every booking in sync."
    static let calendarAlert = "Alert \(CalendarEvent.alertMinutes / 60) h before · editable"
    static let calendarSubscribe = "Subscribe to all bookings"
    static let calendarSubscribeHint = "Opens Calendar with Bruce's feed of your bookings. The link is personal; copy it only into a calendar app."
    static let calendarAdded = "Added to Calendar"
    static let calendarEventFooter = "Added with Brüce, an unofficial Bruce Studios client. This event is a copy and doesn't follow changes to the class; the calendar subscription in Settings stays in sync."

    /// Settings toggle for CancelReminders.swift.
    static let cancelReminder = "A notification 1 h before cancelling a booked class starts to cost a strike. Nothing is cancelled for you."

    // MARK: Check-in

    /// Badge on a My classes row the user already checked in to.
    static let checkedIn = "Checked in"


    // MARK: Rating a class (POST /v52/review)

    static let reviewTitle = "Rate the class"
    static let reviewCommentHint = "Comment (optional)"
    static let reviewAnonymous = "Hide my name and photo"
    static let reviewPrivacy = "Ratings with a comment show your first name and photo on the studio page unless you hide them."
    static let reviewSkip = "Skipped. You can rate this class later from My classes."
    static let reviewLowNeedsComment = "Tell the studio what could be better: a comment is needed for ratings of 1 or 2."

    // MARK: Visit limits

    /// Shown under "Buy for SEK n" when the plan's monthly visits at a studio are used up.
    static let visitLimitReached = "You've reached this month's visit limit at this studio for your plan."
    /// The single-visit purchase call has not been captured, so buying is left to the official app.
    static let dropInUnavailable = "Buying a single visit isn't available in this unofficial client. Use the Bruce app to buy it."
    /// "1 visit left in October • Resets November 1".
    static func visitsLeft(_ left: Int, month: String, reset: String) -> String {
        "\(left) visit\(left == 1 ? "" : "s") left in \(month) • Resets \(reset)"
    }

    // MARK: Pause

    /// From `membership/user_info` (`pause_days_total`, `total_pause_periods`).
    static func pauseRules(_ ms: BruceAPI.MembershipInfo?) -> String {
        let days = ms?.pauseDaysTotal ?? Policy.pauseDays
        let periods = ms?.totalPausePeriods ?? Policy.pausePeriods
        return "Each calendar year you get \(days) pause days to split across up to \(periods) separate pauses, however you like."
    }

    // MARK: Membership

    static let withdrawal = "Possible during the first 14 days after purchase."

    /// From `membership/user_info` (`prolong_commitment`, `committed_until`).
    static func renewal(_ ms: BruceAPI.MembershipInfo?) -> String {
        let until = day(ms?.committedUntil)
        if ms?.prolongCommitment == false {
            return until.map { "Your commitment ends on \($0) and is not renewed." } ?? "Your commitment is not renewed."
        }
        return until.map { "On \($0) the plan continues as a new annual commitment at your current price." }
            ?? "When the commitment ends, the plan continues as a new annual commitment at your current price."
    }

    /// Cancellation terms, from `has_notice_period` and `cancel_without_notice_until` when available.
    static func noticePeriod(_ ms: BruceAPI.MembershipInfo?) -> String {
        if let d = day(ms?.cancelWithoutNoticeUntil) { return "You can cancel without notice until \(d)." }
        let base = "New members can cancel without notice during their first month. Later cancellations run for one more month, so one further payment is charged."
        if ms?.hasNoticePeriod == true { return "A notice period currently applies to your membership. " + base }
        return base
    }

    static let refundRule = "• Refunded only if you cancel before the cancellation deadline"

    // MARK: Plans

    static func planBlurb(_ code: String) -> String {
        switch code.uppercased() {
        case "BLACK": return "More studios and bookings, plus a few Wellness visits each month."
        case "EPIC": return "The widest studio range, the most bookings and the most Wellness visits."
        default: return "The core studio range for a steady weekly training routine."
        }
    }

    // MARK: Invites

    /// `open`/`total` come from `GET /v52/booking/voucher` (nil when logged out).
    static func inviteIntro(open: Int?) -> String {
        var s = "Give someone who isn't a member yet a free session within your own membership tier. Each code is good for a single use."
        s += "\n\nIf they join as members within 30 days, your next payment is 200 kr lower and they pay 30 % less for their first three months."
        if let open { s += "\n\nUnused codes right now: \(open)." }
        return s
    }

    /// Class page "Invite": asks a friend to join this class (the membership invite codes live under Account).
    static func classInvite(_ c: BruceAPI.BruceClass, studio: String) -> String {
        "Join me at \(c.title) at \(studio), \(classDateLine(c))."
    }

    static func shareInvite(_ code: String) -> String { "Here's a free workout at Bruce Studios on me. Invite code: \(code)" }

    static func howItWorks(open: Int?) -> [String] {
        [
            "Invites come with a membership. Accounts that only hold credits can't send them.",
            "Every code is single-use and only works for someone who isn't a member yet. The free session can be a class or open training, for example at a gym.",
            "After a code is registered, the workout has to happen within 30 days. A non-member can get a free invite workout at most once every three months.",
            "When someone you invited becomes a member, your codes are topped up again." + (open.map { " You have \($0) unused right now." } ?? ""),
            "A small number of studios don't accept invite workouts.",
        ]
    }

    // MARK: Notifications

    static let pushInfo = [
        "Pick which notifications you want. Most arrive as push notifications, and key ones also go out by email.",
        "These switches don't change the notification list inside the app.",
    ]

    /// Fallback subtitles when the API's notification type has no `description`.
    static func pushSubtitle(_ key: String) -> String {
        switch key {
        case "booking_reminder": return "Before a booked class starts"
        case "check_in_reminder": return "When your check-in window opens"
        case "new_studio": return "When a studio joins"
        default: return ""
        }
    }

    static let marketing = "Choose how Bruce Studios may contact you with offers and news."

    // MARK: Waitlist

    static let waitlistJoined = "You'll get a notification if a spot opens up."
    static let leaveWaitlist = "Leave the waitlist for this class?"
    /// Badge on a waitlisted class that has a free spot again (booking it is first come, first served).
    static let spotOpen = "Spot open"

    // MARK: Explore

    static let areaHint = "Frame the area on the map, then save to use everything in view, or draw your own outline."
    static let searchHint = "Search for studios, classes, instructors or categories."

    // MARK: Account

    static let locationUse = "Used to suggest studios and classes near you."
    static let resetPassword = "Enter your account email and you'll get a link to set a new password."
    static let unlimitedExcluded = "Studios with unlimited visits aren't counted."

    // MARK: Help

    static let helpTopics = ["Memberships", "Booking and check-in", "Pausing or cancelling", "Payments and receipts",
                             "Invites and vouchers", "Visit limits"]
}
