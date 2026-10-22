import XCTest
@testable import BruceMacOS

// Studio shop (Shop.swift): the catalogue's reading and hiding rules, drop windows and progress, money, and the demo data.
// The same cases run against docs/app/js/shop.js in docs/app/test/shop.test.js.
final class ShopTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_801_950_000)   // 2027-02-05 ~05:40Z
    func ms(_ s: String) -> Int { Int(ISO8601DateFormatter().date(from: s)!.timeIntervalSince1970 * 1000) }

    var drop: Drop {
        Drop(id: "race-day", studioId: 9840, productId: "tee", title: "Race Day tee", opensAt: ms("2027-01-25T08:00:00Z"), closesAt: ms("2027-02-07T22:00:00Z"),
             minQty: 25, maxQty: 40, reserved: 31, pickupFrom: "2027-02-20")
    }

    func testDropWindowProgressAndCountdown() {
        let d = drop
        XCTAssertEqual(d.state(now: ISO8601DateFormatter().date(from: "2027-01-20T00:00:00Z")!), .upcoming)
        XCTAssertEqual(d.state(now: now), .open)
        XCTAssertEqual(d.state(now: ISO8601DateFormatter().date(from: "2027-02-08T00:00:00Z")!), .closed)
        XCTAssertEqual(d.progressText, "31 of 40")
        XCTAssertEqual(d.progress, 0.775, accuracy: 0.001)
        var noMax = d; noMax.maxQty = nil
        XCTAssertEqual(noMax.progressText, "31 of 25")
        noMax.minQty = 0
        XCTAssertEqual(noMax.progressText, "31 reserved")
        XCTAssertEqual(noMax.progress, 0)
        var over = d; over.reserved = 50
        XCTAssertEqual(over.progress, 1)
        XCTAssertEqual(d.countdownText(now: ISO8601DateFormatter().date(from: "2027-02-05T08:00:00Z")!), "Closes in 2 d 14 h")
        XCTAssertEqual(d.countdownText(now: ISO8601DateFormatter().date(from: "2027-02-07T19:30:00Z")!), "Closes in 2 h")
        XCTAssertEqual(d.countdownText(now: ISO8601DateFormatter().date(from: "2027-02-07T21:50:00Z")!), "Closes in 10 min")
        XCTAssertEqual(d.countdownText(now: ISO8601DateFormatter().date(from: "2027-01-20T08:00:00Z")!), "Opens in 5 d 0 h")
        XCTAssertEqual(d.countdownText(now: ISO8601DateFormatter().date(from: "2027-02-08T00:00:00Z")!), "Closed")
        XCTAssertEqual(d.pickupText, "Pickup from Sat 20 Feb")
        XCTAssertEqual(Copy.shopDropLine(d), "Pre-order until Sun 7 Feb · one print run · pickup from Sat 20 Feb")
    }

    func testMoney() {
        XCTAssertEqual(ShopMoney.kr(44900), "449 kr")
        XCTAssertEqual(ShopMoney.kr(129500), "1,295 kr")
        XCTAssertEqual(ShopMoney.kr(34950), "350 kr")
        XCTAssertEqual(ShopMoney.exact(44900), "449,00 kr")
        XCTAssertEqual(ShopMoney.exact(8980), "89,80 kr")
        XCTAssertEqual(ShopMoney.exact(0), "0,00 kr")
        XCTAssertEqual(ShopMoney.vatPart(44900, rate: 25), 8980)
        XCTAssertEqual(ShopMoney.vatPart(34900, rate: 25), 6980)
        XCTAssertEqual(ShopMoney.vatPart(10000, rate: 0), 0)
    }

    func testCatalogueReadingHidesWhatCannotBeShown() throws {
        let json = """
        {"city":"STO","storefronts":[{"studioId":9850,"sellerName":"Ångan Bastu AB","city":"STO","webshopUrl":"https://shop.example.org/angan","consentAt":"2026-11-09"},
          {"studioId":1,"sellerName":"Broken","city":"STO"}],
         "products":[{"id":"towel","studioId":9850,"title":"Bastu towel","kind":"towel","priceOre":44900,"fulfilment":"desk","variants":[{"id":"natural","label":"Natural"},{"id":"x","label":"Out","inStock":false}]},
          {"id":"hat","studioId":9850,"title":"Felt hat","kind":"hat","priceOre":29900,"fulfilment":"desk"},
          {"id":"orphan","studioId":1,"title":"Mat","kind":"mat","priceOre":100,"fulfilment":"desk"},
          {"id":"tee","studioId":9850,"title":"Tee","kind":"apparel","priceOre":34900,"fulfilment":"pod"}],
         "drops":[{"id":"d1","studioId":9850,"productId":"tee","title":"Tee drop","opensAt":1,"closesAt":2},
          {"id":"d2","studioId":9850,"productId":"gone","title":"Gone","opensAt":1,"closesAt":2},
          {"id":"d3","studioId":9850,"productId":"tee","title":"Backwards","opensAt":5,"closesAt":2}]}
        """
        let c = try ShopCatalog.decode(Data(json.utf8))
        XCTAssertEqual(c.storefronts.map(\.studioId), [9850], "a storefront without the consent day is skipped")
        XCTAssertEqual(c.products.map(\.id), ["towel", "tee"], "an unknown kind and a product without a storefront are skipped")
        XCTAssertEqual(c.drops.map(\.id), ["d1"], "a drop of a missing product or with a backwards window is skipped")
        XCTAssertEqual(c.kinds, [.towel, .apparel])
        XCTAssertEqual(c.filtered(kind: .towel).map(\.id), ["towel"])
        XCTAssertEqual(c.towel(for: 9850)?.id, "towel")
        XCTAssertNil(c.towel(for: 1724))
        XCTAssertEqual(c.product("towel")?.inStockVariants.map(\.label), ["Natural"])
        XCTAssertEqual(c.product("towel")?.vatRate, 25)
        XCTAssertEqual(c.storefront(9850)?.webshop?.host, "shop.example.org")
        XCTAssertNil(ShopLink.https("http://shop.example.org"))
        XCTAssertNil(ShopLink.https("javascript:alert(1)"))
        XCTAssertFalse(c.isEmpty)
        XCTAssertTrue(try ShopCatalog.decode(Data(#"{"city":"GOT","storefronts":[],"products":[],"drops":[]}"#.utf8)).isEmpty, "nothing listed: the apps show no shop")
        XCTAssertTrue(ShopCatalog().isEmpty)
    }

    func testDemoCatalogue() {
        let c = ShopCatalog.demo(now: now)
        XCTAssertFalse(c.isEmpty)
        XCTAssertEqual(c.city, "STO")
        XCTAssertEqual(Set(c.products.map(\.studioId)), Set(c.storefronts.map(\.studioId)), "every product has a storefront")
        XCTAssertEqual(c.products.count, Set(c.products.map(\.id)).count, "ids are unique")
        for p in c.products {
            XCTAssertNil(p.title.range(of: "br[uü]ce", options: [.regularExpression, .caseInsensitive]), "no Bruce or Brüce mark on \(p.title)")
            XCTAssertGreaterThan(p.priceOre, 0)
            XCTAssertEqual(p.priceOre % 100, 0, "whole kronor in the demo")
        }
        for s in c.storefronts { XCTAssertTrue(s.webshopUrl?.hasPrefix("https://shop.example.org") ?? true, "fictional webshops only") }
        XCTAssertEqual(c.kinds, [.towel, .mat, .socks, .apparel, .sauna, .other])
        XCTAssertEqual(c.towel(for: ShopCatalog.demoAngan)?.priceText, "449 kr")
        XCTAssertNil(c.towel(for: ShopCatalog.demoYogaloft))
        let d = try! XCTUnwrap(c.drop("hornstull-race-day-2027"))
        XCTAssertEqual(d.title, "Hornstull Race Day tee")
        XCTAssertEqual(d.state(now: now), .open)
        XCTAssertEqual(d.countdownText(now: now), "Closes in 2 d 14 h")
        XCTAssertEqual(d.progressText, "31 of 40")
        XCTAssertEqual(c.drop(for: c.product("karnan-race-day-tee")!)?.id, d.id)
        XCTAssertEqual(c.homeDrop(now: now)?.id, "finisher-tee-2026", "the member's own unlocked drop comes first on Home")
        XCTAssertEqual(c.products(for: ShopCatalog.demoAngan).map(\.title), ["Bastu towel", "Felt sauna hat", "Linen seat cover"])
    }

    @MainActor func testDemoStudiosAndTowelPrompt() {
        AppModel.demo = true
        let m = AppModel()
        m.loadDemo()
        XCTAssertTrue(m.showsShop)
        for id in [ShopCatalog.demoYogaloft, ShopCatalog.demoKarnan, ShopCatalog.demoAngan] { XCTAssertNotNil(m.studio(id), "demo studio \(id) is on the list") }
        XCTAssertTrue(m.isWellness(studioId: ShopCatalog.demoAngan))
        XCTAssertEqual(m.towelPrompt(studioId: ShopCatalog.demoAngan)?.id, "angan-bastu-towel")
        XCTAssertNil(m.towelPrompt(studioId: ShopCatalog.demoYogaloft), "a yoga studio gets no towel card")
        XCTAssertNil(m.towelPrompt(studioId: 9520), "a spa without a listing gets none either")
        XCTAssertEqual(m.shopProducts(for: ShopCatalog.demoKarnan).count, 3)
        XCTAssertNil(m.shopStorefront(1724), "no listing: nothing on the studio page")
    }
}

// MARK: - Phase 3: drops

extension ShopTests {
    func testDropReadyStateAndReserveLink() {
        var d = drop
        d.linkUrl = "https://shop.example.org/karnan/race-day-tee"
        XCTAssertEqual(d.reserveURL(now: now)?.host, "shop.example.org", "open: Reserve opens the studio's own checkout")
        XCTAssertNil(d.reserveURL(now: ISO8601DateFormatter().date(from: "2027-01-20T00:00:00Z")!), "not open yet")
        XCTAssertNil(d.reserveURL(now: ISO8601DateFormatter().date(from: "2027-02-08T00:00:00Z")!), "closed")
        d.linkUrl = "http://shop.example.org/x"
        XCTAssertNil(d.reserveURL(now: now), "https only")
        d.ready = true
        XCTAssertEqual(d.state(now: now), .ready)
        XCTAssertEqual(d.countdownText(now: now), "Ready for pickup")
        XCTAssertNil(d.reserveURL(now: now), "at the desk: nothing to reserve")
        let front = Storefront(studioId: 9840, sellerName: "Kärnan Reformer AB", city: "STO", pickupNote: "At the desk, weekdays 06–20", consentAt: "2026-11-12")
        XCTAssertEqual(Copy.shopReadyBody(front), "Ready at the desk: Kärnan Reformer AB, at the desk, weekdays 06–20.")
        XCTAssertEqual(Copy.shopReadyBody(nil), "Ready at the desk.")
        XCTAssertEqual(Copy.shopReserve("349 kr"), "Reserve · 349 kr")
    }

    func testUnlockedDropsLayOverTheCatalogue() throws {
        let c = try ShopCatalog.decode(Data("""
        {"city":"STO","storefronts":[{"studioId":9840,"sellerName":"Kärnan Reformer AB","city":"STO","consentAt":"2026-11-12"}],
         "products":[{"id":"socks","studioId":9840,"title":"Grip socks","kind":"socks","priceOre":14900,"fulfilment":"desk"}],
         "drops":[{"id":"race-day","studioId":9840,"productId":"socks","title":"Socks drop","opensAt":1,"closesAt":9999999999999,"ready":true}]}
        """.utf8))
        XCTAssertEqual(c.drops[0].state(now: now), .ready, "the catalogue's `ready` is read")
        XCTAssertFalse(c.drops[0].unlocked)
        let mine = try JSONDecoder().decode(ShopServer.Mine.self, from: Data("""
        {"notify":["finisher-tee"],"drops":[{"id":"finisher-tee","studioId":9840,"productId":"finisher","challengeId":"abc","title":"Finisher tee","opensAt":1,"closesAt":9999999999999,"unlocked":true}],
         "products":[{"id":"finisher","studioId":9840,"title":"Finisher tee","kind":"apparel","priceOre":34900,"fulfilment":"pod","variants":[{"id":"m","label":"M"}]}]}
        """.utf8))
        XCTAssertEqual(mine.notify, ["finisher-tee"])
        let merged = c.merging(drops: mine.drops, products: mine.products)
        XCTAssertEqual(merged.products.map(\.id), ["socks", "finisher"])
        XCTAssertEqual(merged.drops.map(\.id), ["race-day", "finisher-tee"])
        XCTAssertEqual(merged.drop(forChallenge: "abc")?.id, "finisher-tee")
        XCTAssertNil(merged.drop(forChallenge: "other"))
        XCTAssertNil(c.drop(forChallenge: "abc"), "nothing unlocked before the server says so")
        XCTAssertEqual(merged.homeDrop(now: now)?.id, "finisher-tee", "the member's own drop comes first on Home")
        XCTAssertEqual(merged.merging(drops: mine.drops, products: mine.products).products.count, 2, "merging twice adds nothing")
        // An empty Mine (a member with nothing unlocked) decodes too.
        XCTAssertEqual(try JSONDecoder().decode(ShopServer.Mine.self, from: Data(#"{"notify":[]}"#.utf8)).drops.count, 0)
    }

    @MainActor func testDemoFinisherTee() {
        AppModel.demo = true
        let m = AppModel()
        m.loadDemo()
        m.loadDemoChallenges()
        let done = try! XCTUnwrap(m.challenges.first { $0.id == "demoDone" })
        XCTAssertEqual(done.metric, "target")
        XCTAssertEqual(m.challengeDetails["demoDone"]?.leaderboard?.first { $0.userId == 0 }?.done, true, "the demo member hit 20")
        let d = try! XCTUnwrap(m.rewardDrop(forChallenge: "demoDone"))
        XCTAssertTrue(d.unlocked)
        XCTAssertEqual(d.state(), .open)
        XCTAssertNotNil(d.reserveURL())
        XCTAssertEqual(m.shopProduct(d.productId)?.title, "Finisher tee")
        XCTAssertNil(m.rewardDrop(forChallenge: "demoOct"), "a running challenge has no reward")
        XCTAssertTrue(Copy.shopFinisherBody(done, studio: "Kärnan Reformer", drop: d).hasPrefix("Only for people who hit 20. One print run, picked up at Kärnan Reformer. Pre-order until "))
        XCTAssertEqual(PushTarget(userInfo: ["dropId": "x", "productId": "karnan-finisher-tee"]), .product("karnan-finisher-tee"))
    }

    // MARK: Checkout (phase 4)

    var towel: Product {
        Product(id: "towel", studioId: 9850, title: "Bastu towel", kind: .towel, priceOre: 44900, fulfilment: .desk,
                variants: [ProductVariant(id: "natural", label: "Natural"), ProductVariant(id: "charcoal", label: "Charcoal", inStock: false)])
    }
    var connected: Storefront {
        Storefront(studioId: 9850, sellerName: "Ångan Bastu AB", city: "STO", pickupNote: "At the desk", consentAt: "2026-11-09", checkout: true, shippingOre: 4900)
    }

    func testCheckoutDraftSumsAndProblems() {
        var d = CheckoutDraft(product: towel, storefront: connected, variant: towel.variants[0], qty: 2, delivery: .pickup)
        XCTAssertEqual(d.subtotalOre, 89800)
        XCTAssertEqual(d.shippingOre, 0)
        XCTAssertEqual(d.totalOre, 89800)
        XCTAssertEqual(d.vatOre, 17960, "the VAT inside 898 kr at 25%")
        XCTAssertEqual(d.itemLine, "Bastu towel · Natural × 2")
        XCTAssertNil(d.problem)
        d.delivery = .ship
        XCTAssertEqual(d.shippingOre, 4900)
        XCTAssertEqual(d.totalOre, 94700)
        XCTAssertEqual(d.vatOre, 18940)
        XCTAssertEqual(d.body["delivery"] as? String, "ship")
        XCTAssertEqual(d.body["variantId"] as? String, "natural")
        XCTAssertEqual(d.body["qty"] as? Int, 2)
        XCTAssertEqual(d.body["returnTo"] as? String, "app")
        // What stops it before Stripe.
        var pickupOnly = connected; pickupOnly.shippingOre = nil
        XCTAssertFalse(pickupOnly.ships)
        XCTAssertEqual(CheckoutDraft(product: towel, storefront: pickupOnly, variant: towel.variants[0], qty: 1, delivery: .ship).problem, Copy.shopNoShipping)
        XCTAssertEqual(CheckoutDraft(product: towel, storefront: connected, variant: nil, qty: 1).problem, Copy.shopPickVariant)
        XCTAssertEqual(CheckoutDraft(product: towel, storefront: connected, variant: towel.variants[1], qty: 1).problem, Copy.shopOutOfStock)
        XCTAssertEqual(CheckoutDraft(product: towel, storefront: connected, variant: towel.variants[0], qty: 6).problem, "1 to 5 of each")
        var off = connected; off.checkout = false
        XCTAssertEqual(CheckoutDraft(product: towel, storefront: off, variant: towel.variants[0]).problem, Copy.shopNoCheckout)
        XCTAssertEqual(Copy.shopBuy(ShopMoney.kr(d.totalOre)), "Buy · 947 kr")
        XCTAssertEqual(Copy.shopPay(ShopMoney.exact(d.totalOre)), "Pay 947,00 kr")
        XCTAssertEqual(Copy.shopShipPrice(connected), "Ship to me · 49 kr")
        XCTAssertEqual(Copy.shopVatLine(25), "incl. VAT 25%")
    }

    func testStorefrontAndOrderDecode() throws {
        // A storefront from phase 3's server has no checkout fields: Buy stays off.
        let old = try JSONDecoder().decode(Storefront.self, from: Data(#"{"studioId":9850,"sellerName":"Ångan Bastu AB","consentAt":"2026-11-09"}"#.utf8))
        XCTAssertFalse(old.checkout)
        XCTAssertFalse(old.ships)
        let new = try JSONDecoder().decode(Storefront.self, from: Data(#"{"studioId":9850,"sellerName":"Ångan Bastu AB","consentAt":"2026-11-09","checkout":true,"shippingOre":4900}"#.utf8))
        XCTAssertTrue(new.checkout)
        XCTAssertEqual(new.shippingOre, 4900)
        // An order as GET /me/orders lists it.
        let json = #"{"orders":[{"id":"o1","studioId":9850,"items":[{"productId":"towel","variantId":"natural","title":"Bastu towel","label":"Natural","qty":1,"unitOre":44900}],"totalOre":44900,"vatOre":8980,"delivery":"pickup","status":"ready","statusText":"Ready for pickup","pickupCode":"K7P2Q","sellerName":"Ångan Bastu AB","createdAt":"2026-11-20T10:00:00Z","updatedAt":"2026-11-22T08:00:00Z"},{"id":"bad"}]}"#
        let orders = try JSONDecoder().decode(ShopServer.Orders.self, from: Data(json.utf8)).orders
        XCTAssertEqual(orders.count, 1, "a broken row is skipped, not the list")
        let o = orders[0]
        XCTAssertTrue(o.isReady)
        XCTAssertFalse(o.isDone)
        XCTAssertEqual(o.statusLine, "Ready for pickup")
        XCTAssertEqual(o.items[0].line, "Bastu towel · Natural")
        XCTAssertEqual(o.symbol, "checkmark.seal.fill")
        XCTAssertEqual(Order.statusText("paid", delivery: .pickup), "Paid · being prepared for pickup")
        XCTAssertEqual(Order.statusText("shipped", delivery: .ship), "On its way")
        XCTAssertEqual(Order.statusText("delivered", delivery: .ship), "Delivered")
        XCTAssertEqual(PushTarget(userInfo: ["orderId": "o1"]), .orders)
    }

    @MainActor func testDemoCheckoutAndOrders() async {
        AppModel.demo = true
        let m = AppModel()
        m.loadDemo()
        let towel = try! XCTUnwrap(m.shopProduct("angan-bastu-towel"))
        XCTAssertTrue(m.canBuy(towel), "the demo's sauna is connected")
        XCTAssertFalse(m.canBuy(try! XCTUnwrap(m.shopProduct("karnan-grip-socks"))), "the others keep the desk and the webshop")
        let draft = try! XCTUnwrap(m.checkoutDraft(for: towel))
        XCTAssertEqual(draft.variant?.id, "natural")
        XCTAssertEqual(draft.delivery, .pickup, "pickup is the default")
        XCTAssertTrue(draft.storefront.ships)
        XCTAssertNil(draft.problem)
        let opened = await m.startCheckout(draft)
        XCTAssertNil(opened, "the demo opens nothing")
        await m.loadOrders()
        XCTAssertEqual(m.orders.map(\.status), ["ready", "printing"])
        XCTAssertEqual(m.orders[0].pickupCode, "K7P2Q")
        XCTAssertEqual(m.orders[1].statusLine, "Being printed")
    }
}
