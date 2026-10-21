import XCTest
@testable import BruceMacOS

/// RaceSocial.swift: going on My races entries and the server's answer, crews (challenges with a race and a weekly
/// target), their words, results links and the recovery week after the race. The same cases run against
/// docs/app/js/crews.js and races.js in docs/app/test/crews.test.js.
final class RaceSocialTests: XCTestCase {
    lazy var catalog: [Race] = try! RaceCatalog.decode(RacesTests.repoFile("docs/app/test/races-fixture.json"))
    lazy var published: [Race] = try! RaceCatalog.decode(RacesTests.repoFile("docs/app/races.json"))
    func race(_ id: String) -> Race { catalog.first { $0.id == id }! }
    func at(_ iso: String) -> Date { BruceDate.parse(iso)! }

    func testGoingIsSavedPerRaceAndOldFilesLoad() throws {
        var m = MyRace(race: race("hyrox-stockholm-2026"), day: "2026-12-12")
        XCTAssertFalse(m.going, "off by default")
        m.going = true
        let back = try JSONDecoder().decode(MyRace.self, from: JSONEncoder().encode(m))
        XCTAssertTrue(back.going)
        let old = #"{"raceId":"hyrox-stockholm-2026","name":"HYROX Stockholm","date":"2026-12-10"}"#
        XCTAssertFalse(try JSONDecoder().decode(MyRace.self, from: Data(old.utf8)).going)
        // Only catalog races are shared: a race added by hand has no shared record.
        var custom = MyRace(name: "Club 10K", date: "2026-11-14")
        custom.going = true
        XCTAssertFalse(MyRaces.entries([custom], catalog: catalog)[0].sharesGoing)
        XCTAssertTrue(MyRaces.entries([back], catalog: catalog)[0].sharesGoing)
    }

    @MainActor func testSyncBodyCarriesGoingWithTheMomentItWasFlipped() {
        var on = MyRace(race: race("hyrox-stockholm-2026"), day: "2026-12-12")
        on.going = true; on.goingAt = Date(timeIntervalSince1970: 1)
        var off = MyRace(race: race("vasaloppet-2027"))
        off.going = false; off.goingAt = Date(timeIntervalSince1970: 2)
        let quiet = MyRace(race: race("tough-viking-stadion-2027"))
        var custom = MyRace(name: "Club 10K", date: "2026-11-14")
        custom.going = true; custom.goingAt = Date()
        let entries = MyRaces.upcoming(MyRaces.entries([on, off, quiet, custom], catalog: catalog), now: at("2026-10-21T10:00:00Z"))
        let body = AppModel.raceSyncBody(entries) { _ in nil }
        // Switched off is sent too (the server hears it without a reminder); untouched and hand-added races are not.
        XCTAssertEqual(body.map { $0["id"] as? String }, ["hyrox-stockholm-2026", "vasaloppet-2027"])
        XCTAssertEqual(body.map { $0["going"] as? Bool }, [true, false])
        XCTAssertEqual(body.map { $0["goingAt"] as? Int }, [1000, 2000])
        XCTAssertEqual(body.first?["date"] as? String, "2026-12-12")
    }

