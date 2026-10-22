import Foundation

// Studio shop (phase 2 of the Studio Merch plan): a catalogue of products the studios approved, served by our server
// (`GET /shop?city=`, `GET /shop/studio/<id>`; server/README.md "Shop"). The studio is the seller: Brüce shows what it
// sells at the desk or in its webshop, shows planned drops with Notify me, and reminds. Nothing here takes money or
// an address, and no product carries a Bruce or Brüce mark. Prices are in öre and include VAT, as the Bruce API's.
// The same logic lives in docs/app/js/shop.js; ShopTests checks both against the same cases.
// SampleShop.swift lays clearly marked sample listings over the real catalogue (`sample`); the server never sees them.

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
    /// A sample listing (SampleShop.swift): made on this device, never decoded from the server, never for sale.
    var sample = false

    init(id: String, studioId: Int, title: String, kind: ProductKind, description: String? = nil, priceOre: Int, vatRate: Int = 25, fulfilment: Fulfilment,
         linkUrl: String? = nil, variants: [ProductVariant] = [], sample: Bool = false) {
        self.id = id; self.studioId = studioId; self.title = title; self.kind = kind; self.description = description; self.priceOre = priceOre
        self.vatRate = vatRate; self.fulfilment = fulfilment; self.linkUrl = linkUrl; self.variants = variants; self.sample = sample
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
    /// The operator marked it ready for pickup (the feed's `ready`; the server sent "Ready for pickup").
    var ready = false
    /// Tied to a challenge the member finished (`GET /me/shop`): only they see it.
    var unlocked = false
    /// A sample drop (SampleShop.swift): Reserve and Notify me only answer "Sample item, not for sale".
    var sample = false

    init(id: String, studioId: Int, productId: String, challengeId: String? = nil, title: String, opensAt: Int, closesAt: Int, minQty: Int = 0, maxQty: Int? = nil,
         reserved: Int = 0, pickupFrom: String? = nil, linkUrl: String? = nil, ready: Bool = false, unlocked: Bool = false, sample: Bool = false) {
        self.id = id; self.studioId = studioId; self.productId = productId; self.challengeId = challengeId; self.title = title; self.opensAt = opensAt
        self.closesAt = closesAt; self.minQty = minQty; self.maxQty = maxQty; self.reserved = reserved; self.pickupFrom = pickupFrom; self.linkUrl = linkUrl
        self.ready = ready; self.unlocked = unlocked; self.sample = sample
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
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        unlocked = try c.decodeIfPresent(Bool.self, forKey: .unlocked) ?? false
    }

    /// Before the window, in it, after it, and once the studio has it at the desk.
    enum State { case upcoming, open, closed, ready }

    var opens: Date { Date(timeIntervalSince1970: Double(opensAt) / 1000) }
    var closes: Date { Date(timeIntervalSince1970: Double(closesAt) / 1000) }
    func state(now: Date = Date()) -> State {
        if ready { return .ready }
        if now < opens { return .upcoming }
        return now < closes ? .open : .closed
    }
    /// "Closes in 2 d 14 h", "Opens in 5 d 3 h", "Closed", "Ready for pickup".
    func countdownText(now: Date = Date()) -> String {
        switch state(now: now) {
        case .upcoming: return "Opens in \(ShopClock.until(opens, now: now))"
        case .open: return "Closes in \(ShopClock.until(closes, now: now))"
        case .closed: return "Closed"
        case .ready: return Copy.shopReadyTitle
        }
    }
    /// Reserve (phase 3): the studio's own checkout, while the window is open. The studio sells; Brüce only links.
    func reserveURL(now: Date = Date()) -> URL? { state(now: now) == .open ? url : nil }
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
    /// The server has a Stripe key and the studio a connected account (phase 4): Buy opens Stripe Checkout on the studio's account.
    var checkout = false
    /// Shipping incl. VAT when the studio ships ("Ship to me · 49 kr"); nil = pickup only.
    var shippingOre: Int? = nil
    /// The storefront of sample listings (SampleShop.swift): the studio did not approve anything.
    var sample = false
    var id: Int { studioId }
    var webshop: URL? { ShopLink.https(webshopUrl) }
    var ships: Bool { shippingOre != nil }

    init(studioId: Int, sellerName: String, city: String, webshopUrl: String? = nil, pickupNote: String? = nil, consentAt: String, checkout: Bool = false, shippingOre: Int? = nil,
         sample: Bool = false) {
        self.studioId = studioId; self.sellerName = sellerName; self.city = city; self.webshopUrl = webshopUrl; self.pickupNote = pickupNote; self.consentAt = consentAt
        self.checkout = checkout; self.shippingOre = shippingOre; self.sample = sample
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        studioId = try c.decode(Int.self, forKey: .studioId)
        sellerName = try c.decode(String.self, forKey: .sellerName)
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        webshopUrl = try c.decodeIfPresent(String.self, forKey: .webshopUrl)
        pickupNote = try c.decodeIfPresent(String.self, forKey: .pickupNote)
        consentAt = try c.decode(String.self, forKey: .consentAt)
        checkout = try c.decodeIfPresent(Bool.self, forKey: .checkout) ?? false
        shippingOre = try c.decodeIfPresent(Int.self, forKey: .shippingOre)
    }
}

