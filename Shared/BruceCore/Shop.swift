import Foundation

// Studio shop (phase 2 of the Studio Merch plan): a catalogue of products the studios approved, served by our server
// (`GET /shop?city=`, `GET /shop/studio/<id>`; server/README.md "Shop"). The studio is the seller: Brüce shows what it
// sells at the desk or in its webshop, shows planned drops with Notify me, and reminds. Nothing here takes money or
// an address, and no product carries a Bruce or Brüce mark. Prices are in öre and include VAT, as the Bruce API's.
// The same logic lives in docs/app/js/shop.js; ShopTests checks both against the same cases.

/// The Shop screen's chips, in this order.
enum ProductKind: String, Codable, CaseIterable, Hashable {
    case towel, mat, socks, apparel, sauna, other
    var title: String {
        switch self {
        case .towel: "Towels"
        case .mat: "Mats"
        case .socks: "Grip socks"
        case .apparel: "Apparel"
        case .sauna: "Sauna"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .towel: "rectangle.portrait.on.rectangle.portrait"
        case .mat: "figure.yoga"
        case .socks: "shoeprints.fill"
        case .apparel: "tshirt"
        case .sauna: "flame"
        case .other: "bag"
        }
    }
}

/// Where the studio sells it: at the desk, in its webshop, or printed to order for a drop.
enum Fulfilment: String, Codable, Hashable {
    case desk, link, pod
}

struct ProductVariant: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var inStock = true

    init(id: String, label: String, inStock: Bool = true) { self.id = id; self.label = label; self.inStock = inStock }
    /// Missing fields get their defaults (a synthesized decoder would refuse them).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        inStock = try c.decodeIfPresent(Bool.self, forKey: .inStock) ?? true
    }
}

struct Product: Codable, Hashable, Identifiable {
    var id: String
    /// Bruce's studio id: the seller's studio page.
    var studioId: Int
    var title: String
    var kind: ProductKind
    /// "Organic cotton · 90 × 180 cm".
    var description: String? = nil
    /// Incl. VAT.
    var priceOre: Int
    var vatRate = 25
    var fulfilment: Fulfilment
    /// The product's own page in the studio's webshop (https).
    var linkUrl: String? = nil
    var variants: [ProductVariant] = []

    init(id: String, studioId: Int, title: String, kind: ProductKind, description: String? = nil, priceOre: Int, vatRate: Int = 25, fulfilment: Fulfilment,
         linkUrl: String? = nil, variants: [ProductVariant] = []) {
        self.id = id; self.studioId = studioId; self.title = title; self.kind = kind; self.description = description; self.priceOre = priceOre
        self.vatRate = vatRate; self.fulfilment = fulfilment; self.linkUrl = linkUrl; self.variants = variants
    }
    /// Required: id, studioId, title, kind, priceOre, fulfilment. A variant this version can't read is dropped, not the product.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        studioId = try c.decode(Int.self, forKey: .studioId)
        title = try c.decode(String.self, forKey: .title)
        kind = try c.decode(ProductKind.self, forKey: .kind)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        priceOre = try c.decode(Int.self, forKey: .priceOre)
        vatRate = try c.decodeIfPresent(Int.self, forKey: .vatRate) ?? 25
        fulfilment = try c.decode(Fulfilment.self, forKey: .fulfilment)
        linkUrl = try c.decodeIfPresent(String.self, forKey: .linkUrl)
        variants = ((try? c.decodeIfPresent([LossyItem<ProductVariant>].self, forKey: .variants)) ?? nil)?.compactMap(\.value) ?? []
    }

    var priceText: String { ShopMoney.kr(priceOre) }
    var url: URL? { ShopLink.https(linkUrl) }
    var inStockVariants: [ProductVariant] { variants.filter(\.inStock) }
}

/// A pre-order window for one product, printed in one run and picked up at the studio.
struct Drop: Codable, Hashable, Identifiable {
    var id: String
    var studioId: Int
    var productId: String
    /// Only that challenge's finishers see it (phase 3).
    var challengeId: String? = nil
    var title: String
    /// UTC ms.
    var opensAt: Int
    var closesAt: Int
    var minQty = 0
    var maxQty: Int? = nil
    var reserved = 0
    /// The day pickup starts, "2027-02-20", once known.
    var pickupFrom: String? = nil
    /// The studio's own payment link for Reserve (phase 3).
    var linkUrl: String? = nil

