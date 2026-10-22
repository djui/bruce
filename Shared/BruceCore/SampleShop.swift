import Foundation

// Sample shop: while Settings › Show sample shop is on (it is, by default), a few clearly marked listings are laid over
// the real catalogue, so the shop can be looked at before any studio has approved one. They are made on this device from
// what the app has already loaded (the studios, the visit history, the favourites), sit on the member's own studios and
// go nowhere: Buy, Reserve, Notify me and Webshop only answer "Sample item, not for sale", and no tap counter and no
// notify call is sent. No name or picture carries a Bruce, Brüce, STC or Hyrox mark. The same rules live in
// docs/app/js/shop.js (`samplePicks`, `sampleCatalog`); ShopTests checks both against the same cases.

/// The studios the samples attach to (ids), nil when none fits: a yoga studio, an STC gym and a Hyrox studio.
struct SamplePicks: Equatable {
    var yoga: Int?
    var gym: Int?
    var hyrox: Int?
}

/// What the pick reads, taken from the model.
struct SampleInput {
    var studios: [BruceAPI.Studio] = []
    var cityId = 1
    /// Checked-in visits per studio id, and those to a Hyrox class.
    var visits: [Int: Int] = [:]
    var hyroxVisits: [Int: Int] = [:]
    /// Studios with a listed Hyrox class (the classes Explore has loaded).
    var hyroxClassStudios: Set<Int> = []
    var favourites: Set<Int> = []
    /// Metres from the member (or the city centre) per studio id.
    var distances: [Int: Double] = [:]
    /// Studios with a real storefront: they keep their own listings and get no samples.
    var listed: Set<Int> = []
    /// A category's title, for studios whose list entry carries only its id.
    var categoryTitle: (Int) -> String? = { _ in nil }
}

enum SampleShop {
    /// Every sample id starts with this, so nothing real can be mistaken for one (and the server is never told of one).
    static let idPrefix = "sample-"
    static func isSample(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    /// "STC Rosenlundsparken": the name starts with STC as a word.
    static func isSTC(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces).uppercased()
        guard n.hasPrefix("STC") else { return false }
        return n.dropFirst(3).first.map { !$0.isLetter } ?? true
    }

    /// Yoga: the yoga studio visited most, else a favourite one, else the nearest. STC: the same among STC studios. Hyrox:
    /// the studio whose Hyrox classes (or whose Hyrox category) were visited most, else a favourite, else the nearest
    /// that runs Hyrox. All in the member's city; ties go to the nearer studio, then the lower id.
    static func picks(_ i: SampleInput) -> SamplePicks {
        let city = i.studios.filter { ($0.cityId ?? i.cityId) == i.cityId && ($0.status == nil || $0.isLive) && !i.listed.contains($0.id) }
        func titles(_ s: BruceAPI.Studio) -> [String] {
            (s.studioCategories ?? []).compactMap { $0.category?.title ?? $0.categoryId.flatMap(i.categoryTitle) }.map { $0.lowercased() }
        }
        func has(_ s: BruceAPI.Studio, _ word: String) -> Bool { titles(s).contains { $0.contains(word) } }
        func near(_ a: BruceAPI.Studio, _ b: BruceAPI.Studio) -> Bool {
            let (da, db) = (i.distances[a.id] ?? .infinity, i.distances[b.id] ?? .infinity)
            return da != db ? da < db : a.id < b.id
        }
        func best(_ list: [BruceAPI.Studio], score: (BruceAPI.Studio) -> Int) -> Int? {
            let went = list.filter { score($0) > 0 }.sorted { score($0) != score($1) ? score($0) > score($1) : near($0, $1) }
            if let s = went.first { return s.id }
            if let s = list.filter({ i.favourites.contains($0.id) }).sorted(by: near).first { return s.id }
            return list.sorted(by: near).first?.id
        }
        let visited = { (s: BruceAPI.Studio) in i.visits[s.id] ?? 0 }
        return SamplePicks(
            yoga: best(city.filter { has($0, "yoga") }, score: visited),
            gym: best(city.filter { isSTC($0.name) }, score: visited),
            hyrox: best(city.filter { has($0, "hyrox") || i.hyroxClassStudios.contains($0.id) || (i.hyroxVisits[$0.id] ?? 0) > 0 },
                        score: { (i.hyroxVisits[$0.id] ?? 0) * 1000 + visited($0) }))
    }