// MARK: - Checkout (phase 4)

/// How the member wants it: at the desk (free, the default) or shipped (where the studio ships; the address goes to Stripe).
enum Delivery: String, Codable, CaseIterable, Hashable {
    case pickup, ship
}

/// What the checkout sheet shows before Stripe takes over: one listing, its variant, the count, the delivery, the sums.
struct CheckoutDraft: Hashable {
    static let maxQty = 5
    var product: Product
    var storefront: Storefront
    var variant: ProductVariant?
    var qty = 1
    var delivery: Delivery = .pickup

    var subtotalOre: Int { product.priceOre * qty }
    var shippingOre: Int { delivery == .ship ? storefront.shippingOre ?? 0 : 0 }
    var totalOre: Int { subtotalOre + shippingOre }
    var vatOre: Int { ShopMoney.vatPart(totalOre, rate: product.vatRate) }
    /// "Bastu towel · Natural × 2".
    var itemLine: String { product.title + (variant.map { " · \($0.label)" } ?? "") + (qty > 1 ? " × \(qty)" : "") }
    /// Why it can't go to Stripe yet; nil when it can.
    var problem: String? {
        if !storefront.checkout { return Copy.shopNoCheckout }
        if !product.variants.isEmpty, variant == nil { return Copy.shopPickVariant }
        if let v = variant, !v.inStock { return Copy.shopOutOfStock }
        if delivery == .ship, !storefront.ships { return Copy.shopNoShipping }
        if !(1...Self.maxQty).contains(qty) { return "1 to \(Self.maxQty) of each" }
        return nil
    }
    var body: [String: Any] {
        var b: [String: Any] = ["productId": product.id, "qty": qty, "delivery": delivery.rawValue, "returnTo": "app"]
        if let v = variant { b["variantId"] = v.id }
        return b
    }
}

/// An order as `GET /me/orders` lists it: what was bought, the status, the pickup code, the seller. Never an address.
struct Order: Codable, Hashable, Identifiable {
    struct Item: Codable, Hashable {
        var productId: String
        var variantId: String? = nil
        var title: String
        var label: String? = nil
        var qty = 1
        var unitOre = 0
        /// "Bastu towel · Natural × 2".
        var line: String { title + (label.map { " · \($0)" } ?? "") + (qty > 1 ? " × \(qty)" : "") }
    }
    var id: String
    var studioId: Int
    var dropId: String? = nil
    var items: [Item] = []
    var totalOre: Int
    var vatOre = 0
    var delivery: Delivery = .pickup
    var status: String
    var statusText: String? = nil
    var pickupCode: String? = nil
    var sellerName: String? = nil
    var pickupNote: String? = nil
    var createdAt: String
    var updatedAt: String? = nil

