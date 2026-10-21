import XCTest
@testable import BruceMacOS

/// Races.swift: the catalog file (docs/app/races.json), countdowns, price steps, grouping and filters, My races and
/// the reminder plan. The same cases run against docs/app/js/races.js in docs/app/test/races.test.js. The logic tests
/// read docs/app/test/races-fixture.json, the catalog frozen as checked on 21 Oct 2026.
final class RacesTests: XCTestCase {
    let now = BruceDate.parse("2026-10-21T10:00:00Z")!   // Wednesday 21 October 2026, 12:00 in Stockholm

    static func repoFile(_ path: String) -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try! Data(contentsOf: root.appendingPathComponent(path))
    }
    /// The frozen fixture (the logic tests' races).
    lazy var catalog: [Race] = try! RaceCatalog.decode(Self.repoFile("docs/app/test/races-fixture.json"))
    /// The published catalog, as it is in the repository now.
    lazy var published: [Race] = try! RaceCatalog.decode(Self.repoFile("docs/app/races.json"))
    func race(_ id: String) -> Race { catalog.first { $0.id == id }! }
    func at(_ iso: String) -> Date { BruceDate.parse(iso)! }

    func testCatalogFileDecodesEveryRace() throws {
        let raw = try JSONSerialization.jsonObject(with: Self.repoFile("docs/app/races.json")) as! [String: Any]
        XCTAssertEqual(published.count, (raw["races"] as! [Any]).count, "every entry is readable by the apps")
        XCTAssertEqual(Set(published.map(\.id)).count, published.count)
        for r in published {
            XCTAssertNotNil(r.url, r.id)
            XCTAssertTrue(r.hasReadableDates, r.id)
            XCTAssertFalse(r.checkedOn.isEmpty, r.id)
            XCTAssertTrue(["SE", "NO", "DK"].contains(r.country), r.id)
        }
        XCTAssertEqual(catalog.count, 32)
        XCTAssertEqual(catalog.filter { $0.klassiker == true }.map(\.name), ["Vasaloppet", "Vätternrundan", "Vansbrosimningen", "Lidingöloppet"])
    }

    func testDemoRacesAreCatalogRaces() {
        XCTAssertGreaterThan(Race.demo.count, 10)
        // Prices and status may move on in the catalog; the race itself must stay the same.
        func stable(_ r: Race?) -> [String?] { [r?.id, r?.name, r?.type.rawValue, r?.sport?.rawValue, r?.date, r?.endDate, r?.city, r?.country, r?.venue] }
        for d in Race.demo { XCTAssertEqual(stable(d), stable(published.first { $0.id == d.id }), d.id) }
    }

    func testLossyDecodingSkipsUnknownEntries() throws {
        let json = #"{"races":[{"id":"a","name":"A","type":"running","date":"2027-05-01","city":"X","country":"SE","distancesKm":[5],"signupUrl":"https://a.example","status":"open","checkedOn":"2026-10-21"},{"id":"b","name":"B","type":"paddle","date":"2027-05-02","city":"X","country":"SE","distancesKm":[],"signupUrl":"https://b.example","status":"open","checkedOn":"2026-10-21"},{"id":"c","name":"C","type":"running","date":"2027-02-30","city":"X","country":"SE","distancesKm":[],"signupUrl":"https://c.example","status":"open","checkedOn":"2026-10-21"}]}"#
        XCTAssertEqual(try RaceCatalog.decode(Data(json.utf8)).map(\.id), ["a"])
        // Optional fields may be missing; a bad optional date drops the entry.
        let bare = #"{"races":[{"id":"g","name":"G","type":"running","date":"2027-05-01","signupUrl":"https://g.example","status":"open"},{"id":"h","name":"H","type":"running","date":"2027-05-01","endDate":"soon","signupUrl":"https://h.example","status":"open"}]}"#
        let got = try RaceCatalog.decode(Data(bare.utf8))
        XCTAssertEqual(got.map(\.id), ["g"])
        XCTAssertEqual(got.first?.distancesKm, [])
        XCTAssertEqual(got.first?.pillText(now: now), "Sign-up open")
    }

    func testCountdown() {
        let tv = race("tough-viking-stadion-2027")
        XCTAssertEqual(tv.daysToGo(now: now), 206)   // across the end of summer time on 25 Oct
        XCTAssertEqual(tv.countdownText(now: now), "206 days to go")
        XCTAssertEqual(tv.countdownShort(now: now), "206 days")
        let hyrox = race("hyrox-stockholm-2026")
        XCTAssertEqual(hyrox.daysToGo(day: "2026-12-12", now: now), 52)
        XCTAssertEqual(hyrox.countdownText(now: at("2026-12-09T10:00:00Z")), "Tomorrow")
        XCTAssertEqual(hyrox.countdownText(now: at("2026-12-11T10:00:00Z")), "Race day")   // second of four days
        XCTAssertFalse(hyrox.isPast(now: at("2026-12-13T22:30:00Z")))                     // 23:30 on the last day
        XCTAssertTrue(hyrox.isPast(now: at("2026-12-13T23:30:00Z")))                      // 00:30 the day after
        XCTAssertEqual(hyrox.countdownText(now: at("2026-12-14T10:00:00Z")), "Done")
        XCTAssertEqual(hyrox.countdownText(day: "2026-12-12", now: at("2026-12-11T10:00:00Z")), "Tomorrow")
        XCTAssertEqual(hyrox.days, ["2026-12-10", "2026-12-11", "2026-12-12", "2026-12-13"])
    }

    func testPriceSteps() {
        let tv = race("tough-viking-stadion-2027")
        XCTAssertEqual(tv.currentStep(now: now)?.amount, 750)
        XCTAssertEqual(tv.nextStep(now: now)?.amount, 775)
        XCTAssertEqual(tv.nextPriceChange(now: now), "2026-11-01")
        XCTAssertEqual(tv.pillText(now: now), "750 SEK until 31 Oct")
        XCTAssertEqual(tv.pillText(now: at("2026-11-02T10:00:00Z")), "775 SEK")
        XCTAssertNil(tv.nextStep(now: at("2026-11-02T10:00:00Z")))
        XCTAssertNil(tv.nextPriceChange(now: at("2026-11-02T10:00:00Z")))
        // Only an end day known: the change is the day after it.
        XCTAssertEqual(race("bergen-city-marathon-2027").nextPriceChange(now: now), "2027-02-01")
        XCTAssertEqual(race("vasaloppet-2027").pillText(now: now), "2,685 SEK until 5 Nov")
        XCTAssertEqual(race("vasaloppet-2027").pillText(now: at("2026-11-06T10:00:00Z")), "2,985 SEK")
        XCTAssertEqual(race("hyrox-stockholm-2026").pillText(now: now), "From 1,470 SEK")
        XCTAssertEqual(race("holmenkollstafetten-2027").pillText(now: now), "4,700 NOK per team")
        XCTAssertEqual(race("oslo-maraton-2027").pillText(now: now), "Sign-up open")
    }

    func testStatusTexts() {
        XCTAssertEqual(race("goteborgsvarvet-2027").pillText(now: now), "Sold out")
        XCTAssertEqual(race("copenhagen-marathon-2027").pillText(now: now), "Lottery")
        XCTAssertEqual(race("stockholm-marathon-2027").pillText(now: now), "Check site")
        let vr = race("vatternrundan-2027")
        XCTAssertEqual(vr.pillText(now: now), "Opens 25 Nov")
        XCTAssertEqual(vr.statusText(now: now), "Sign-up opens Wed 25 Nov")
        XCTAssertEqual(vr.pillText(now: at("2026-11-25T10:00:00Z")), "Opens today")
        XCTAssertEqual(vr.statusText(now: at("2026-11-25T10:00:00Z")), "Sign-up opens today")
        XCTAssertEqual(vr.pillText(now: at("2026-11-26T10:00:00Z")), "Check site")
        XCTAssertEqual(race("midnattsloppet-stockholm-2027").statusText(now: now), "Sign-up opens Sun 1 Nov")
        XCTAssertEqual(race("tough-viking-stadion-2027").signupLine(now: now), "Sign-up on RaceID · checked 21 Oct")
        XCTAssertEqual(race("vasaloppet-2027").signupLine(now: now), "Sign-up on vasaloppet.se · checked 21 Oct")
        XCTAssertEqual(race("vasaloppet-2027").signupLine(now: at("2027-01-05T10:00:00Z")), "Sign-up on vasaloppet.se · checked 21 Oct 2026")
    }

    func testLabelsAndFormatting() {
        XCTAssertEqual(RaceMoney.grouped(2685), "2,685")
        XCTAssertEqual(RaceMoney.grouped(999), "999")
        XCTAssertEqual(RaceMoney.grouped(1_234_567), "1,234,567")
        XCTAssertEqual(race("hyrox-stockholm-2026").kindLabel, "HYROX · Solna")
        XCTAssertEqual(race("vasaloppet-2027").kindLabel, "Ski · Klassiker")
        XCTAssertEqual(race("hyrox-stockholm-2026").dateText(), "Thu 10 – Sun 13 Dec 2026")
        XCTAssertEqual(race("hyrox-stockholm-2026").dateText(day: "2026-12-12"), "Sat 12 Dec 2026")
        XCTAssertEqual(race("tough-viking-stadion-2027").longDateText(), "Saturday 15 May 2027")
        XCTAssertEqual(race("tough-viking-stadion-2027").factsLine, "8 km · solo, duo, trio or team")
        XCTAssertEqual(race("hyrox-stockholm-2026").placeLine, "Strawberry Arena | Solna")
        XCTAssertEqual(race("vasaloppet-2027").placeLine, "Sälen to Mora")   // the venue already names the city
        XCTAssertEqual(race("bergen-city-marathon-2027").distanceText, "42.2 / 21.1 / 5 km")
        XCTAssertEqual(race("stockholm-marathon-2027").distanceText, "42.195 km")
        XCTAssertEqual(race("tough-viking-stadion-2027").host, "toughviking.se")
        XCTAssertEqual(Races.webURL("toughviking.se")?.absoluteString, "https://toughviking.se")
        XCTAssertEqual(Races.webURL(" https://example.org/race ")?.absoluteString, "https://example.org/race")
        XCTAssertNil(Races.webURL("not a link"))
        XCTAssertNil(Races.webURL("localhost"))
    }

    func testMonthGroupsAndFilters() {
        let groups = Races.byMonth(catalog)
        XCTAssertEqual(groups.map(\.title), ["December 2026", "March 2027", "April 2027", "May 2027", "June 2027", "July 2027", "August 2027", "September 2027"])
        XCTAssertEqual(groups.map(\.races.count), [1, 3, 2, 7, 3, 2, 9, 5])
        XCTAssertEqual(Races.filter(catalog, types: [.hyrox], now: now).count, 2)
        XCTAssertEqual(Races.filter(catalog, types: [.obstacle], now: now).count, 7)
        XCTAssertEqual(Races.filter(catalog, countries: ["SE"], now: now).count, 19)
        XCTAssertEqual(Races.filter(catalog, countries: ["NO", "DK"], now: now).count, 13)
        XCTAssertEqual(Races.filter(catalog, query: "gothenburg", now: now).count, 4)
        XCTAssertEqual(Races.filter(catalog, query: "GOTEBORG", now: now).count, 4)   // diacritics and case ignored
        XCTAssertEqual(Races.filter(catalog, query: "21.1", now: now).count, 5)
        XCTAssertEqual(Races.filter(catalog, query: "klassiker", now: now).count, 4)
        XCTAssertEqual(Races.filter(catalog, query: "ski mora", now: now).map(\.id), ["vasaloppet-2027"])
        // Past races drop out unless asked for.
        let january = at("2027-01-10T10:00:00Z")
        XCTAssertEqual(Races.filter(catalog, now: january).count, 31)
        XCTAssertEqual(Races.filter(catalog, includePast: true, now: january).count, 32)
    }

    func testMyRacesResolvePersistAndSort() throws {
        let hyrox = race("hyrox-stockholm-2026"), tv = race("tough-viking-stadion-2027")
        var custom = MyRace(name: "Lidingö Ultra", date: "2027-04-10", city: "Lidingö", url: "https://example.org", type: .running)
        custom.note = "50 km"
        let mine = [MyRace(race: tv), custom, MyRace(race: hyrox, day: "2026-12-12", note: "Doubles Open")]
        let entries = MyRaces.entries(mine, catalog: catalog)
        XCTAssertEqual(MyRaces.upcoming(entries, now: now).map(\.race.name), ["HYROX Stockholm", "Lidingö Ultra", "Tough Viking Stockholms Stadion"])
        XCTAssertEqual(MyRaces.upcoming(entries, now: now).first?.whenLine, "Sat 12 Dec · Doubles Open")
        let c = custom.resolved(in: catalog)
        XCTAssertTrue(c.isCustom)
        XCTAssertEqual(c.id, custom.key)
        XCTAssertNil(c.statusText(now: now))
        XCTAssertEqual(c.pillText(now: now), "")
        // A catalog race that left the catalog still shows what was saved.
        let gone = MyRace(race: tv).resolved(in: [])
        XCTAssertEqual(gone.name, tv.name)
        XCTAssertEqual(gone.checkedOn, "")
        // After the race: in Done, out of upcoming.
        let later = at("2026-12-14T10:00:00Z")
        XCTAssertEqual(MyRaces.past(entries, now: later).map(\.race.name), ["HYROX Stockholm"])

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("races-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        MyRaces.save(mine, to: url)
        XCTAssertEqual(MyRaces.load(from: url), mine)
        // One entry that can't be read doesn't lose the others; a file that can't be read at all is kept aside.
        try Data(#"[{"raceId":"a","name":"A","date":"2027-03-07"},{"name":42},{"raceId":"b","name":"B","date":"2027-04-01"}]"#.utf8).write(to: url)
        XCTAssertEqual(MyRaces.load(from: url).map(\.raceId), ["a", "b"])
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(MyRaces.load(from: url), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + ".unreadable"))
        try? FileManager.default.removeItem(atPath: url.path + ".unreadable")
        // Older files without the newer fields still load.
        try Data(#"[{"raceId":"vasaloppet-2027","name":"Vasaloppet","date":"2027-03-07"}]"#.utf8).write(to: url)
        let old = MyRaces.load(from: url)
        XCTAssertEqual(old.first?.raceId, "vasaloppet-2027")
        XCTAssertEqual(old.first?.remindPrice, false)
        XCTAssertEqual(old.first?.type, .running)
    }

    func testHint() {
        let tv = MyRaceEntry(mine: MyRace(race: race("tough-viking-stadion-2027"), remindPrice: true), race: race("tough-viking-stadion-2027"))
        XCTAssertEqual(tv.hint(now: now), "775 SEK from 1 Nov · reminder on")
        let mid = MyRaceEntry(mine: MyRace(race: race("midnattsloppet-stockholm-2027"), remindSignup: true), race: race("midnattsloppet-stockholm-2027"))
        XCTAssertEqual(mid.hint(now: now), "Sign-up opens 1 Nov · reminder on")
        let gbg = MyRaceEntry(mine: MyRace(race: race("goteborgsvarvet-2027")), race: race("goteborgsvarvet-2027"))
        XCTAssertEqual(gbg.hint(now: now), "Sold out")
    }

    func testReminderPlan() {
        let mine = [MyRace(race: race("tough-viking-stadion-2027"), remindPrice: true),
                    MyRace(race: race("vatternrundan-2027"), remindSignup: true),
                    MyRace(race: race("midnattsloppet-stockholm-2027"), remindSignup: true, remindPrice: true),
                    MyRace(race: race("vasaloppet-2027")),
                    MyRace(name: "Own race", date: "2027-01-01")]
        let p = RaceReminders.plan(mine, catalog: catalog, now: now)
        XCTAssertEqual(p.map(\.id), ["race-reminder-price-tough-viking-stadion-2027", "race-reminder-signup-midnattsloppet-stockholm-2027",
                                     "race-reminder-signup-vatternrundan-2027"])
        // 09:00 in Stockholm (winter time, UTC+1).
        XCTAssertEqual(p.map(\.fire), [at("2026-10-31T08:00:00Z"), at("2026-11-01T08:00:00Z"), at("2026-11-25T08:00:00Z")])
        XCTAssertEqual(p[0].body, "Tough Viking Stockholms Stadion: 750 SEK until today, 775 SEK from tomorrow. Sign up on toughviking.se.")
        XCTAssertEqual(p[0].title, "Price goes up tomorrow")
        XCTAssertEqual(p[2].title, "Sign-up opens today")
        XCTAssertEqual(p[0].raceId, "tough-viking-stadion-2027")
        // A sync early on the opening day keeps that morning's reminder.
        XCTAssertTrue(RaceReminders.plan(mine, catalog: catalog, now: at("2026-11-25T06:00:00Z")).contains { $0.id == "race-reminder-signup-vatternrundan-2027" })
        // A reminder whose moment has passed is dropped.
        XCTAssertFalse(RaceReminders.plan(mine, catalog: catalog, now: at("2026-10-31T09:30:00Z")).contains { $0.id.hasSuffix("tough-viking-stadion-2027") })
        // Only an end day known: the last day at that price.
        let bergen = RaceReminders.plan([MyRace(race: race("bergen-city-marathon-2027"), remindPrice: true)], catalog: catalog, now: now)
        XCTAssertEqual(bergen.first?.fire, at("2027-01-31T08:00:00Z"))
        XCTAssertEqual(bergen.first?.body, "Bergen City Marathon: today is the last day for 900 NOK. Sign up on bergencitymarathon.no.")
    }

    func testRaceCalendarEvent() throws {
        let hyrox = race("hyrox-stockholm-2026")
        let one = try XCTUnwrap(CalendarEvent(race: hyrox, day: "2026-12-12"))
        XCTAssertTrue(one.allDay)
        XCTAssertTrue(one.ics.contains("DTSTART;VALUE=DATE:20261212\r\n"))
        XCTAssertTrue(one.ics.contains("DTEND;VALUE=DATE:20261213\r\n"))
        XCTAssertTrue(one.ics.contains("TRIGGER:-PT360M"))
        XCTAssertTrue(one.ics.contains("UID:race-hyrox-stockholm-2026@bruce.unofficial"))
        XCTAssertTrue(one.ics.contains("LOCATION:Strawberry Arena\\, Solna"))
        let all = try XCTUnwrap(CalendarEvent(race: hyrox))
        XCTAssertTrue(all.ics.contains("DTSTART;VALUE=DATE:20261210\r\n"))
        XCTAssertTrue(all.ics.contains("DTEND;VALUE=DATE:20261214\r\n"))
        XCTAssertEqual(all.fileName, "hyrox-stockholm-2026-12-10.ics")
        // EventKit gets the same calendar days in the device's time zone, ending on the last day.
        let range = all.deviceAllDayRange
        XCTAssertEqual(Calendar.current.dateComponents([.year, .month, .day], from: range.start), DateComponents(year: 2026, month: 12, day: 10))
        XCTAssertEqual(Calendar.current.dateComponents([.year, .month, .day], from: range.end), DateComponents(year: 2026, month: 12, day: 13))
    }
}