    func testGoingAnswerDecodes() throws {
        let json = #"{"going":{"hyrox-stockholm-2026":[{"userId":7,"name":"Robin"},{"userId":9,"name":"Sam"}]},"sharing":true,"mine":["vasaloppet-2027"]}"#
        let g = try JSONDecoder().decode(RaceGoing.self, from: Data(json.utf8))
        XCTAssertEqual(g.going["hyrox-stockholm-2026"]?.map(\.userId), [7, 9])
        XCTAssertTrue(g.sharing)
        XCTAssertEqual(g.mine, ["vasaloppet-2027"])
        XCTAssertEqual(try JSONDecoder().decode(RaceGoing.self, from: Data(#"{"going":{},"sharing":false,"mine":[]}"#.utf8)), RaceGoing())
    }

    func testWords() {
        XCTAssertEqual(RaceSocialText.going(1), "1 friend going")
        XCTAssertEqual(RaceSocialText.going(2), "2 friends going")
        XCTAssertEqual(RaceSocialText.names(["Alex"]), "Alex is going")
        XCTAssertEqual(RaceSocialText.names(["Alex", "Maja"]), "Alex and Maja are going")
        XCTAssertEqual(RaceSocialText.names(["Alex", "", "Maja", "Robin"]), "Alex, Maja and Robin are going")
        XCTAssertEqual(RaceSocialText.weekly(1), "1 session a week")
        XCTAssertEqual(RaceSocialText.weekly(4), "4 sessions a week")
        XCTAssertEqual(RaceSocialText.thisWeek(2, 4), "2 of 4 this week")
        XCTAssertEqual(RaceSocialText.crewName(race("hyrox-stockholm-2026")), "HYROX Stockholm crew")
        XCTAssertEqual(Crew.defaultWeekly(nil), 3)
        XCTAssertEqual(Crew.defaultWeekly(RacePlanSettings(startedOn: "2026-10-05", perWeek: 5)), 5)
        XCTAssertEqual(Crew.defaultWeekly(RacePlanSettings(startedOn: "2026-10-05", perWeek: 12)), 7)
    }

    func testCrewDecodesFromTheServerAndOldChallengesStayChallenges() throws {
        let json = #"""
        {"challenge":{"id":"abc","title":"HYROX Sthlm Doubles","metric":"visits","start":"2026-10-21","end":"2026-12-12","repeatMonthly":false,
          "ownerId":42,"ownerName":"Uwe","myStatus":"accepted","raceId":"hyrox-stockholm-2026","weekly":4,
          "participants":[{"userId":42,"name":"Uwe","status":"accepted"},{"userId":7,"name":"Robin","status":"accepted"}],
          "period":{"start":"2026-10-21","end":"2026-12-12","label":"21 Oct – 12 Dec 2026","day":1,"days":53,"daysLeft":52}},
         "leaderboard":[],"months":[],
         "crew":{"raceId":"hyrox-stockholm-2026","weekly":4,"size":2,"week":{"start":"2026-10-19","end":"2026-10-25"},
          "lastWeek":{"start":"2026-10-12","end":"2026-10-18","hit":1},"weeksLeft":8,
          "members":[{"userId":42,"name":"Uwe","thisWeek":2,"lastWeek":4},{"userId":7,"name":"Robin","thisWeek":1,"lastWeek":3}]}}
        """#
        let d = try JSONDecoder().decode(ChallengeDetail.self, from: Data(json.utf8))
        XCTAssertTrue(d.challenge.isCrew)
        XCTAssertEqual(d.challenge.weekly, 4)
        let w = try XCTUnwrap(d.crew)
        XCTAssertEqual(w.members.map(\.thisWeek), [2, 1])
        XCTAssertEqual(RaceSocialText.lastWeek(w), "Last week 1 of 2 hit their sessions")
        XCTAssertEqual(RaceSocialText.doneThisWeek(w), "0 of 2 done this week")
        var first = w
        first.lastWeek = nil
        XCTAssertNil(RaceSocialText.lastWeek(first), "the crew's first week")
        let plain = try JSONDecoder().decode(ChallengeSummary.self, from: Data(#"{"id":"x","metric":"classes"}"#.utf8))
        XCTAssertFalse(plain.isCrew)
    }

    func testCrewDraftBody() {
        let end = RaceDay.date("2026-12-12")!
        let d = ChallengeDraft(metric: "visits", start: RaceDay.date("2026-10-21")!, end: end, repeatMonthly: false, invite: [7],
                               raceId: "hyrox-stockholm-2026", weekly: 4, name: "HYROX Sthlm Doubles")
        let b = d.body
        XCTAssertEqual(b["raceId"] as? String, "hyrox-stockholm-2026")
        XCTAssertEqual(b["weekly"] as? Int, 4)
        XCTAssertEqual(b["title"] as? String, "HYROX Sthlm Doubles")
        XCTAssertEqual(b["end"] as? String, "2026-12-12")
        XCTAssertEqual(b["metric"] as? String, "visits")
        XCTAssertEqual(b["repeatMonthly"] as? Bool, false)
        XCTAssertEqual(b["invite"] as? [Int], [7])
        // A challenge is unchanged.
        let c = ChallengeDraft(metric: "target", target: 12, start: end, end: end)
        XCTAssertEqual(c.body["title"] as? String, "Everyone hits 12")
        XCTAssertNil(c.body["raceId"])
    }

    func testResultsLinks() {
        XCTAssertNil(race("tough-viking-stadion-2027").results, "the fixture has none")
        var r = race("lidingoloppet-2027")
        r.resultsUrl = "https://lidingoloppet.se/en/tcs-lidingoloppet/results-and-statistics"
        XCTAssertEqual(r.results?.host, "lidingoloppet.se")
        r.resultsUrl = "http://example.com/results"
        XCTAssertNil(r.results, "https only")
        r.resultsUrl = "javascript:alert(1)"
        XCTAssertNil(r.results)
        // The published catalog: every results link is https and opens; the 2026 editions are over with results.
        for x in published where x.resultsUrl != nil { XCTAssertNotNil(x.results, x.id) }
        let now = at("2026-10-21T10:00:00Z")
        for id in ["goteborgsvarvet-2026", "midnattsloppet-stockholm-2026"] {
            let x = published.first { $0.id == id }!
            XCTAssertTrue(x.isPast(now: now), id)
            XCTAssertNotNil(x.results, id)
            XCTAssertEqual(x.pillText(now: now), "Done")
        }
        XCTAssertTrue(Race.demo.contains { $0.id == "midnattsloppet-stockholm-2026" && $0.results != nil }, "the demo has a race with results")
    }

    func testRecoveryWeekAfterTheRace() {
        // HYROX on Saturday 12 December: race week is 7-13 Dec, the recovery week 14-20 Dec.
        let e = MyRaces.entries([MyRace(race: race("hyrox-stockholm-2026"), day: "2026-12-12")], catalog: catalog)[0]
        XCTAssertNil(e.recovery(now: at("2026-12-12T15:00:00Z")), "race day")
        let r = e.recovery(now: at("2026-12-13T09:00:00Z"))
        XCTAssertEqual(r?.monday, "2026-12-14")
        XCTAssertEqual(r?.sunday, "2026-12-20")
        XCTAssertEqual(r?.text, "1 Mobility and 1 Sauna")
        XCTAssertNotNil(e.recovery(now: at("2026-12-20T20:00:00Z")))
        XCTAssertNil(e.recovery(now: at("2026-12-21T08:00:00Z")), "the week after the recovery week")
        // Without a day of its own, a multi-day event counts from its last day.
        let all = MyRaces.entries([MyRace(race: race("hyrox-stockholm-2026"))], catalog: catalog)[0]
        XCTAssertNil(all.recovery(now: at("2026-12-13T09:00:00Z")), "still on")
        XCTAssertEqual(all.recovery(now: at("2026-12-14T09:00:00Z"))?.monday, "2026-12-14")
        // A run: massage and mobility.
        let run = MyRaces.entries([MyRace(race: race("goteborgsvarvet-2027"))], catalog: catalog)[0]
        XCTAssertEqual(run.recovery(now: at("2027-05-24T09:00:00Z"))?.text, "1 Massage and 1 Mobility")
    }
}
