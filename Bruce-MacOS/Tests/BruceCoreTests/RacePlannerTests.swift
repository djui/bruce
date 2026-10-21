import XCTest
@testable import BruceMacOS

/// RacePlanner.swift (Train for it): phases from the race date, the class mix per race type, the weeks × categories
/// grid with the member's changes, monthly targets, filling this week's slots, suggestions, the category mapping and
/// the race-week reminders. The same cases run against docs/app/js/raceplan.js in docs/app/test/raceplan.test.js.
final class RacePlannerTests: XCTestCase {
    let now = BruceDate.parse("2026-10-21T10:00:00Z")!   // Wednesday 21 October 2026 (W43), 12:00 in Stockholm
    func at(_ iso: String) -> Date { BruceDate.parse(iso)! }

    /// HYROX Stockholm on Saturday 12 December 2026, started on Monday 5 October: the report's 10-week table.
    func hyrox(_ edits: [String: Int] = [:], perWeek: Int = 4, startedOn: String = "2026-10-05") -> RacePlan {
        var s = RacePlanSettings(startedOn: startedOn, perWeek: perWeek)
        s.edits = edits
        return RacePlan(raceDay: "2026-12-12", type: .hyrox, settings: s)!
    }
    func cls(_ json: String) -> BruceAPI.BruceClass { try! JSONDecoder().decode(BruceAPI.BruceClass.self, from: Data(json.utf8)) }

    func testPhasesFromTheBlockLength() {
        let b = PlanPhase.base, u = PlanPhase.build, p = PlanPhase.peak, r = PlanPhase.race, x = PlanPhase.recovery
        XCTAssertEqual(RacePlanner.phases(blockWeeks: 10), [b, b, b, b, u, u, u, p, p, r, x])
        XCTAssertEqual(RacePlanner.phases(blockWeeks: 7), [b, b, u, u, p, p, r, x])
        XCTAssertEqual(RacePlanner.phases(blockWeeks: 6), [u, u, u, p, p, r, x], "under six weeks away: no Base")
        XCTAssertEqual(RacePlanner.phases(blockWeeks: 3), [u, p, r, x])
        XCTAssertEqual(RacePlanner.phases(blockWeeks: 2), [p, r, x])
        XCTAssertEqual(RacePlanner.phases(blockWeeks: 1), [r, x])
        XCTAssertEqual(RacePlanner.phases(blockWeeks: 16).filter { $0 == .base }.count, 8)
    }