    /// The sample catalogue for the picked studios, in kronor incl. VAT. The seller is the studio itself, under its own
    /// name; every storefront, product and drop carries `sample`. The race-day tee is open, 31 of 40 reserved.
    static func catalog(_ p: SamplePicks, studioName: (Int) -> String, city: String, now: Date = Date()) -> ShopCatalog {
        var c = ShopCatalog(city: city)
        func add(_ studio: Int, _ slug: String, _ title: String, _ kind: ProductKind, _ description: String, kr: Int, _ fulfilment: Fulfilment = .desk, sizes: [String] = []) {
            if !c.storefronts.contains(where: { $0.studioId == studio }) {
                c.storefronts.append(Storefront(studioId: studio, sellerName: studioName(studio), city: city, consentAt: "", sample: true))
            }
            c.products.append(Product(id: "\(idPrefix)\(studio)-\(slug)", studioId: studio, title: title, kind: kind, description: description, priceOre: kr * 100, fulfilment: fulfilment,
                                      variants: sizes.map { ProductVariant(id: $0.lowercased().replacingOccurrences(of: "/", with: "-"), label: $0) }, sample: true))
        }
        if let y = p.yoga {
            add(y, "cork-mat", "Cork yoga mat", .mat, "Natural cork on rubber · 183 × 61 cm · 4 mm", kr: 795, .link)
            add(y, "grip-socks", "Grip socks", .socks, "Cotton with silicone grip · 2-pack", kr: 149, sizes: ["S/M", "L/XL"])
            add(y, "mat-towel", "Mat towel", .towel, "Microfibre with grip dots · 183 × 63 cm", kr: 299)
        }
        if let g = p.gym {
            add(g, "gym-towel", "Gym towel", .towel, "Quick-dry microfibre · 50 × 100 cm", kr: 199)
            add(g, "shaker", "Shaker bottle", .other, "700 ml, leak-proof lid", kr: 129)
            add(g, "lifting-straps", "Lifting straps", .other, "Cotton with a padded wrist loop · pair", kr: 179)
        }
        if let h = p.hyrox {
            add(h, "race-day-tee", "Race-day tee", .apparel, "Organic cotton, printed in the EU · unisex", kr: 349, .pod, sizes: ["XS", "S", "M", "L", "XL"])
            add(h, "grip-gloves", "Grip gloves", .other, "Padded palm, open fingers · for pull-ups and wall balls", kr: 249)
            let ms = { (d: Date) in Int(d.timeIntervalSince1970 * 1000) }
            c.drops.append(Drop(id: "\(idPrefix)\(h)-race-day", studioId: h, productId: "\(idPrefix)\(h)-race-day-tee", title: "Race-day tee",
                                opensAt: ms(now.addingTimeInterval(-5 * 86_400)), closesAt: ms(now.addingTimeInterval(2 * 86_400 + 14 * 3600)),
                                minQty: 25, maxQty: 40, reserved: 31, pickupFrom: RaceDay.adding(12, to: RaceDay.today(now)), sample: true))
        }
        return c
    }
}

extension AppModel {
    /// What the apps show: the real catalogue with the sample listings after it (SampleShop.swift). nil until the real one
    /// is read and no sample applies.
    var shop: ShopCatalog? {
        guard let s = sampleShop else { return shopReal }
        return (shopReal ?? ShopCatalog(city: s.city)).overlaying(s)
    }

    /// The sample listings for this member, nil with the switch off or when no studio fits. Picked again when what the pick
    /// reads changes (studios, favourites, visits, loaded classes, position, the day), else kept.
    var sampleShop: ShopCatalog? {
        guard showSampleShop else { return nil }
        let key = sampleKey
        if let c = sampleCache, c.key == key { return c.value }
        let c = SampleShop.catalog(SampleShop.picks(sampleInput), studioName: studioName, city: city?.code ?? (cityId == 1 ? "STO" : ""))
        sampleCache = (key, c.isEmpty ? nil : c)
        return sampleCache?.value
    }

    /// The studios the samples sit on, for the tests and the demo screens.
    var samplePicks: SamplePicks { SampleShop.picks(sampleInput) }

    private var sampleKey: Int {
        var h = Hasher()
        h.combine(cityId); h.combine(studios.count); h.combine(categories.count); h.combine(favoriteIds.keys.sorted())
        h.combine(visitHistory?.count ?? -1); h.combine(visitHistory?.first?.id ?? 0); h.combine(pastBookings.count)
        h.combine(classesByDay.values.reduce(0) { $0 + $1.count }); h.combine(shopReal?.storefronts.map(\.studioId) ?? [])
        h.combine(Int(refLat * 100)); h.combine(Int(refLon * 100)); h.combine(Calendar.current.ordinality(of: .day, in: .era, for: Date()))
        return h.finalize()
    }

    private var sampleInput: SampleInput {
        let hyroxId = categories.first { ($0.title ?? "").lowercased().contains("hyrox") }?.id
        func isHyrox(_ title: String?, _ ids: [Int]) -> Bool { (title ?? "").lowercased().contains("hyrox") || (hyroxId.map(ids.contains) ?? false) }
        var visits: [Int: Int] = [:], hyrox: [Int: Int] = [:]
        // The full history once it is read; until then the recent check-ins.
        if let history = visitHistory {
            for v in VisitDedupe.unique(history) {
                guard let s = v.studioRef else { continue }
                visits[s, default: 0] += 1
                if isHyrox(v.visitClass?.title, v.categoryIds) { hyrox[s, default: 0] += 1 }
            }
        } else {
            for b in pastBookings {
                guard let s = b.studioId ?? b.class?.studioId else { continue }
                visits[s, default: 0] += 1
                if isHyrox(b.class?.title, (b.class?.classCategories ?? []).compactMap(\.categoryId)) { hyrox[s, default: 0] += 1 }
            }
        }
        let classes = classesByDay.values.joined().filter { isHyrox($0.title, ($0.classCategories ?? []).compactMap(\.categoryId)) }
        return SampleInput(studios: studios, cityId: cityId, visits: visits, hyroxVisits: hyrox, hyroxClassStudios: Set(classes.map(\.studioId)),
                           favourites: favorites, distances: studioDistances, listed: Set(shopReal?.storefronts.map(\.studioId) ?? []),
                           categoryTitle: { id in self.categories.first { $0.id == id }?.title })
    }

    /// Buy, Reserve, Notify me and Webshop on a sample: a short message, nothing sent.
    func flashSample() { flash(Copy.shopSampleToast, icon: "bag") }

    /// The switch as saved on this device: on unless turned off. The demo shows none unless BRUCE_SAMPLE_SHOP=1.
    nonisolated static func savedSampleShop() -> Bool {
        demo ? flag("BRUCE_SAMPLE_SHOP") : (UserDefaults.standard.object(forKey: "showSampleShop") as? Bool ?? true)
    }
}
