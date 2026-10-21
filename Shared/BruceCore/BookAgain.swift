import Foundation

// "Book again": the next class of a series the user went to (Statistics, My classes, the rating sheet, a past class
// page), found the way auto-book finds a weekly class (AutoBookRule.matches: same studio, weekday and start time,
// the same master_id when both sides have one, else the same title). It reads one studio on one or two days.

/// What identifies the series: built from a past class or a visit from the history.
struct BookAgainTemplate: Hashable, Codable {
    let studioId: Int
    let masterId: Int?
    let title: String
    /// Calendar weekday (1 = Sunday) and local start time in minutes, as in `AutoBookRule`.
    let weekday: Int
    let minuteOfDay: Int
    let instructor: String?

    init?(studioId: Int, masterId: Int?, title: String, start: Date?, instructor: String?) {
        guard let start, !title.isEmpty else { return nil }
        let d = BruceDate.calendar.dateComponents([.weekday, .hour, .minute], from: start)
        self.studioId = studioId
        self.masterId = masterId
        self.title = title
        weekday = d.weekday ?? 1
        minuteOfDay = (d.hour ?? 0) * 60 + (d.minute ?? 0)
        self.instructor = instructor?.isEmpty == false ? instructor : nil
    }

    init?(_ c: BruceAPI.BruceClass) {
        self.init(studioId: c.studioId, masterId: c.masterId, title: c.title, start: c.start, instructor: c.instructor)
    }

    /// Class visits only (a solo gym visit has nothing to book again).
    init?(_ v: BruceAPI.Visit) {
        guard !v.isSolo, let c = v.visitClass, let title = c.title,
              let studioId = v.studioId ?? c.studio?.id else { return nil }
        self.init(studioId: studioId, masterId: nil, title: title, start: v.classStart, instructor: c.instructor)
    }

    var rule: AutoBookRule { AutoBookRule(studioId: studioId, masterId: masterId, title: title, weekday: weekday, minuteOfDay: minuteOfDay) }
    /// "Tuesdays 18:00".
    var label: String { rule.label }
}

enum BookAgain {
    /// The next class of the series: `opens` is when booking opens if it is not open yet.
    struct Match: Hashable {
        let next: BruceAPI.BruceClass
        let opens: Date?
        let sameInstructor: Bool
    }

    /// Classes are listed about two weeks ahead, so the next occurrence is on one of the next two matching days.
    static func candidateDays(for t: BookAgainTemplate, now: Date = Date()) -> [Date] {
        let cal = BruceDate.calendar
        let today = cal.startOfDay(for: now)
        var out: [Date] = []
        for i in 0..<15 {
            guard let day = cal.date(byAdding: .day, value: i, to: today), cal.component(.weekday, from: day) == t.weekday else { continue }
            // Today only counts while the class has not started yet.
            if i == 0, let at = cal.date(byAdding: .minute, value: t.minuteOfDay, to: day), at <= now { continue }
            out.append(day)
            if out.count == 2 { break }
        }
        return out
    }

    /// The first upcoming class in `classes` that the series matches.
    static func pick(from classes: [BruceAPI.BruceClass], template t: BookAgainTemplate, now: Date = Date()) -> Match? {
        let rule = t.rule
        let next = classes.filter { c in rule.matches(c) && (c.start ?? .distantPast) > now }
            .sorted { $0.startTime < $1.startTime }.first
        guard let next else { return nil }
        let opens = next.bookingOpens.flatMap { $0 > now ? $0 : nil }
        let same = t.instructor != nil && next.instructor?.caseInsensitiveCompare(t.instructor ?? "") == .orderedSame
        return Match(next: next, opens: opens, sameInstructor: same)
    }

    /// Reads the studio's classes on the next matching day (and the one after, when the first has nothing).
    static func next(for t: BookAgainTemplate, token: String, now: Date = Date()) async -> Match? {
        for day in candidateDays(for: t, now: now) {
            let classes = (try? await BruceAPI.fetchClasses(token: token, day: day, studioId: t.studioId, maxPages: 5)) ?? []
            if let m = pick(from: classes, template: t, now: now) { return m }
        }
        return nil
    }
}

extension AppModel {
    /// The next occurrence for the Book again sheet; demo mode looks through the loaded class days instead.
    func bookAgainNext(_ t: BookAgainTemplate) async -> BookAgain.Match? {
        let m: BookAgain.Match?
        if AppModel.demo {
            m = BookAgain.pick(from: Array(classesByDay.values.joined()), template: t)
        } else {
            guard tokenUsable else { return nil }
            m = await BookAgain.next(for: t, token: token)
        }
        if let m { classDetails[m.next.id] = classDetails[m.next.id] ?? m.next }
        return m
    }

    /// Opens the Book again sheet on top of what is open (a pushed screen inside a sheet, else a new sheet).
    func openBookAgain(_ t: BookAgainTemplate) {
        if sheets.isEmpty { present(.bookAgain(t)) } else { pushSheet(.bookAgain(t)) }
    }
}