    var created: Date? { BruceDate.parse(createdAt) }
    var isReady: Bool { status == "ready" }
    var isDone: Bool { ["collected", "delivered", "refunded"].contains(status) }
    /// "Ready for pickup", "Paid · being prepared for pickup" (the server's words, else ours).
    var statusLine: String { statusText ?? Order.statusText(status, delivery: delivery) }
    static func statusText(_ status: String, delivery: Delivery) -> String {
        switch status {
        case "paid": return delivery == .ship ? "Paid · being prepared" : "Paid · being prepared for pickup"
        case "printing": return "Being printed"
        case "shipped": return delivery == .ship ? "On its way" : "On its way to the studio"
        case "ready": return "Ready for pickup"
        case "delivered": return "Delivered"
        case "collected": return "Collected"
        case "refunded": return "Refunded"
        default: return status
        }
    }
    var symbol: String {
        switch status {
        case "ready": return "checkmark.seal.fill"
        case "shipped": return "shippingbox"
        case "printing": return "printer"
        case "delivered", "collected": return "checkmark.circle"
        case "refunded": return "arrow.uturn.backward.circle"
        default: return "bag"
        }
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
    /// Drops not over yet (or ready at the desk), soonest closing first.
    func liveDrops(now: Date = Date()) -> [Drop] { drops.filter { $0.state(now: now) != .closed }.sorted { $0.closesAt < $1.closesAt } }
    /// Home's drop card: an unlocked drop first (it is the member's), then a real drop closing first, then a sample.
    func homeDrop(now: Date = Date()) -> Drop? {
        let live = liveDrops(now: now)
        return live.first { $0.unlocked } ?? live.first { !$0.sample } ?? live.first
    }
    /// Any sample listing in it (SampleShop.swift): the Shop screen then says so at the top.
    var hasSamples: Bool { products.contains { $0.sample } }
    /// Something real in it: only then the footer says the studios approved the listings.
    var hasReal: Bool { products.contains { !$0.sample } }
    /// The drop a finished challenge unlocked, if the member has it (phase 3).
    func drop(forChallenge id: String) -> Drop? { drops.first { $0.challengeId == id && $0.unlocked } }

    /// Sample listings (SampleShop.swift) after the real ones; a studio with a real storefront keeps only its own.
    func overlaying(_ samples: ShopCatalog?) -> ShopCatalog {
        guard let samples, !samples.isEmpty else { return self }
        var c = self
        if c.city.isEmpty { c.city = samples.city }
        let real = Set(storefronts.map(\.studioId))
        let fronts = samples.storefronts.filter { !real.contains($0.studioId) }
        let ids = Set(fronts.map(\.studioId))
        c.storefronts += fronts
        c.products += samples.products.filter { ids.contains($0.studioId) }
        c.drops += samples.drops.filter { ids.contains($0.studioId) }
        return c
    }

    /// The member's unlocked drops and their products (`GET /me/shop`) laid over the public catalogue, by id.
    func merging(drops mine: [Drop], products theirs: [Product]) -> ShopCatalog {
        var c = self
        for p in theirs where !c.products.contains(where: { $0.id == p.id }) { c.products.append(p) }
        for d in mine {
            if let i = c.drops.firstIndex(where: { $0.id == d.id }) { c.drops[i] = d } else { c.drops.append(d) }
        }
        return c
    }

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
    /// `GET /me/shop`: the drops the member watches, on every device, and the drops a finished challenge unlocked.
    struct Mine: Decodable {
        var notify: [String] = []
        var drops: [Drop] = []
        var products: [Product] = []
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            notify = try c.decodeIfPresent([String].self, forKey: .notify) ?? []
            drops = ((try? c.decodeIfPresent([LossyItem<Drop>].self, forKey: .drops)) ?? nil)?.compactMap(\.value) ?? []
            products = ((try? c.decodeIfPresent([LossyItem<Product>].self, forKey: .products)) ?? nil)?.compactMap(\.value) ?? []
        }
        enum CodingKeys: String, CodingKey { case notify, drops, products }
    }
    static func mine(session: Session) async throws -> Mine {
        try JSONDecoder().decode(Mine.self, from: try await BruceAPI.send(AutoBookServer.request("GET", "me/shop", session: session)))
    }
    /// `POST /checkout`: a Stripe Checkout Session on the studio's account; the app opens the URL in the browser.
    struct Checkout: Decodable { let url: String; let sessionId: String?; let totalOre: Int?; let vatOre: Int? }
    static func checkout(_ draft: CheckoutDraft, session: Session) async throws -> Checkout {
        try JSONDecoder().decode(Checkout.self, from: try await BruceAPI.send(AutoBookServer.request("POST", "checkout", session: session, body: draft.body)))
    }
    /// `GET /me/orders`: a broken row is skipped, not the list.
    struct Orders: Decodable {
        var orders: [Order] = []
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            orders = (try c.decodeIfPresent([LossyItem<Order>].self, forKey: .orders) ?? []).compactMap(\.value)
        }
        enum CodingKeys: String, CodingKey { case orders }
    }
    static func orders(session: Session) async throws -> [Order] {
        try JSONDecoder().decode(Orders.self, from: try await BruceAPI.send(AutoBookServer.request("GET", "me/orders", session: session))).orders
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
    /// Something is listed in the city: Home's Shop section, the studio rails and the towel card show only then. Sample
    /// listings (SampleShop.swift) count: with "Show sample shop" on, the shop is there to look at.
    var showsShop: Bool { shop?.isEmpty == false }
    /// Menu › Orders: only where a real shop is listed or something was bought (a sample shop has no orders).
    var showsOrders: Bool { shopReal?.isEmpty == false || !orders.isEmpty }

    /// Loads the city's catalogue: the demo's in demo mode, else `GET /shop?city=` at most every 10 minutes (or `force`).
    /// A failed read keeps whatever is shown; with the server switched off nothing real is listed. Sample listings are
    /// laid over it by `shop` and need no server.
    func loadShop(force: Bool = false) async {
        if AppModel.demo { if shopReal == nil { loadDemoShop() }; return }
        // The samples pick studios by the visit history; Home's For you reads it as well, so it is usually there already.
        if showSampleShop, tokenUsable, visitHistory == nil { Task { await fetchVisitHistory() } }
        guard AutoBookServer.isConfigured, let code = city?.code ?? (cityId == 1 ? "STO" : nil) else { shopReal = nil; return }
        if !force, let at = shopFetchedAt, Date().timeIntervalSince(at) < 600, shopReal?.city == code { return }
        guard !shopLoading else { return }
        shopLoading = true
        defer { shopLoading = false }
        if let c = try? await ShopServer.catalogue(city: code) { shopReal = c; shopFetchedAt = Date() }
        // Notify me on every device, and the drops a finished challenge unlocked, laid over the catalogue.
        if tokenUsable, let s = session, AutoBookServer.booksForMe, let mine = try? await ShopServer.mine(session: s) {
            shopNotify = Set(mine.notify)
            if let c = shopReal { shopReal = c.merging(drops: mine.drops, products: mine.products) }
        }
    }

    /// The reward of a finished challenge (phase 3): its drop, only once the server unlocked it for the member.
    func rewardDrop(forChallenge id: String) -> Drop? { shop?.drop(forChallenge: id) }

    func shopStorefront(_ studioId: Int) -> Storefront? { shop?.storefront(studioId) }
    func shopProducts(for studioId: Int) -> [Product] { shop?.products(for: studioId) ?? [] }
    func shopProduct(_ id: String) -> Product? { shop?.product(id) }
    /// The drop for a product, if it has one.
    func shopDrop(for product: Product) -> Drop? { shop?.drop(for: product) }
    func isNotified(_ dropId: String) -> Bool { shopNotify.contains(dropId) }

    /// "Forgot your towel?" after a check-in: a Wellness studio (sauna, spa) whose storefront lists a towel. Never a sample.
    func towelPrompt(studioId: Int) -> Product? {
        guard isWellness(studioId: studioId) else { return nil }
        return shopReal?.towel(for: studioId)
    }

    /// Notify me on a drop: a push and an email from our server when the pre-order opens. Needs the server; the demo pretends.
    func setNotify(_ drop: Drop, _ on: Bool) async {
        if drop.sample { flashSample(); return }
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
        guard !AppModel.demo, AutoBookServer.isConfigured, !SampleShop.isSample(id), !shopTapped.contains(id) else { return }
        shopTapped.insert(id)
        Task { await ShopServer.tap(productId: id) }
    }

    /// Opens Home › Shop.
    func showShop() {
        dismissSheets()
        stacks[.home] = [.shop]
        tab = .home
    }

    // MARK: Checkout (phase 4)

    /// Buy is offered only where the server and the studio can take the payment (`Storefront.checkout`).
    func canBuy(_ product: Product) -> Bool { shopStorefront(product.studioId)?.checkout == true }

    /// The checkout sheet's draft for a listing: its first in-stock variant picked, pickup by default.
    func checkoutDraft(for product: Product, delivery: Delivery = .pickup, variant: ProductVariant? = nil) -> CheckoutDraft? {
        guard let front = shopStorefront(product.studioId) else { return nil }
        return CheckoutDraft(product: product, storefront: front, variant: variant ?? product.inStockVariants.first, qty: 1, delivery: front.ships ? delivery : .pickup)
    }

    /// Opens Stripe Checkout for the draft: the URL to show in the browser (SFSafariViewController on the iPhone), or nil
    /// with a toast. The demo opens nothing. Apple's guideline 3.1.3(e): physical goods are never in-app purchases.
    func startCheckout(_ draft: CheckoutDraft) async -> URL? {
        if draft.product.sample { flashSample(); return nil }
        if let p = draft.problem { flash(p); return nil }
        if AppModel.demo { flash("Demo: Stripe Checkout would open now (offline, nothing sent)"); return nil }
        guard tokenUsable, let s = session else { present(.login); return nil }
        guard AutoBookServer.isConfigured else { flash(Copy.shopNoCheckout); return nil }
        do {
            let r = try await ShopServer.checkout(draft, session: s)
            guard let u = ShopLink.https(r.url) else { flash(Copy.shopNoCheckout); return nil }
            return u
        } catch { flash(Challenge.message(error)); return nil }
    }

    /// Menu › Orders: the demo's orders in demo mode, else `GET /me/orders`. A failed read keeps what is shown.
    func loadOrders() async {
        if AppModel.demo { if orders.isEmpty { orders = Order.demo }; return }
        guard tokenUsable, let s = session, AutoBookServer.isConfigured else { return }
        if let list = try? await ShopServer.orders(session: s) { orders = list; ordersLoaded = true }
    }

    /// Back from Stripe (`bruece://orders?paid=…`) or an order push: Menu › Orders, read again.
    func showOrders() {
        dismissSheets()
        present(.orders)
        Task { await loadOrders() }
    }
}
