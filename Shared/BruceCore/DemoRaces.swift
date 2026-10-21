import Foundation

// Demo mode's races (Races.swift): a slice of the real catalog in docs/app/races.json, as checked on 21 Oct 2026, and
// three of them in My races (HYROX Stockholm on the Saturday in doubles, a price reminder, a sign-up reminder).
// RacesTests checks that every demo race matches the catalog file.

extension Race {
    static let demo: [Race] = (try? RaceCatalog.decode(Data(demoJSON.utf8))) ?? []

    private static let demoJSON = #"""
{"races": [
  {"id":"hyrox-stockholm-2026","name":"HYROX Stockholm","type":"hyrox","date":"2026-12-10","endDate":"2026-12-13","city":"Solna","country":"SE","venue":"Strawberry Arena","distancesKm":[],"signupUrl":"https://hyrox.com/find-my-race/","platform":"vivenu","priceNote":"Single 1,530 SEK, doubles 1,470 SEK per person","priceSteps":[{"amount":1470,"currency":"SEK","lowest":true}],"status":"open","checkedOn":"2026-10-21"},
  {"id":"vasaloppet-2027","name":"Vasaloppet","type":"endurance","sport":"ski","date":"2027-03-07","city":"Mora","country":"SE","venue":"Sälen to Mora","distancesKm":[90],"signupUrl":"https://www.vasaloppet.se/en/ski/vasaloppet/","priceNote":"2,685 SEK until 5 Nov, then 2,985 SEK as a late entry","priceSteps":[{"until":"2026-11-05","amount":2685,"currency":"SEK"},{"from":"2026-11-06","amount":2985,"currency":"SEK"}],"status":"open","klassiker":true,"checkedOn":"2026-10-21"},
  {"id":"hyrox-copenhagen-2027","name":"HYROX Copenhagen","type":"hyrox","date":"2027-03-25","endDate":"2027-03-28","city":"Copenhagen","country":"DK","venue":"Bella Center","distancesKm":[],"signupUrl":"https://hyrox.com/find-my-race/","platform":"vivenu","priceNote":"Single 1,045 DKK","priceSteps":[{"amount":1045,"currency":"DKK","lowest":true}],"status":"open","checkedOn":"2026-10-21"},
  {"id":"tough-viking-goteborg-2027","name":"Tough Viking Göteborg","type":"obstacle","date":"2027-04-24","city":"Gothenburg","country":"SE","venue":"Slottsskogen","distancesKm":[8],"signupUrl":"https://www.toughviking.se/","platform":"RaceID","priceNote":"750 SEK now","priceSteps":[{"amount":750,"currency":"SEK"}],"status":"open","checkedOn":"2026-10-21"},
  {"id":"tough-viking-stadion-2027","name":"Tough Viking Stockholms Stadion","type":"obstacle","date":"2027-05-15","city":"Stockholm","country":"SE","venue":"Stockholms Stadion","distancesKm":[8],"format":"solo, duo, trio or team","signupUrl":"https://www.toughviking.se/","platform":"RaceID","priceNote":"750 SEK until 31 Oct, then 775 SEK","priceSteps":[{"until":"2026-10-31","amount":750,"currency":"SEK"},{"from":"2026-11-01","amount":775,"currency":"SEK"}],"status":"open","checkedOn":"2026-10-21"},
  {"id":"goteborgsvarvet-2027","name":"Göteborgsvarvet","type":"running","date":"2027-05-22","city":"Gothenburg","country":"SE","distancesKm":[21.1],"signupUrl":"https://www.goteborgsvarvet.se/en/news/goteborgsvarvet-2027-is-sold-out","platform":"njuko","priceNote":"Sold out. There is a waitlist with entry transfers.","status":"soldOut","checkedOn":"2026-10-21"},
  {"id":"stockholm-marathon-2027","name":"Stockholm Marathon","type":"running","date":"2027-05-29","city":"Stockholm","country":"SE","distancesKm":[42.195],"signupUrl":"https://stockholmmarathon.se/eng/eng-lopare/","platform":"Haku","priceNote":"1,295–1,995 SEK in four steps","status":"checkSite","checkedOn":"2026-10-21"},
  {"id":"vatternrundan-2027","name":"Vätternrundan","type":"endurance","sport":"bike","date":"2027-06-18","endDate":"2027-06-19","city":"Motala","country":"SE","distancesKm":[315],"signupUrl":"https://vatternrundan.se/en/races/vatternrundan-315km","priceNote":"2,100 SEK. Entries open at 19:00 on 25 Nov.","priceSteps":[{"amount":2100,"currency":"SEK"}],"status":"opensSoon","opensOn":"2026-11-25","klassiker":true,"checkedOn":"2026-10-21"},
  {"id":"vansbrosimningen-2027","name":"Vansbrosimningen","type":"endurance","sport":"swim","date":"2027-07-10","city":"Vansbro","country":"SE","distancesKm":[3],"signupUrl":"https://www.vansbrosimningen.se/","priceNote":"1,345–1,545 SEK","priceSteps":[{"amount":1345,"currency":"SEK","lowest":true}],"status":"open","klassiker":true,"checkedOn":"2026-10-21"},
  {"id":"ironman-703-jonkoping-2027","name":"IRONMAN 70.3 Jönköping","type":"triathlon","date":"2027-07-11","city":"Jönköping","country":"SE","distancesKm":[],"signupUrl":"https://www.ironman.com/races/im703-jonkoping","priceNote":"Sold out","status":"soldOut","checkedOn":"2026-10-21"},
  {"id":"midnattsloppet-stockholm-2027","name":"Midnattsloppet Stockholm","type":"running","date":"2027-08-14","city":"Stockholm","country":"SE","distancesKm":[5,10],"format":"evening run","signupUrl":"https://midnattsloppet.com/en/start-fee/","priceNote":"2027 prices come with the sign-up. The first price step was 499 SEK in 2026.","status":"opensSoon","opensOn":"2026-11-01","checkedOn":"2026-10-21"},
  {"id":"stockholm-half-marathon-2027","name":"Stockholm Half Marathon","type":"running","date":"2027-08-21","city":"Stockholm","country":"SE","distancesKm":[21.1],"signupUrl":"https://www.stockholmhalfmarathon.se/","platform":"Haku","priceNote":"1,045 SEK until 14 Feb","priceSteps":[{"until":"2027-02-14","amount":1045,"currency":"SEK"}],"status":"open","checkedOn":"2026-10-21"},
  {"id":"oslo-maraton-2027","name":"Oslo Maraton","type":"running","date":"2027-09-18","city":"Oslo","country":"NO","distancesKm":[42.195,21.1,10],"signupUrl":"https://www.oslomaraton.no/","platform":"Haku","priceNote":"1,350 NOK for the marathon","status":"open","checkedOn":"2026-10-21"},
  {"id":"cph-half-2027","name":"CPH Half","type":"running","date":"2027-09-19","city":"Copenhagen","country":"DK","distancesKm":[21.1],"signupUrl":"https://cphhalf.dk/en/lottery/","priceNote":"795 DKK. The lottery is done; about 188,000 entered the draw.","priceSteps":[{"amount":795,"currency":"DKK"}],"status":"lottery","checkedOn":"2026-10-21"},
  {"id":"lidingoloppet-2027","name":"Lidingöloppet","type":"running","date":"2027-09-25","city":"Lidingö","country":"SE","distancesKm":[30],"format":"cross-country","signupUrl":"https://lidingoloppet.se/en/tcs-lidingoloppet/faq/registration-fees","priceNote":"2027 prices are not out yet. Entries cost 796–1,395 SEK in 2026.","status":"checkSite","klassiker":true,"checkedOn":"2026-10-21"}
]}
"""#
}

extension AppModel {
    func loadDemoRaces() {
        races = Race.demo
        func pick(_ id: String) -> Race? { races.first { $0.id == id } }
        myRaces = [
            pick("hyrox-stockholm-2026").map { MyRace(race: $0, day: "2026-12-12", note: "Doubles Open") },
            pick("tough-viking-stadion-2027").map { MyRace(race: $0, remindPrice: true) },
            pick("midnattsloppet-stockholm-2027").map { MyRace(race: $0, note: "10 km", remindSignup: true) },
        ].compactMap { $0 }
    }
}
