import Foundation

// Demo mode's studio shop (Shop.swift): three fictional studios with the listings from the Studio Merch mockups, a
// race-day tee drop that closes in two and a half days, and a check-in at the sauna for the "Forgot your towel?" card.
// Studios, sellers, products and the webshop are made up; no product carries a Bruce or Brüce mark. Production
// starts with an empty catalogue: only what a real studio approves gets listed. ShopTests checks the demo data.

extension ShopCatalog {
    static let demoYogaloft = 9830, demoKarnan = 9840, demoAngan = 9850

    static func demo(now: Date = Date()) -> ShopCatalog {
        let ms = { (d: Date) in Int(d.timeIntervalSince1970 * 1000) }
        let fronts = [
            Storefront(studioId: demoYogaloft, sellerName: "Yogaloft Södermalm AB", city: "STO", webshopUrl: "https://shop.example.org/yogaloft", pickupNote: "At the desk, every day 07–21", consentAt: "2026-11-10"),
            Storefront(studioId: demoKarnan, sellerName: "Kärnan Reformer AB", city: "STO", webshopUrl: nil, pickupNote: "At the desk, weekdays 06–20", consentAt: "2026-11-12"),
            Storefront(studioId: demoAngan, sellerName: "Ångan Bastu AB", city: "STO", webshopUrl: "https://shop.example.org/angan-bastu", pickupNote: "At the desk, every day 07–22", consentAt: "2026-11-09"),
        ]
        let products = [
            Product(id: "yogaloft-cork-mat", studioId: demoYogaloft, title: "Cork yoga mat", kind: .mat, description: "Natural cork on rubber · 183 × 61 cm · 4 mm", priceOre: 79500, fulfilment: .link,
                    linkUrl: "https://shop.example.org/yogaloft/cork-mat"),
            Product(id: "yogaloft-strap", studioId: demoYogaloft, title: "Cotton yoga strap", kind: .other, description: "2.5 m, metal buckle", priceOre: 14900, fulfilment: .desk),
            Product(id: "karnan-grip-socks", studioId: demoKarnan, title: "Grip socks", kind: .socks, description: "Cotton with silicone grip · 2-pack", priceOre: 14900, fulfilment: .desk,
                    variants: [ProductVariant(id: "s-m", label: "S/M"), ProductVariant(id: "l-xl", label: "L/XL")]),
            Product(id: "karnan-race-day-tee", studioId: demoKarnan, title: "Hornstull Race Day tee", kind: .apparel, description: "Organic cotton, printed in the EU · unisex", priceOre: 34900, fulfilment: .pod,
                    variants: ["xs", "s", "m", "l", "xl"].map { ProductVariant(id: $0, label: $0.uppercased()) }),
            Product(id: "angan-bastu-towel", studioId: demoAngan, title: "Bastu towel", kind: .towel, description: "Organic cotton · 90 × 180 cm", priceOre: 44900, fulfilment: .desk,
                    linkUrl: "https://shop.example.org/angan-bastu/towel", variants: [ProductVariant(id: "natural", label: "Natural"), ProductVariant(id: "charcoal", label: "Charcoal")]),
            Product(id: "angan-felt-hat", studioId: demoAngan, title: "Felt sauna hat", kind: .sauna, description: "100% wool felt", priceOre: 29900, fulfilment: .desk),
            Product(id: "angan-seat-cover", studioId: demoAngan, title: "Linen seat cover", kind: .sauna, description: "Washed linen · 50 × 150 cm", priceOre: 19900, fulfilment: .desk),
        ]
        // The race-day tee: a run of 40, 31 reserved, closing in 2 days and 14 hours, picked up at Kärnan Reformer from the end of next week.
        let closes = now.addingTimeInterval(2 * 86_400 + 14 * 3600)
        let drops = [Drop(id: "hornstull-race-day-2027", studioId: demoKarnan, productId: "karnan-race-day-tee", title: "Hornstull Race Day tee",
                          opensAt: ms(now.addingTimeInterval(-5 * 86_400)), closesAt: ms(closes), minQty: 25, maxQty: 40, reserved: 31,
                          pickupFrom: RaceDay.adding(12, to: RaceDay.today(now)), linkUrl: "https://shop.example.org/karnan/race-day-tee")]
        return ShopCatalog(city: "STO", storefronts: fronts, products: products, drops: drops)
    }
}