    func testHyroxTenWeekPlan() {
        let plan = hyrox()
        XCTAssertEqual(plan.weeks.map(\.label), ["W41", "W42", "W43", "W44", "W45", "W46", "W47", "W48", "W49", "W50", "W51"])
        XCTAssertEqual(plan.weeks.first?.monday, "2026-10-05")
        XCTAssertEqual(plan.raceWeek?.monday, "2026-12-07")
        XCTAssertEqual(plan.blockWeeks, 10)
        XCTAssertEqual(plan.rows, [.hyrox, .strength, .running, .mobility, .highIntensity, .sauna])
        XCTAssertEqual(plan.segments.map(\.phase), [.base, .build, .peak, .race])
        XCTAssertEqual(plan.segments.map(\.weeks), [4, 3, 2, 1])
        func row(_ c: PlanCategory) -> [Int] { plan.weeks.map { $0.count(c) } }
        XCTAssertEqual(row(.hyrox), [1, 1, 1, 1, 2, 2, 2, 2, 2, 1, 0])
        XCTAssertEqual(row(.strength), [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0])
        XCTAssertEqual(row(.running), [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0])
        XCTAssertEqual(row(.mobility), [1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1])
        XCTAssertEqual(row(.sauna), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(plan.weeks.map(\.total), [4, 4, 4, 4, 4, 4, 4, 4, 4, 2, 2])
        // Five a week adds High-intensity in Build and Peak, a second Strength in Base.
        let five = hyrox(perWeek: 5)
        XCTAssertEqual(five.weeks[0].count(.strength), 2)
        XCTAssertEqual(five.weeks[4].count(.highIntensity), 1)
        XCTAssertEqual(five.weeks[9].total, 2, "race week stays light")
    }

    func testHeadlineAndStatus() {
        let plan = hyrox()
        XCTAssertEqual(plan.headline(now: now), "Week 3 of 10 · Base")
        XCTAssertEqual(plan.headline(now: at("2026-11-10T10:00:00Z")), "Week 6 of 10 · Build")
        XCTAssertEqual(plan.headline(now: at("2026-12-08T10:00:00Z")), "Week 10 of 10 · Race week")
        XCTAssertEqual(plan.headline(now: at("2026-12-15T10:00:00Z")), "Recovery week")
        XCTAssertEqual(plan.headline(now: at("2026-12-21T10:00:00Z")), "Plan done")
        XCTAssertFalse(plan.isRunning(now: at("2026-12-21T10:00:00Z")))
        // Started long before: the block still counts back 10 weeks from race week.
        let early = hyrox(startedOn: "2026-06-01")
        XCTAssertEqual(early.weeks.first?.monday, "2026-10-05")
        XCTAssertEqual(early.headline(now: at("2026-09-01T10:00:00Z")), "Starts Mon 5 Oct")
        XCTAssertEqual(early.status(now: at("2026-09-01T10:00:00Z")), .upcoming)
    }

    func testShortLeadTimesDegrade() {
        // Started in W45: six weeks to race week, so no Base.
        let late = hyrox(startedOn: "2026-11-04")
        XCTAssertEqual(late.blockWeeks, 6)
        XCTAssertEqual(late.weeks.map(\.phase), [.build, .build, .build, .peak, .peak, .race, .recovery])
        XCTAssertEqual(late.headline(now: at("2026-11-04T10:00:00Z")), "Week 1 of 6 · Build")
        // Started in race week: race week and recovery only.
        let last = hyrox(startedOn: "2026-12-09")
        XCTAssertEqual(last.weeks.map(\.phase), [.race, .recovery])
        XCTAssertEqual(last.headline(now: at("2026-12-09T10:00:00Z")), "Week 1 of 1 · Race week")
        // A shorter block on purpose.
        var s = RacePlanSettings(startedOn: "2026-10-05", weeks: 4)
        s.perWeek = 3
        let four = RacePlan(raceDay: "2026-12-12", type: .hyrox, settings: s)!
        XCTAssertEqual(four.weeks.first?.label, "W47")
        XCTAssertEqual(four.weeks.map(\.phase), [.build, .build, .peak, .race, .recovery])
        XCTAssertEqual(four.weeks[0].total, 3)
    }

    func testMemberEditsAWeek() {
        let plan = hyrox(["2026-10-19|hyrox": 2, "2026-10-19|mobility": 0, "2026-11-30|sauna": 3])
        let w43 = plan.weeks[2]
        XCTAssertEqual(w43.count(.hyrox), 2)
        XCTAssertEqual(w43.count(.mobility), 0)
        XCTAssertEqual(w43.edited, [.hyrox, .mobility])
        XCTAssertEqual(w43.total, 4)
        XCTAssertEqual(plan.weeks[8].count(.sauna), 3)
        XCTAssertEqual(plan.weeks[3].count(.hyrox), 1, "other weeks keep the mix")
        XCTAssertEqual(RacePlanner.mixText(plan.raceWeek!, rows: plan.rows), "1 Hyrox and 1 Mobility")
        XCTAssertEqual(RacePlanner.mixText(plan.weeks[4], rows: plan.rows), "2 Hyrox, 1 Strength and 1 Running")
    }

    func testMonthTargets() {
        let plan = hyrox()
        func t(_ iso: String) -> [String] { plan.monthTargets(month: at(iso)).map { "\($0.category.rawValue) \($0.count)" } }
        // A week counts for the month of its Thursday: W41-W44 in October, W45-W48 in November.
        XCTAssertEqual(t("2026-10-21T10:00:00Z"), ["hyrox 4", "strength 4", "running 4", "mobility 4"])
        XCTAssertEqual(t("2026-11-15T10:00:00Z"), ["hyrox 8", "strength 4", "running 4"])
        XCTAssertEqual(t("2026-12-15T10:00:00Z"), ["hyrox 3", "strength 1", "running 1", "mobility 2", "sauna 1"])
        XCTAssertEqual(t("2027-01-15T10:00:00Z"), [])
    }

    func testThisWeekFillsSlots() {
        let plan = hyrox()
        let w43 = plan.weeks[2]
        func item(_ kind: PlanItem.Kind, _ day: Int, _ cats: Set<PlanCategory>, _ title: String) -> PlanItem {
            PlanItem(kind: kind, classId: nil, title: title, studioId: nil, start: at("2026-10-\(day)T16:00:00Z"), categories: cats)
        }
        let st = RacePlanner.assign(week: w43, rows: plan.rows, items: [
            item(.booked, 22, [.hyrox, .highIntensity], "Hyrox"), item(.done, 19, [.strength], "Strength"),
            item(.done, 20, [.running, .outdoor], "Run Club"), item(.autoBook, 25, [.mobility], "Mobility"),
            item(.done, 21, [.strength], "Strength Circuit"),
        ])
        XCTAssertEqual(st.slots.map(\.category), [.hyrox, .strength, .running, .mobility])
        XCTAssertEqual(st.slots.map(\.state), [.booked, .done, .done, .autoBook])
        XCTAssertEqual(st.progressText, "2 of 4 this week")
        XCTAssertEqual(st.extra.map(\.title), ["Strength Circuit"])
        // A class in two categories takes the one with more open slots (Build: 2 Hyrox, 1 Strength).
        let w45 = plan.weeks[4]
        let two = RacePlanner.assign(week: w45, rows: plan.rows, items: [item(.done, 3, [.strength, .hyrox], "Hyrox Strength")])
        XCTAssertEqual(two.slots.first { $0.item != nil }?.category, .hyrox)
    }

    func testSuggestionsPickClassesOfTheWeek() {
        let plan = hyrox()
        let open = RacePlanner.assign(week: plan.weeks[2], rows: plan.rows, items: [])
        let classes = [
            cls(#"{"id":1,"studio_id":9810,"title":"Hyrox","start_time":"2026-10-22T16:00:00Z","end_time":"2026-10-22T17:00:00Z","available_spots":7,"class_categories":[{"category_id":13}]}"#),
            cls(#"{"id":2,"studio_id":9810,"title":"Hyrox","start_time":"2026-10-27T16:00:00Z","end_time":"2026-10-27T17:00:00Z","available_spots":7,"class_categories":[{"category_id":13}]}"#),
            cls(#"{"id":3,"studio_id":1724,"title":"Strength","start_time":"2026-10-23T05:30:00Z","end_time":"2026-10-23T06:15:00Z","available_spots":0,"class_categories":[{"category_id":26}]}"#),
            cls(#"{"id":4,"studio_id":1724,"title":"Strength","start_time":"2026-10-23T16:30:00Z","end_time":"2026-10-23T17:15:00Z","available_spots":4,"class_categories":[{"category_id":26}]}"#),
            cls(#"{"id":5,"studio_id":1489,"title":"Mobility","start_time":"2026-10-25T15:00:00Z","end_time":"2026-10-25T15:45:00Z","available_spots":9,"class_categories":[{"category_id":16}]}"#),
        ]
        let rec = RecInput(now: now, classes: classes, studioPoints: [:], visits: [], friendsByClass: [:], excluded: [], settings: RecSettings(), categoryTitles: [:])
        let ids = Dictionary(uniqueKeysWithValues: PlanCategory.allCases.map { ($0, $0.categoryId) })
        let input = RacePlanner.SuggestInput(now: now, notAfter: plan.weeks[2].end, rec: rec, categoryIds: ids)
        let st = RacePlanner.suggest(open, input: input)
        XCTAssertEqual(st.slots.map { $0.suggestion?.c.id }, [1, 4, nil, 5], "this week only, not full, one per class")
        XCTAssertEqual(st.slots.map(\.state), [.suggested, .suggested, .open, .suggested])
        XCTAssertEqual(st.nextToBook?.c.id, 1)
        XCTAssertEqual(st.slots[0].suggestion?.fewSpots, 7)
        XCTAssertEqual(st.slots[0].suggestion?.strike, false)
        // Visit limits, tiers and the area come in as `allowed`.
        var blocked = input
        blocked.allowed = { $0.studioId != 9810 }
        XCTAssertNil(RacePlanner.suggest(open, input: blocked).slots[0].suggestion)
        // On Thursday at 11:00 the 18:00 Hyrox is inside the free cancellation: it still shows, marked.
        var late = input
        late.now = at("2026-10-22T09:00:00Z")
        late.rec.now = late.now
        XCTAssertEqual(RacePlanner.suggest(open, input: late).slots[0].suggestion?.strike, true)
    }

    func testCategoryMapping() {
        // The demo data's ids are the report's: Hyrox 13, Running 23, Strength 26, Swimming 27 ...
        for c in PlanCategory.allCases {
            XCTAssertEqual(c.resolve(in: BruceAPI.Category.demo), c.categoryId, c.rawValue)
            XCTAssertTrue(c.names(category: BruceAPI.Category.demo.first { $0.id == c.categoryId }?.title), c.rawValue)
        }
        func cat(_ id: Int, _ title: String, code: String? = nil) -> BruceAPI.Category { .init(id: id, code: code, title: title, photo: nil) }
        // An id that moved is found by title; an id that now names something else is not used; a missing id is.
        XCTAssertEqual(PlanCategory.swimming.resolve(in: [cat(30, "Swimming"), cat(27, "Other")]), 30)
        XCTAssertNil(PlanCategory.hyrox.resolve(in: [cat(13, "Other"), cat(1, "Gym")]))
        XCTAssertEqual(PlanCategory.hyrox.resolve(in: [cat(1, "Gym")]), 13)
        XCTAssertEqual(PlanCategory.highIntensity.resolve(in: [cat(40, "High Intensity")]), 40)
        XCTAssertEqual(PlanCategory.hyrox.resolve(in: [cat(41, "Functional", code: "HYROX")]), 41)
        XCTAssertEqual(PlanCategory.hyrox.resolve(in: []), 13)
        // Weekly rules without a loaded class: the title.
        XCTAssertEqual(PlanCategory.guess(title: "Hyrox Prep"), .hyrox)
        XCTAssertEqual(PlanCategory.guess(title: "Strength Circuit"), .strength)
        XCTAssertEqual(PlanCategory.guess(title: "Run Club"), .running)
        XCTAssertEqual(PlanCategory.guess(title: "High Intensity"), .highIntensity)
        XCTAssertNil(PlanCategory.guess(title: "Morning Flow"))
        XCTAssertNil(PlanCategory.guess(title: "Brunch Ride"))
        XCTAssertTrue(PlanCategory.hyrox.heavy && !PlanCategory.mobility.heavy)
    }

    func testMixPerRaceType() {
        XCTAssertEqual(PlanTemplate.forRace(.endurance, sport: .ski).base.first, .cardio)
        XCTAssertEqual(PlanTemplate.forRace(.endurance, sport: .bike).build.prefix(2), [.cycling, .cycling])
        XCTAssertEqual(PlanTemplate.forRace(.endurance, sport: .swim).peak.prefix(2), [.swimming, .swimming])
        XCTAssertEqual(PlanTemplate.forRace(.endurance, sport: .swim).raceWeek, [.swimming, .mobility], "race week: an easy one in the race's sport")
        XCTAssertEqual(Set(PlanTemplate.forRace(.triathlon).base.prefix(4)), [.swimming, .cycling, .running, .strength])
        XCTAssertEqual(PlanTemplate.forRace(.running).raceWeek, [.mobility])
        XCTAssertEqual(PlanTemplate.forRace(.running).recovery.first, .massage)
        XCTAssertTrue(PlanTemplate.forRace(.obstacle).rows.contains(.climbing))
        XCTAssertEqual(PlanTemplate.forRace(.obstacle).raceWeek, [.climbing, .mobility])
        for t in RaceType.allCases { XCTAssertGreaterThanOrEqual(PlanTemplate.forRace(t).base.count, 6, t.rawValue) }
    }

    func testRaceDayReminderTimes() {
        XCTAssertEqual(RaceReminders.weekTime("2026-12-12"), at("2026-12-07T07:00:00Z"))   // Monday 08:00 CET
        XCTAssertEqual(RaceReminders.eveTime("2026-12-12"), at("2026-12-11T17:00:00Z"))    // Friday 18:00
        XCTAssertNil(RaceReminders.weekTime("2026-12-07"), "a Monday race: the evening before covers it")
        XCTAssertEqual(RaceReminders.weekTime("2026-10-31"), at("2026-10-26T07:00:00Z"))   // after summer time
        XCTAssertEqual(RaceReminders.eveTime("2026-10-26"), at("2026-10-25T17:00:00Z"))    // on the change day
    }

    func testRaceDayReminderPlan() {
        let race = Race.demo.first { $0.id == "hyrox-stockholm-2026" }!
        var m = MyRace(race: race, day: "2026-12-12")
        m.remindWeek = true; m.remindEve = true
        m.plan = RacePlanSettings(startedOn: "2026-10-05")
        let p = RaceReminders.plan([m], catalog: Race.demo, now: now)
        XCTAssertEqual(p.map(\.id), ["race-reminder-week-hyrox-stockholm-2026", "race-reminder-eve-hyrox-stockholm-2026"])
        XCTAssertEqual(p[0].title, "Race week: HYROX Stockholm")
        XCTAssertEqual(p[0].body, "Saturday is race day. Your class mix this week: 1 Hyrox and 1 Mobility.")
        XCTAssertEqual(p[1].title, "Tomorrow: HYROX Stockholm")
        XCTAssertEqual(p[1].body, "Race day tomorrow. Start times and what to bring are on hyrox.com.")
        XCTAssertEqual(p[0].raceId, "hyrox-stockholm-2026")
        // The server sends them: none on the device.
        XCTAssertTrue(RaceReminders.plan([m], catalog: Race.demo, now: now, serverIds: [m.key]).isEmpty)
        // A race added by hand gets them too; one that is over does not.
        var own = MyRace(name: "Club 10K", date: "2026-11-14")
        own.remindEve = true
        let o = RaceReminders.plan([own], catalog: [], now: now)
        XCTAssertEqual(o.map(\.title), ["Tomorrow: Club 10K"])
        XCTAssertEqual(o.first?.body, "Race day tomorrow.")
        XCTAssertEqual(o.first?.raceId, own.key)
        XCTAssertTrue(RaceReminders.plan([m], catalog: Race.demo, now: at("2026-12-11T18:00:00Z")).isEmpty)
    }

    func testGoalsFromThePlan() {
        let plan = hyrox()
        let ids = Dictionary(uniqueKeysWithValues: PlanCategory.allCases.map { ($0, $0.categoryId) })
        let title = { (k: String) in "goal \(k)" }
        let mine = MonthlyGoal(category: "26", title: "Strength classes", target: 6)
        let october = RacePlanner.GoalPlan(key: "hyrox-stockholm-2026", targets: plan.monthTargets(month: now))
        var g = RacePlanner.planGoals([mine], plans: [october], ids: ids, title: title)
        XCTAssertEqual(g.map { "\($0.category ?? "") \($0.target) \($0.raceKey ?? "own")" },
                       ["26 6 own", "13 4 hyrox-stockholm-2026", "23 4 hyrox-stockholm-2026", "16 4 hyrox-stockholm-2026"], "the member's Strength goal stays theirs")
        XCTAssertTrue(g.filter { $0.raceKey != nil }.allSatisfy(\.remind))
        // November: targets follow the plan, Mobility (none planned) goes, and comes back in December.
        let november = RacePlanner.GoalPlan(key: october.key, targets: plan.monthTargets(month: at("2026-11-15T10:00:00Z")))
        g = RacePlanner.planGoals(g, plans: [november], ids: ids, title: title)
        XCTAssertEqual(g.compactMap { $0.raceKey == nil ? nil : "\($0.category!) \($0.target)" }, ["13 8", "23 4"])
        let december = RacePlanner.GoalPlan(key: october.key, targets: plan.monthTargets(month: at("2026-12-15T10:00:00Z")))
        XCTAssertEqual(RacePlanner.planGoals(g, plans: [december], ids: ids, title: title).compactMap { $0.raceKey == nil ? nil : $0.category }, ["13", "23", "16"], "the four biggest: Hyrox 3, Mobility 2, Strength (theirs) and Running 1")
        // A category the member deleted stays deleted; a plan that stopped takes its goals along.
        var skipping = october; skipping.skip = ["23"]
        XCTAssertFalse(RacePlanner.planGoals([mine], plans: [skipping], ids: ids, title: title).contains { $0.category == "23" })
        XCTAssertEqual(RacePlanner.planGoals(g, plans: [], ids: ids, title: title), [mine])
    }

    func testRaceDayRemindersPerRaceOnTheServerAndMondays() {
        let race = Race.demo.first { $0.id == "hyrox-stockholm-2026" }!
        var m = MyRace(race: race, day: "2026-12-12")
        m.remindWeek = true; m.remindEve = true
        var own = MyRace(name: "Monday Run", date: "2026-12-14")
        own.remindWeek = true
        // The server confirmed HYROX only: the race added by hand stays on the device.
        let p = RaceReminders.plan([m, own], catalog: Race.demo, now: now, serverIds: ["hyrox-stockholm-2026"])
        XCTAssertEqual(p.map(\.id), ["race-reminder-eve-\(own.key)"], "a Monday race: the race-week switch is the evening before")
        XCTAssertEqual(p.first?.fire, at("2026-12-13T17:00:00Z"))
        own.remindEve = true
        XCTAssertEqual(RaceReminders.plan([own], catalog: [], now: now).count, 1, "both switches: one reminder")
        // My races keep an endurance race's sport, so the mix is right before the catalog loads.
        let vasa = MyRace(race: Race.demo.first { $0.id == "vasaloppet-2027" }!)
        let back = try! JSONDecoder().decode(MyRace.self, from: JSONEncoder().encode(vasa))
        XCTAssertEqual(back.sport, .ski)
        XCTAssertEqual(back.resolved(in: []).sport, .ski)
    }

    func testMyRacesFilesStayReadable() throws {
        let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","raceId":"hyrox-stockholm-2026","name":"HYROX Stockholm","date":"2026-12-10","type":"hyrox"}]"#
        let a = try JSONDecoder().decode([MyRace].self, from: Data(old.utf8))[0]
        XCTAssertFalse(a.remindWeek)
        XCTAssertNil(a.plan)
        let withPlan = #"[{"name":"A","date":"2026-12-12","plan":{"startedOn":"2026-10-05","perWeek":5,"edits":{"2026-10-19|hyrox":2}}},{"name":"B","date":"2026-12-12","remindEve":true,"plan":{"perWeek":"x"}}]"#
        let list = try JSONDecoder().decode([MyRace].self, from: Data(withPlan.utf8))
        XCTAssertEqual(list[0].plan?.perWeek, 5)
        XCTAssertEqual(list[0].plan?.weeks, 10)
        XCTAssertEqual(list[0].plan?.edits["2026-10-19|hyrox"], 2)
        XCTAssertNil(list[1].plan, "an unreadable plan is dropped, the race stays")
        XCTAssertTrue(list[1].remindEve)
        // Round trip, with a paused rule.
        var m = list[0]
        m.plan?.paused = [AutoBookRule(studioId: 9810, masterId: nil, title: "Hyrox", weekday: 5, minuteOfDay: 1080)]
        let back = try JSONDecoder().decode(MyRace.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back.plan, m.plan)
        // Monthly goals made from a plan keep their race; old goals decode without one.
        let g = try JSONDecoder().decode([MonthlyGoal].self, from: Data(#"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","category":"13","title":"Hyrox classes","target":4,"remind":true}]"#.utf8))
        XCTAssertNil(g[0].raceKey)
    }
}
