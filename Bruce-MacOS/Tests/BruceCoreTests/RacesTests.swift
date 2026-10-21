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

    func testFormatsStartWaveAndArrival() throws {
        var r = race("hyrox-stockholm-2026")
        r.arriveMinutesBefore = 90
        r.formats = [RaceFormat(code: "singles", title: "Singles", teamSize: 1, priceSteps: [PriceStep(amount: 1530, currency: "SEK")], note: "Open or Pro"),
                     RaceFormat(code: "doubles", title: "Doubles", teamSize: 2, priceSteps: [PriceStep(amount: 1470, currency: "SEK", per: "person")]),
                     RaceFormat(code: "relay", title: "Relay", teamSize: 4)]
        XCTAssertTrue(r.hasFormats)
        XCTAssertFalse(race("vasaloppet-2027").hasFormats)
        XCTAssertEqual(r.format("doubles")?.title, "Doubles")
        XCTAssertNil(r.format("pro"))
        XCTAssertNil(r.format(nil))
        XCTAssertEqual(r.currentStep(for: r.format("doubles"), now: now)?.priceText, "1,470 SEK per person")
        XCTAssertEqual(r.currentStep(for: r.format("singles"), now: now)?.priceText, "1,530 SEK")
        // A format without fees of its own shows the race's.
        XCTAssertEqual(r.currentStep(for: r.format("relay"), now: now)?.priceText, "From 1,470 SEK")
        XCTAssertEqual(r.currentStep(for: nil, now: now)?.priceText, "From 1,470 SEK")
        XCTAssertEqual(r.format("singles")?.detail, "Open or Pro")
        XCTAssertEqual(r.format("doubles")?.detail, "2 people")
        XCTAssertEqual(RaceFormat(code: "x", title: "X", distanceKm: 15).detail, "15 km")
        XCTAssertNil(RaceFormat(code: "x", title: "X").detail)
        // Start waves as typed.
        XCTAssertEqual(RaceClock.minutes("14:20"), 860)
        XCTAssertEqual(RaceClock.normalized("1420"), "14:20")
        XCTAssertEqual(RaceClock.normalized("9.05"), "09:05")
        XCTAssertEqual(RaceClock.normalized(" 7:30 "), "07:30")
        XCTAssertNil(RaceClock.normalized("wave 3"))
        XCTAssertNil(RaceClock.normalized("25:00"))
        XCTAssertNil(RaceClock.normalized("14:60"))
        XCTAssertNil(RaceClock.normalized(""))
        XCTAssertEqual(RaceClock.arriveBy(wave: "14:20", minutesBefore: 90), "12:50")
        XCTAssertEqual(RaceClock.arriveBy(wave: "00:30", minutesBefore: 90), "00:00")
        XCTAssertNil(RaceClock.arriveBy(wave: "wave 3", minutesBefore: 90))
        XCTAssertEqual(r.arriveMinutes, 90)
        XCTAssertEqual(race("vasaloppet-2027").arriveMinutes, 60)
        XCTAssertEqual(RaceClock.date("2026-12-12", "14:20"), at("2026-12-12T13:20:00Z"))
        var mine = MyRace(race: r, day: "2026-12-12", note: "Open")
        mine.format = "doubles"; mine.wave = "1420"; mine.bib = "1427"
        let e = MyRaces.entries([mine], catalog: [r])[0]
        XCTAssertEqual(e.startText, "Doubles · Open")
        XCTAssertEqual(e.whenLine, "Sat 12 Dec · Doubles · Open")
        XCTAssertEqual(e.wave, "14:20")
        XCTAssertEqual(e.arriveBy, "12:50")
        XCTAssertTrue(e.isRaceDay(now: at("2026-12-12T08:00:00Z")))
        XCTAssertFalse(e.isRaceDay(now: now))
        // A format the catalog dropped: the note alone; nothing picked: nothing.
        mine.format = "pro"
        XCTAssertEqual(MyRaces.entries([mine], catalog: [r])[0].startText, "Open")
        XCTAssertNil(MyRaces.entries([MyRace(race: r)], catalog: [r])[0].startText)
        // The new fields survive a save and load; an older file without them still loads.
        let data = try JSONEncoder().encode([mine])
        let back = try JSONDecoder().decode([MyRace].self, from: data)[0]
        XCTAssertEqual(back.wave, "1420"); XCTAssertEqual(back.bib, "1427"); XCTAssertEqual(back.format, "pro")
        let old = try JSONDecoder().decode(MyRace.self, from: Data(#"{"name":"X","date":"2027-01-01"}"#.utf8))
        XCTAssertNil(old.format); XCTAssertNil(old.wave); XCTAssertFalse(old.remindWave)
        // The published catalog has the HYROX Stockholm formats and the rules that matter; formats this version can't
        // read are dropped one by one.
        let pub = try XCTUnwrap(published.first { $0.id == "hyrox-stockholm-2026" })
        XCTAssertEqual(pub.formats?.map(\.code), ["singles", "doubles", "relay", "adaptive"])
        XCTAssertEqual(pub.arriveMinutesBefore, 90)
        XCTAssertTrue(pub.changeRule?.contains("Flex") == true)
        XCTAssertTrue(published.contains { $0.id == "premiarhalvan-2027" })
        let lossy = try RaceCatalog.decode(Data(#"{"races":[{"id":"a-2027","name":"A","type":"running","date":"2027-05-01","signupUrl":"https://a.example","status":"open","formats":[{"code":"a","title":"A"},{"code":"","title":"B"},{"title":"C"}],"arriveMinutesBefore":-5}]}"#.utf8))
        XCTAssertEqual(lossy[0].formats?.map(\.code), ["a"])
        XCTAssertNil(lossy[0].arriveMinutesBefore)
    }

    func testUpcomingRacesOnHome() {
        let mine = [MyRace(race: race("hyrox-stockholm-2026"))]
        XCTAssertEqual(Races.upcomingOnHome(catalog, mine: mine, country: "SE", now: now, limit: 5).map(\.id),
                       ["vasaloppet-2027", "tough-viking-goteborg-2027", "tough-viking-stadion-2027", "toughest-malmo-2027", "toughest-stockholm-2027"])
        XCTAssertEqual(Races.upcomingOnHome(catalog, mine: mine, country: "NO", now: now, limit: 3).map(\.id), ["birkebeinerrennet-2027", "bergen-city-marathon-2027", "holmenkollstafetten-2027"])
        XCTAssertEqual(Races.upcomingOnHome(catalog, mine: [], now: now, limit: 4).map(\.id), ["hyrox-stockholm-2026", "vasaloppet-2027", "birkebeinerrennet-2027", "hyrox-copenhagen-2027"])
        // A country with no races: by date.
        XCTAssertEqual(Races.upcomingOnHome(catalog, mine: mine, country: "FI", now: now, limit: 3).map(\.id), ["vasaloppet-2027", "birkebeinerrennet-2027", "hyrox-copenhagen-2027"])
        XCTAssertEqual(Races.upcomingOnHome(catalog, mine: [], now: now).count, 8)
        XCTAssertTrue(Races.upcomingOnHome(catalog, mine: [], now: now, limit: 99).allSatisfy { $0.status == .open || $0.status == .opensSoon })
        XCTAssertEqual(Races.upcomingOnHome(catalog, mine: [], now: at("2027-12-01T10:00:00Z")).count, 0)
        XCTAssertEqual(Races.homePill(race("tough-viking-stadion-2027"), now: now), "750 → 775 SEK on 1 Nov")
        XCTAssertEqual(Races.homePill(race("vasaloppet-2027"), now: now), "2,685 → 2,985 SEK on 6 Nov")
        XCTAssertEqual(Races.homePill(race("vatternrundan-2027"), now: now), "Opens 25 Nov")
        XCTAssertEqual(Races.homePill(race("hyrox-stockholm-2026"), now: now), "From 1,470 SEK")
        XCTAssertEqual(Races.homePill(race("bergen-city-marathon-2027"), now: now), "900 NOK until 31 Jan")
    }

    func testStartWaveReminder() {
        var m = MyRace(race: race("hyrox-stockholm-2026"), day: "2026-12-12")
        m.remindWave = true
        let p = RaceReminders.plan([m], catalog: catalog, now: now)
        XCTAssertEqual(p.map(\.id), ["race-reminder-wave-hyrox-stockholm-2026"])
        // 18:00 in Stockholm three days before (winter time, UTC+1).
        XCTAssertEqual(p.first?.fire, at("2026-12-09T17:00:00Z"))
        XCTAssertEqual(p.first?.title, "Add your start wave: HYROX Stockholm")
        XCTAssertTrue(p.first?.body.hasPrefix("Saturday is race day.") == true)
        // Once the wave is in, there is nothing to remind about; the switch stays for a wave typed by mistake.
        m.wave = "14:20"
        XCTAssertTrue(RaceReminders.plan([m], catalog: catalog, now: now).isEmpty)
        m.wave = "later"
        XCTAssertEqual(RaceReminders.plan([m], catalog: catalog, now: now).count, 1)
        // The server never sends this one: it stays local even for races the server reminds about.
        XCTAssertEqual(RaceReminders.plan([m], catalog: catalog, now: now, serverIds: [m.key]).count, 1)
    }

    func testRaceDayTicket() throws {
        var m = MyRace(race: race("hyrox-stockholm-2026"), day: "2026-12-12", note: "Open")
        m.format = "doubles"; m.wave = "14:20"; m.bib = "1427"
        var r = race("hyrox-stockholm-2026"); r.arriveMinutesBefore = 90
        r.formats = [RaceFormat(code: "doubles", title: "Doubles")]
        let entries = MyRaces.entries([m, MyRace(race: race("tough-viking-stadion-2027"))], catalog: [r, race("tough-viking-stadion-2027")])
        // Race day, from midnight; the evening before from 18:00; nothing earlier.
        let t = try XCTUnwrap(MyRaces.ticket(entries, now: at("2026-12-12T07:00:00Z")))
        XCTAssertEqual(t.title, "Race day · today")
        XCTAssertEqual(t.bib, "1427"); XCTAssertEqual(t.wave, "14:20"); XCTAssertEqual(t.arriveBy, "12:50")
        XCTAssertEqual(t.entry.startText, "Doubles · Open")
        XCTAssertEqual(t.mapsURL?.absoluteString, "https://maps.apple.com/?q=Strawberry%20Arena,%20Solna")
        XCTAssertEqual(MyRaces.ticket(entries, now: at("2026-12-11T17:30:00Z"))?.title, "Race day · tomorrow")   // 18:30 CET
        XCTAssertNil(MyRaces.ticket(entries, now: at("2026-12-11T12:00:00Z")))
        XCTAssertNil(MyRaces.ticket(entries, now: now))
        // Without a wave the cells say so, and the card still shows.
        m.wave = nil; m.bib = nil
        let bare = try XCTUnwrap(MyRaces.ticket(MyRaces.entries([m], catalog: [r]), now: at("2026-12-12T07:00:00Z")))
        XCTAssertNil(bare.wave); XCTAssertNil(bare.arriveBy); XCTAssertNil(bare.bib)
        XCTAssertNil(RaceDayTicket(entry: MyRaces.entries([MyRace(name: "Own", date: "2027-01-01")], catalog: [])[0], tomorrow: false).mapsURL)
    }

    @MainActor func testPriceReminderGoesToTheServer() throws {
        // The device sends the day the price changes and the words; the server has no catalog.
        let tv = race("tough-viking-stadion-2027")
        let p = try XCTUnwrap(RaceReminders.priceReminder(tv, now: now))
        XCTAssertEqual(p.changeOn, "2026-11-01")
        XCTAssertEqual(p.fire, at("2026-10-31T08:00:00Z"))
        XCTAssertEqual(p.body, "Tough Viking Stockholms Stadion: 750 SEK until today, 775 SEK from tomorrow. Sign up on toughviking.se.")
        XCTAssertNil(RaceReminders.priceReminder(race("stockholm-marathon-2027"), now: now), "no steps known")
        XCTAssertNil(RaceReminders.priceReminder(race("vatternrundan-2027"), now: now), "not open yet")
        let entries = MyRaces.entries([MyRace(race: tv, remindPrice: true), MyRace(race: race("vasaloppet-2027"))], catalog: catalog)
        let body = AppModel.raceSyncBody(MyRaces.upcoming(entries, now: now), now: now) { _ in nil }
        XCTAssertEqual(body.map { $0["id"] as? String }, ["tough-viking-stadion-2027"])
        XCTAssertEqual(body[0]["remindPrice"] as? Bool, true)
        XCTAssertEqual(body[0]["priceAt"] as? String, "2026-11-01")
        XCTAssertEqual(body[0]["priceBody"] as? String, p.body)
        XCTAssertEqual(body[0]["remindWeek"] as? Bool, false)
        // Once the server has the race, the device leaves its own price notification out.
        let mine = [MyRace(race: tv, remindPrice: true)]
        XCTAssertEqual(RaceReminders.plan(mine, catalog: catalog, now: now).count, 1)
        XCTAssertEqual(RaceReminders.plan(mine, catalog: catalog, now: now, serverIds: ["tough-viking-stadion-2027"]).count, 0)
    }

    func testResultsRegisterLinkFeedAndClubs() throws {
        // Results: times in and out, the summary, HYROX's split rows, a file round trip.
        XCTAssertEqual(RaceResult.timeText(4132), "1:08:52"); XCTAssertEqual(RaceResult.timeText(2290), "38:10"); XCTAssertEqual(RaceResult.timeText(0), "0:00")
        XCTAssertEqual(RaceResult.seconds("1:08:52"), 4132); XCTAssertEqual(RaceResult.seconds("68:52"), 4132); XCTAssertEqual(RaceResult.seconds("38:10"), 2290)
        XCTAssertEqual(RaceResult.seconds("1.08.52"), 4132); XCTAssertEqual(RaceResult.seconds("1h 08m"), 4080); XCTAssertEqual(RaceResult.seconds("45m"), 2700)
        XCTAssertNil(RaceResult.seconds("fast")); XCTAssertNil(RaceResult.seconds("1:60")); XCTAssertNil(RaceResult.seconds("")); XCTAssertNil(RaceResult.seconds("12"))
        let res = RaceResult(seconds: 4132, place: 212, field: 1040, splits: [RaceSplit(title: "SkiErg", seconds: 245)])
        XCTAssertEqual(res.summary, "1:08:52 · Place 212 of 1,040")
        XCTAssertEqual(RaceResult(seconds: 0, dnf: true).summary, "Did not finish")
        XCTAssertEqual(RaceResult(seconds: 2290).summary, "38:10")
        XCTAssertEqual(RaceResult.splitTemplate(.hyrox).count, 9); XCTAssertEqual(RaceResult.splitTemplate(.running), [])
        // The 2026 edition is in the published file, not the frozen fixture: the 2027 entry moved back a year.
        var mid = race("midnattsloppet-stockholm-2027"); mid.id = "midnattsloppet-stockholm-2026"; mid.date = "2026-08-15"
        var mine = MyRace(race: mid, note: "10 km"); mine.result = res
        let back = try JSONDecoder().decode(MyRace.self, from: JSONEncoder().encode(mine))
        XCTAssertEqual(back.result, res)
        // The register link: the race's page, with the affiliate code only when the catalog has one.
        var tv = race("tough-viking-stadion-2027")
        XCTAssertEqual(tv.registerURL, tv.url)
        tv.affiliate = RaceAffiliate(param: "ref", code: "bruce")
        XCTAssertEqual(tv.registerURL?.absoluteString, "https://www.toughviking.se/?ref=bruce")
        var lid = race("lidingoloppet-2027"); lid.affiliate = RaceAffiliate(param: "utm_source", code: "bruce")
        XCTAssertTrue(lid.registerURL!.absoluteString.hasSuffix("registration-fees?utm_source=bruce"))
        // The feed overlay: newer facts win, new races are added, the catalog is never shortened.
        var fresh = race("stockholm-marathon-2027"); fresh.checkedOn = "2026-11-01"; fresh.status = .open
        var stale = race("vasaloppet-2027"); stale.checkedOn = "2026-01-01"; stale.name = "Old"
        let new = Race(id: "example-run-2027", name: "Example Run", type: .running, date: "2027-06-05", city: "Stockholm", country: "SE",
                       signupUrl: "https://example.org", status: .open, checkedOn: "2026-10-21")
        let merged = RaceCatalog.merge(catalog, feed: [fresh, stale, new])
        XCTAssertEqual(merged.count, catalog.count + 1)
        XCTAssertEqual(merged.first { $0.id == "stockholm-marathon-2027" }?.status, .open)
        XCTAssertEqual(merged.first { $0.id == "vasaloppet-2027" }?.name, "Vasaloppet")
        XCTAssertEqual(merged.first { $0.id == "example-run-2027" }?.name, "Example Run")
        XCTAssertEqual(merged.map(\.date), merged.map(\.date).sorted())
        // Training clubs: read from the file (none in the published one yet), by race type.
        XCTAssertEqual(RaceCatalog.decodeClubs(Self.repoFile("docs/app/races.json")), [])
        let clubs = RaceCatalog.decodeClubs(Data(#"{"races":[],"trainingClubs":[{"studioId":9810,"name":"Box","badge":"HYROX Training Club","raceType":"hyrox"},{"studioId":1,"name":"Any","badge":"Club"},{"studioId":2,"name":"","badge":"X"}]}"#.utf8))
        XCTAssertEqual(clubs.map(\.studioId), [9810, 1])
        // The race as a workout for Apple Health: from the wave on the race day, as long as the time, outdoors.
        mine.wave = "21:40"
        let e = MyRaces.entries([mine, MyRace(race: tv)], catalog: catalog)
        let w = WorkoutExport.raceWorkouts(e, weightKg: 75, now: now)
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w[0].kind, .running); XCTAssertTrue(w[0].race); XCTAssertEqual(w[0].minutes, 68)
        XCTAssertEqual(w[0].start, at("2026-08-15T19:40:00Z")); XCTAssertEqual(w[0].title, "Midnattsloppet Stockholm · 10 km")
        XCTAssertTrue(w[0].visitId < 0); XCTAssertEqual(w[0].syncId, "bruce-race-\(-w[0].visitId)")
        XCTAssertEqual(WorkoutExport.raceId("midnattsloppet-stockholm-2026"), WorkoutExport.raceId("midnattsloppet-stockholm-2026"))
        XCTAssertNotEqual(WorkoutExport.raceId("a"), WorkoutExport.raceId("b"))
        XCTAssertEqual(WorkoutKind.forRace(.endurance, sport: .ski), .skiing); XCTAssertEqual(WorkoutKind.forRace(.hyrox, sport: nil), .hiit)
        mine.result = RaceResult(seconds: 0, dnf: true)
        XCTAssertTrue(WorkoutExport.raceWorkouts(MyRaces.entries([mine], catalog: catalog), weightKg: 75, now: now).isEmpty)
        // Wrapped's race chapter: this year's races that are over, with the result.
        mine.result = res
        let wr = Wrapped.races(MyRaces.entries([mine, MyRace(race: race("hyrox-stockholm-2026"), day: "2026-12-12")], catalog: catalog), now: now)
        XCTAssertEqual(wr.map(\.name), ["Midnattsloppet Stockholm"])
        XCTAssertEqual(wr[0].timeText, "1:08:52"); XCTAssertEqual(wr[0].placeText, "Place 212 of 1,040"); XCTAssertEqual(wr[0].kind, "Running · 10 km")
        var s = WrappedStats(year: 2026); s.visits = 5; s.races = wr
        XCTAssertTrue(s.cards.contains(.race))
        XCTAssertTrue(s.shareTiles.contains { $0.value == "1:08:52" })
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