    init(id: String, studioId: Int, productId: String, challengeId: String? = nil, title: String, opensAt: Int, closesAt: Int, minQty: Int = 0, maxQty: Int? = nil,
         reserved: Int = 0, pickupFrom: String? = nil, linkUrl: String? = nil) {
        self.id = id; self.studioId = studioId; self.productId = productId; self.challengeId = challengeId; self.title = title; self.opensAt = opensAt
        self.closesAt = closesAt; self.minQty = minQty; self.maxQty = maxQty; self.reserved = reserved; self.pickupFrom = pickupFrom; self.linkUrl = linkUrl
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        studioId = try c.decode(Int.self, forKey: .studioId)
        productId = try c.decode(String.self, forKey: .productId)
        challengeId = try c.decodeIfPresent(String.self, forKey: .challengeId)
        title = try c.decode(String.self, forKey: .title)
        opensAt = try c.decode(Int.self, forKey: .opensAt)
        closesAt = try c.decode(Int.self, forKey: .closesAt)
        minQty = try c.decodeIfPresent(Int.self, forKey: .minQty) ?? 0
        maxQty = try c.decodeIfPresent(Int.self, forKey: .maxQty)
        reserved = try c.decodeIfPresent(Int.self, forKey: .reserved) ?? 0
        pickupFrom = try c.decodeIfPresent(String.self, forKey: .pickupFrom)
        linkUrl = try c.decodeIfPresent(String.self, forKey: .linkUrl)
    }

    enum State { case upcoming, open, closed }

    var opens: Date { Date(timeIntervalSince1970: Double(opensAt) / 1000) }
    var closes: Date { Date(timeIntervalSince1970: Double(closesAt) / 1000) }
    func state(now: Date = Date()) -> State {
        if now < opens { return .upcoming }
        return now < closes ? .open : .closed
    }
    /// "Closes in 2 d 14 h", "Opens in 5 d 3 h", "Closed".
    func countdownText(now: Date = Date()) -> String {
        switch state(now: now) {
        case .upcoming: return "Opens in \(ShopClock.until(opens, now: now))"
        case .open: return "Closes in \(ShopClock.until(closes, now: now))"
        case .closed: return "Closed"
        }
    }
    /// The run's goal: its size, else the minimum; 0 without either.
    var goal: Int { maxQty ?? minQty }
    /// "31 of 40", or "31 reserved" without a goal.
    var progressText: String { goal > 0 ? "\(reserved) of \(goal)" : "\(reserved) reserved" }
    var progress: Double { goal > 0 ? min(1, Double(reserved) / Double(goal)) : 0 }
    /// "Sat 20 Feb": the day pickup starts; nil until the studio knows.
    var pickupDayText: String? { pickupFrom.map { RaceDay.format($0, "EEE d MMM") } }
    /// "Pickup from Sat 20 Feb".
    var pickupText: String? { pickupDayText.map { "Pickup from \($0)" } }
    var url: URL? { ShopLink.https(linkUrl) }
}

/// A studio that approved a listing: the seller of record, its webshop and how pickup works.
struct Storefront: Codable, Hashable, Identifiable {
    var studioId: Int
    var sellerName: String
    var city: String
    var webshopUrl: String? = nil
    var pickupNote: String? = nil
    var consentAt: String
    var id: Int { studioId }
    var webshop: URL? { ShopLink.https(webshopUrl) }

    init(studioId: Int, sellerName: String, city: String, webshopUrl: String? = nil, pickupNote: String? = nil, consentAt: String) {
        self.studioId = studioId; self.sellerName = sellerName; self.city = city; self.webshopUrl = webshopUrl; self.pickupNote = pickupNote; self.consentAt = consentAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        studioId = try c.decode(Int.self, forKey: .studioId)
        sellerName = try c.decode(String.self, forKey: .sellerName)
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        webshopUrl = try c.decodeIfPresent(String.self, forKey: .webshopUrl)
        pickupNote = try c.decodeIfPresent(String.self, forKey: .pickupNote)
        consentAt = try c.decode(String.self, forKey: .consentAt)
    }
}

/// The catalogue of a city, as `GET /shop?city=` answers it.
struct ShopCatalog: Codable, Hashable {
    var city = ""
    var storefronts: [Storefront] = []
    var products: [Product] = []
    var drops: [Drop] = []