extension AppModel {
    /// The demo's three shop studios (on the studio list, so the rails and the towel card have pages to live on) and its catalogue.
    func loadDemoShop() {
        func dec<T: Decodable>(_ t: T.Type, _ json: String) -> T { try! JSONDecoder().decode(T.self, from: Data(json.utf8)) }
        if studioIndex[ShopCatalog.demoAngan] == nil {
            studios += dec([BruceAPI.Studio].self, """
            [{"id":\(ShopCatalog.demoYogaloft),"name":"Yogaloft Södermalm","status":"LIVE","vicinity":"Södermalm","city_id":1,"qr_code_id":"9830","has_classes":true,
              "rating":{"total":210,"average":485},
              "studio_categories":[{"category_id":2,"main":true,"order":0,"category":{"id":2,"title":"Yoga"}}],
              "studio_addresses":[{"main":true,"address":{"address":"Example street 12","zip_code":"118 46","city":"Stockholm","latitude":59.3140,"longitude":18.0710}}],
              "studio_facilities":[{"facility":{"code":"changing","title":"Changing room"}},{"facility":{"code":"shower","title":"Shower"}}],
              "visit_limit":{"items":[{"label":"BASE","limit":4},{"label":"BLACK","limit":8},{"label":"EPIC","limit":0}]},
              "description":"A fictional yoga studio used for the offline demo. Mats and straps at the desk."},
             {"id":\(ShopCatalog.demoKarnan),"name":"Kärnan Reformer","status":"LIVE","vicinity":"Hornstull","city_id":1,"qr_code_id":"9840","has_classes":true,
              "rating":{"total":96,"average":479},
              "studio_categories":[{"category_id":22,"main":true,"order":0,"category":{"id":22,"title":"Reformer"}}],
              "studio_addresses":[{"main":true,"address":{"address":"Example square 3","zip_code":"117 33","city":"Stockholm","latitude":59.3156,"longitude":18.0330}}],
              "studio_facilities":[{"facility":{"code":"changing","title":"Changing room"}},{"facility":{"code":"locker","title":"Locker"}}],
              "visit_limit":{"items":[{"label":"BASE","limit":2},{"label":"BLACK","limit":4},{"label":"EPIC","limit":8}]},
              "description":"A fictional reformer studio used for the offline demo. Grip socks at the desk; the race-day tee is a pre-order."},
             {"id":\(ShopCatalog.demoAngan),"name":"Ångan Bastu","status":"LIVE","vicinity":"Hornstull","city_id":1,"qr_code_id":"9850","label":"WELLNESS","has_openings":true,
              "rating":{"total":150,"average":480,"distribution":{"1":0,"2":2,"3":6,"4":32,"5":110}},
              "studio_categories":[{"category_id":24,"main":true,"order":0,"category":{"id":24,"title":"Sauna"}}],
              "studio_addresses":[{"main":true,"address":{"address":"Example quay 7","zip_code":"117 33","city":"Stockholm","latitude":59.3170,"longitude":18.0290}}],
              "studio_facilities":[{"facility":{"code":"changing","title":"Changing room"}},{"facility":{"code":"shower","title":"Shower"}},{"facility":{"code":"sauna","title":"Sauna"}}],
              "visit_limit":{"items":[{"label":"BASE","limit":-1},{"label":"BLACK","limit":4},{"label":"EPIC","limit":8}]},
              "description":"A fictional sauna used for the offline demo. Towels for rent at the desk."}]
            """)
            let iso = ISO8601DateFormatter()
            let now = Date()
            schedules[ShopCatalog.demoAngan] = [BruceAPI.ScheduleEntry(start: iso.string(from: now.addingTimeInterval(-6 * 3600)), end: iso.string(from: now.addingTimeInterval(5 * 3600)), isAllDay: false)]
        }
        shop = ShopCatalog.demo()
    }

    /// Demo screen "towel": a check-in at the sauna just now, so the ticket shows the "Forgot your towel?" card.
    func loadDemoSaunaCheckIn() {
        let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600))
        pastBookings.append(BruceAPI.Booking(id: 5002, classId: nil, studioId: ShopCatalog.demoAngan, checkedInAt: at, class: nil))
    }
}