    /// Nothing listed: the apps then show no shop at all (a user who never sees a listing sees no dead feature).
    var isEmpty: Bool { products.isEmpty }
    func storefront(_ studioId: Int) -> Storefront? { storefronts.first { $0.studioId == studioId } }
    func product(_ id: String) -> Product? { products.first { $0.id == id } }
    func drop(_ id: String) -> Drop? { drops.first { $0.id == id } }
    func products(for studioId: Int) -> [Product] { products.filter { $0.studioId == studioId } }
    func drops(for studioId: Int) -> [Drop] { drops.filter { $0.studioId == studioId } }
    /// The drop of a product (one at a time), if any.
    func drop(for product: Product) -> Drop? { drops.first { $0.productId == product.id } }
    /// The chips: the kinds that have a product, in the chips' order.
    var kinds: [ProductKind] { ProductKind.allCases.filter { k in products.contains { $0.kind == k } } }
    func filtered(kind: ProductKind?) -> [Product] { kind.map { k in products.filter { $0.kind == k } } ?? products }
    /// A studio lists a towel (the "Forgot your towel?" card after a check-in at a Wellness studio).
    func towel(for studioId: Int) -> Product? { products(for: studioId).first { $0.kind == .towel } }
    /// Drops not over yet, soonest closing first.
    func liveDrops(now: Date = Date()) -> [Drop] { drops.filter { $0.state(now: now) != .closed }.sorted { $0.closesAt < $1.closesAt } }
    /// Home's drop card: the live drop closing first.
    func homeDrop(now: Date = Date()) -> Drop? { liveDrops(now: now).first }

    /// Decodes a catalogue, skipping entries this version can't read (a new kind, say) instead of failing the whole answer.
    static func decode(_ data: Data) throws -> ShopCatalog {
        struct File: Decodable { let city: String?; let storefronts: [LossyItem<Storefront>]?; let products: [LossyItem<Product>]?; let drops: [LossyItem<Drop>]? }
        let f = try JSONDecoder().decode(File.self, from: data)
        var c = ShopCatalog(city: f.city ?? "", storefronts: (f.storefronts ?? []).compactMap(\.value), products: (f.products ?? []).compactMap(\.value),
                            drops: (f.drops ?? []).compactMap(\.value))
        // A product whose studio has no storefront, or a drop whose product is gone, is left out.
        let fronts = Set(c.storefronts.map(\.studioId))
        c.products = c.products.filter { fronts.contains($0.studioId) && $0.priceOre >= 0 }
        let ids = Set(c.products.map(\.id))
        c.drops = c.drops.filter { ids.contains($0.productId) && $0.closesAt > $0.opensAt }
        return c
    }
}

private struct LossyItem<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

enum ShopLink {
    /// https links only (the studio's webshop, a payment link); anything else is dropped.
    static func https(_ s: String?) -> URL? {
        guard let s, let u = URL(string: s), u.scheme?.lowercased() == "https", u.host != nil else { return nil }
        return u
    }
}

enum ShopClock {
    /// "2 d 14 h", "3 h", "25 min"; "" once the moment has passed.
    static func until(_ d: Date, now: Date = Date()) -> String {
        let left = Int(d.timeIntervalSince(now))
        guard left > 0 else { return "" }
        let days = left / 86_400, hours = left % 86_400 / 3600, minutes = left % 3600 / 60
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h" }
        return "\(max(1, minutes)) min"
    }
}

enum ShopMoney {
    /// "449 kr", "1,295 kr": whole kronor, as the prices on the pages.
    static func kr(_ ore: Int) -> String { RaceMoney.grouped(Int((Double(ore) / 100).rounded())) + " kr" }
    /// "449,00 kr", "89,80 kr": the checkout rows.
    static func exact(_ ore: Int) -> String {
        let a = abs(ore)
        return (ore < 0 ? "-" : "") + RaceMoney.grouped(a / 100) + "," + String(format: "%02d", a % 100) + " kr"
    }
    /// The VAT inside a price that includes it: 449 kr at 25% holds 89,80 kr.
    static func vatPart(_ ore: Int, rate: Int) -> Int { Int((Double(ore) - Double(ore) / (1 + Double(rate) / 100)).rounded()) }
}

// MARK: - Server

/// The shop routes of the auto-book server (server/README.md "Shop"). The catalogue is public; Notify me signs in
/// with the Bruce login like the other `/me` routes.
enum ShopServer {
    private static func get(_ path: String) async throws -> Data {
        guard let base = URL(string: AutoBookServer.url), base.host != nil else { throw BruceAPI.APIError.notLoggedIn }
        var req = URLRequest(url: base.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
    /// `GET /shop?city=STO`.
    static func catalogue(city: String) async throws -> ShopCatalog {
        try ShopCatalog.decode(try await get("shop?city=\(city)"))
    }
    /// `PUT|DELETE /me/notify/<dropId>`: a push and an email when the drop opens.
    static func notify(_ on: Bool, dropId: String, session: Session) async throws {
        try await BruceAPI.send(AutoBookServer.request(on ? "PUT" : "DELETE", "me/notify/\(dropId)", session: session))
    }
    /// `GET /me/shop`: the drops the member watches, on every device.
    static func mine(session: Session) async throws -> [String] {
        struct R: Decodable { let notify: [String]? }
        return try JSONDecoder().decode(R.self, from: try await BruceAPI.send(AutoBookServer.request("GET", "me/shop", session: session))).notify ?? []
    }
    /// `POST /shop/tap`: one to the day's counter for a listing; no user id goes with it.
    static func tap(productId: String) async {
        guard let base = URL(string: AutoBookServer.url), base.host != nil else { return }
        var req = URLRequest(url: base.appendingPathComponent("shop/tap"), timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["productId": productId])
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: - App state

extension AppModel {
    /// Something is listed in the city: Home's Shop section, the studio rails and the towel card show only then.
    var showsShop: Bool { shop?.isEmpty == false }

    /// Loads the city's catalogue: the demo's in demo mode, else `GET /shop?city=` at most every 10 minutes (or `force`).
    /// A failed read keeps whatever is shown; with the server switched off nothing is listed.
    func loadShop(force: Bool = false) async {
        if AppModel.demo { if shop == nil { loadDemoShop() }; return }
        guard AutoBookServer.isConfigured, let code = city?.code ?? (cityId == 1 ? "STO" : nil) else { shop = nil; return }
        if !force, let at = shopFetchedAt, Date().timeIntervalSince(at) < 600, shop?.city == code { return }
        guard !shopLoading else { return }
        shopLoading = true
        defer { shopLoading = false }
        if let c = try? await ShopServer.catalogue(city: code) { shop = c; shopFetchedAt = Date() }
        if tokenUsable, let s = session, AutoBookServer.booksForMe, let mine = try? await ShopServer.mine(session: s) { shopNotify = Set(mine) }
    }

    func shopStorefront(_ studioId: Int) -> Storefront? { shop?.storefront(studioId) }
    func shopProducts(for studioId: Int) -> [Product] { shop?.products(for: studioId) ?? [] }
    func shopProduct(_ id: String) -> Product? { shop?.product(id) }
    /// The drop for a product, if it has one.
    func shopDrop(for product: Product) -> Drop? { shop?.drop(for: product) }
    func isNotified(_ dropId: String) -> Bool { shopNotify.contains(dropId) }

    /// "Forgot your towel?" after a check-in: a Wellness studio (sauna, spa) whose storefront lists a towel.
    func towelPrompt(studioId: Int) -> Product? {
        guard isWellness(studioId: studioId) else { return nil }
        return shop?.towel(for: studioId)
    }

    /// Notify me on a drop: a push and an email from our server when the pre-order opens. Needs the server; the demo pretends.
    func setNotify(_ drop: Drop, _ on: Bool) async {
        if AppModel.demo {
            if on { shopNotify.insert(drop.id) } else { shopNotify.remove(drop.id) }
            flash(on ? Copy.shopNotifyOn : Copy.shopNotifyOff, icon: on ? "bell.fill" : "bell.slash")
            return
        }
        guard tokenUsable, let s = session else { present(.login); return }
        guard AutoBookServer.isConfigured, AutoBookServer.booksForMe else { flash(Copy.shopNotifyNeedsServer, icon: "server.rack"); return }
        do {
            try await ShopServer.notify(on, dropId: drop.id, session: s)
            if on { shopNotify.insert(drop.id) } else { shopNotify.remove(drop.id) }
            if on {
                #if os(iOS)
                await AutoBook.requestPermission()   // the "Drop open" push; also registers for it
                #endif
                await syncAutoBookServer()           // sends this device's push token
            }
            flash(on ? Copy.shopNotifyOn : Copy.shopNotifyOff, icon: on ? "bell.fill" : "bell.slash")
        } catch { flash(Challenge.message(error)) }
    }

    /// One to the day's anonymous counter when a listing is opened (the KPI "taps per studio-page view"). Never in the demo.
    func tapProduct(_ id: String) {
        guard !AppModel.demo, AutoBookServer.isConfigured, !shopTapped.contains(id) else { return }
        shopTapped.insert(id)
        Task { await ShopServer.tap(productId: id) }
    }

    /// Opens Home › Shop.
    func showShop() {
        dismissSheets()
        stacks[.home] = [.shop]
        tab = .home
    }
}
