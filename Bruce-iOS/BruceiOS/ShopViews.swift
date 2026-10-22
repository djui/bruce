import SwiftUI
import SafariServices

// Studio shop on the iPhone (Shop.swift): Home's Shop section with the drop card, Home › Shop with its chips, a
// product page, the "Shop at the desk" rail on a studio page and the "Forgot your towel?" card on the ticket after a
// check-in at a sauna. Everything shows only while the city's catalogue has something in it (`m.showsShop`). The
// studio sells: the buttons say "Ask at the desk" or open its webshop, and Notify me only reminds. Sample listings
// (SampleShop.swift) wear a "Sample" tag and their buttons only say "Sample item, not for sale".

/// A product's picture: the kind's tint and symbol (listings carry no photos; nothing is loaded from anywhere).
struct ProductArt: View {
    let kind: ProductKind
    var corner: CGFloat = 18
    var symbolSize: CGFloat = 34
    static func tint(_ k: ProductKind) -> Color {
        switch k {
        case .towel: Color(light: Color(red: 0.95, green: 0.91, blue: 0.84), dark: Color(red: 0.23, green: 0.20, blue: 0.15))
        case .mat: Color(light: Color(red: 0.88, green: 0.92, blue: 0.85), dark: Color(red: 0.16, green: 0.20, blue: 0.14))
        case .socks: Color(light: Color(red: 0.87, green: 0.91, blue: 0.95), dark: Color(red: 0.12, green: 0.17, blue: 0.21))
        case .apparel: Color(light: Color(red: 0.93, green: 0.97, blue: 0.77), dark: Color(red: 0.18, green: 0.21, blue: 0.07))
        case .sauna: Color(light: Color(red: 0.95, green: 0.88, blue: 0.87), dark: Color(red: 0.23, green: 0.15, blue: 0.14))
        case .other: Color(light: Color(red: 0.91, green: 0.91, blue: 0.93), dark: Color(red: 0.17, green: 0.17, blue: 0.18))
        }
    }
    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Self.tint(kind))
            .overlay { Image(systemName: kind.symbol).font(.system(size: symbolSize, weight: .light)).foregroundStyle(Theme.ink.opacity(0.55)) }
            .accessibilityHidden(true)
    }
}

/// "SAMPLE" on a listing that is not real (SampleShop.swift), on the picture, the drop card and the product page.
struct SampleTag: View {
    var body: some View {
        Text(Copy.shopSampleTag.uppercased()).bruceFont(10, weight: .heavy, width: .expanded).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.black.opacity(0.78), in: .capsule)
    }
}

/// The line at the top of Home › Shop while a sample listing is in it.
struct SampleNote: View {
    var body: some View {
        Label(Copy.shopSampleNote, systemImage: "info.circle").bruceFont(13, weight: .semibold).fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(Theme.lime.opacity(0.14)), in: .rect(cornerRadius: 16))
    }
}

/// A product in the Shop grid and the studio rail: picture, title, "449 kr · Ångan".
struct ProductTile: View {
    @Environment(AppModel.self) var m
    let product: Product
    var compact = false
    var body: some View {
        NavigationLink(value: Route.product(product.id)) {
            VStack(alignment: .leading, spacing: 4) {
                ProductArt(kind: product.kind, corner: 16, symbolSize: compact ? 30 : 36).aspectRatio(compact ? 4 / 3 : 2 / 1, contentMode: .fit)
                    .overlay(alignment: .topLeading) { if product.sample { SampleTag().padding(6) } }
                Text(product.title).bruceFont(14, weight: .bold).lineLimit(1).padding(.top, 2)
                HStack(spacing: 4) {
                    Text(product.priceText).bruceFont(13, weight: .heavy)
                    if !compact {
                        Text("· \(shortStudio)").bruceFont(12).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(product.sample ? "Sample, " : "")\(product.title), \(product.priceText), \(m.studioName(product.studioId))")
    }
    /// "Yogaloft", "Kärnan", "Ångan": the studio's first word, as the mockup lists them.
    var shortStudio: String { String(m.studioName(product.studioId).split(separator: " ").first ?? "") }
}

/// "DROP" or "UNLOCKED" as a lime tag.
struct DropTag: View {
    var unlocked = false
    var body: some View {
        Text((unlocked ? Copy.shopUnlocked : Copy.shopDropTag).uppercased()).bruceFont(10, weight: .heavy, width: .expanded).foregroundStyle(.black)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.lime, in: .capsule)
    }
}

/// A drop (mockup 1): "DROP" tag, the title, where to pick it up, the countdown, "31 of 40" and a meter, with Notify me
/// before it opens, Reserve while it is open (the studio's own checkout) and "Ready for pickup" once it is at the desk.
struct DropCard: View {
    @Environment(AppModel.self) var m
    @Environment(\.openURL) private var openURL
    let drop: Drop
    var body: some View {
        let product = m.shopProduct(drop.productId)
        let on = m.isNotified(drop.id)
        NavigationLink(value: Route.product(drop.productId)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    DropTag(unlocked: drop.unlocked)
                    if drop.sample { SampleTag() }
                    Spacer()
                    Image(systemName: product?.kind.symbol ?? "tshirt").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.white.opacity(0.35))
                }
                Text(drop.title).bruceDisplay(19, weight: .heavy).lineLimit(2).minimumScaleFactor(0.8)
                Text(Copy.shopPickup(m.studioName(drop.studioId))).bruceFont(13).opacity(0.85)
                HStack {
                    Label(drop.countdownText(), systemImage: "clock").bruceFont(12, weight: .bold)
                    Spacer()
                    Text(drop.progressText).bruceFont(12, weight: .bold).monospacedDigit()
                }
                .padding(.top, 2)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(Theme.lime).frame(width: max(6, g.size.width * drop.progress))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                HStack(spacing: 10) {
                    if let product { Text(product.priceText).bruceFont(15, weight: .heavy) }
                    Spacer()
                    switch drop.state() {
                    case .open:
                        if drop.sample {
                            Button { m.flashSample() } label: { cardButton("Reserve", "arrow.up.right.square", lime: true) }.buttonStyle(.plain)
                        } else if let u = drop.reserveURL() {
                            Button { openURL(u) } label: { cardButton("Reserve", "arrow.up.right.square", lime: true) }.buttonStyle(.plain)
                        } else {
                            Button { Task { await m.setNotify(drop, !on) } } label: { cardButton(on ? "Notifying" : Copy.shopNotifyMe, on ? "bell.fill" : "bell", lime: !on) }
                                .buttonStyle(.plain).accessibilityLabel(on ? "Notify me is on" : Copy.shopNotifyMe)
                        }
                    case .upcoming:
                        Button { Task { await m.setNotify(drop, !on) } } label: { cardButton(on ? "Notifying" : Copy.shopNotifyMe, on ? "bell.fill" : "bell", lime: !on) }
                            .buttonStyle(.plain).accessibilityLabel(on ? "Notify me is on" : Copy.shopNotifyMe)
                    case .ready: cardButton(Copy.shopReadyTitle, "checkmark.seal.fill", lime: true)
                    case .closed: cardButton("Closed", "clock", lime: false)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.12, green: 0.44, blue: 0.47), Color(red: 0.06, green: 0.18, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(drop.sample ? "Sample drop" : "Drop"): \(drop.title), \(drop.countdownText()), \(drop.progressText) reserved, \(Copy.shopPickup(m.studioName(drop.studioId)))")
    }

    func cardButton(_ title: String, _ symbol: String, lime: Bool) -> some View {
        Label(title, systemImage: symbol).bruceFont(14, weight: .bold)
            .foregroundStyle(lime ? .black : .white)
            .padding(.horizontal, 14).frame(height: 34)
            .background(lime ? Theme.lime : Color.white.opacity(0.22), in: .capsule)
    }
}

// MARK: - Home

/// Home, after Spotlight: the live drop as a card and a row of listings, with "Show all" into Home › Shop. Nothing while
/// the city has no listing.
struct ShopHomeSection: View {
    @Environment(AppModel.self) var m
    var body: some View {
        if let shop = m.shop, !shop.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(Copy.shopTitle.uppercased()).bruceHeading(19)
                    Spacer()
                    NavigationLink(value: Route.shop) { Text("Show all").bruceFont(15, weight: .semibold) }.buttonStyle(.glass)
                }
                .padding(.horizontal, Theme.gutter)
                if let d = shop.homeDrop() { DropCard(drop: d).padding(.horizontal, Theme.gutter) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(shop.products.prefix(8)) { p in ProductTile(product: p).frame(width: 150) }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .scrollClipDisabled()
            }
            .padding(.top, 26)
        }
    }
}

// MARK: - Home › Shop

/// The city's catalogue (mockup 1): chips (All, Drops, Towels, Mats, Grip socks…), the live drops and a grid of listings.
struct ShopView: View {
    @Environment(AppModel.self) var m
    /// nil = All; "drops" = the drops; else a kind.
    @State private var chip: String?
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let shop = m.shop ?? ShopCatalog()
        let drops = shop.liveDrops()
        let kind = chip.flatMap(ProductKind.init(rawValue:))
        let products = chip == "drops" ? [] : shop.filtered(kind: kind)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeading(text: Copy.shopTitle)
                if shop.hasSamples { SampleNote() }
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer {
                        HStack(spacing: 8) {
                            GlassChip("All", selected: chip == nil) { chip = nil }
                            if !drops.isEmpty { GlassChip("Drops", selected: chip == "drops") { chip = "drops" } }
                            ForEach(shop.kinds, id: \.self) { k in GlassChip(k.title, selected: chip == k.rawValue) { chip = k.rawValue } }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .padding(.horizontal, -Theme.gutter)
                if chip == nil || chip == "drops" {
                    ForEach(drops) { d in DropCard(drop: d) }
                }
                if !products.isEmpty {
                    if chip == nil { Text("NEAR YOU").bruceHeading(18).padding(.top, 6) }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(products) { p in ProductTile(product: p) }
                    }
                } else if chip != "drops" {
                    EmptyState(system: "bag", text: shop.isEmpty ? "Nothing listed in \(m.cityName) yet." : Copy.shopEmptyKind)
                }
                if shop.hasReal { Text(Copy.shopCatalogFooter).bruceFont(13).foregroundStyle(Theme.secondary).padding(.top, 8) }
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 30)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .pushedPage(Copy.shopTitle)
        .onAppear { if let k = m.demoShopKind { chip = k; m.demoShopKind = nil } }
        .task { await m.loadShop() }
        .refreshable { await m.loadShop(force: true) }
    }
}

// MARK: - Product page

/// Mockup 3 as phase 2 shows it: the picture, title, seller and description, the price incl. VAT, the variants, the
/// drop's window and Notify me when it is one, and "Ask at the desk" or the webshop. Opening it counts one anonymous tap.
struct ProductView: View {
    @Environment(AppModel.self) var m
    @Environment(\.openURL) private var openURL
    let productId: String
    @State private var variantId: String?
    @State private var delivery: Delivery = .pickup

    var body: some View {
        Group {
            if let p = m.shopProduct(productId) {
                content(p)
            } else {
                EmptyState(system: "bag", text: m.shop == nil ? "Loading…" : "This listing is no longer there.")
            }
        }
        .pushedPage("")
        .task { await m.loadShop(); m.tapProduct(productId) }
    }

    func content(_ p: Product) -> some View {
        let front = m.shopStorefront(p.studioId)
        let drop = m.shopDrop(for: p)
        let studio = m.studioName(p.studioId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ProductArt(kind: p.kind, corner: 26, symbolSize: 72).frame(height: 220)
                    .overlay(alignment: .topLeading) { if p.sample { SampleTag().padding(12) } }
                Text(p.title.uppercased()).bruceScreenTitle(26).lineLimit(3).minimumScaleFactor(0.7)
                Text([studio, p.description].compactMap { $0 }.joined(separator: " · ")).bruceFont(14).foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(p.priceText).bruceFont(24, weight: .heavy).monospacedDigit()
                    Text(Copy.shopInclVAT).bruceFont(13).foregroundStyle(Theme.secondary)
                    Spacer()
                }
                if !p.variants.isEmpty { variants(p) }
                if let drop { dropBlock(drop, p, studio) }
                if buyable(p, drop), let front { deliveryBlock(p, front, studio) }
                NavigationLink(value: Route.studio(p.studioId)) {
                    InfoRow(title: studio, subtitle: front.map { Copy.shopSoldBy($0.sellerName, desk: p.fulfilment == .desk && !$0.sample, checkout: $0.checkout) } ?? "Studio page").padding(14)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                if let note = front?.pickupNote {
                    Label(note, systemImage: "mappin.and.ellipse").bruceFont(14).foregroundStyle(Theme.secondary)
                }
                Text(p.sample ? Copy.shopSampleProductNote : Copy.shopNotAffiliated).bruceFont(13).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.gutter).padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom) { actions(p, front, drop).padding(Theme.gutter) }
    }

    /// Buy is on the page when the studio takes payment through Brüce (phase 4) and the listing is open to buy: no drop,
    /// or a drop whose window is open. A drop that is ready or closed is only a notice.
    func buyable(_ p: Product, _ drop: Drop?) -> Bool { m.canBuy(p) && (drop == nil || drop?.state() == .open) }

    /// The one picked, else the first in stock (what the checkout sheet starts with).
    func picked(_ p: Product) -> ProductVariant? { p.variants.first { $0.id == variantId && $0.inStock } ?? p.inStockVariants.first }

    func variants(_ p: Product) -> some View {
        let pickable = m.canBuy(p)
        let current = picked(p)?.id
        return VStack(alignment: .leading, spacing: 8) {
            Text(p.kind == .apparel ? "SIZES" : "OPTIONS").bruceFont(11, weight: .heavy, width: .expanded).foregroundStyle(Theme.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        ForEach(p.variants) { v in
                            if pickable && v.inStock {
                                GlassChip(selected: v.id == current, action: { variantId = v.id }) { Text(v.label) }
                            } else {
                                Text(v.label + (v.inStock ? "" : " · out")).bruceFont(14, weight: .semibold).foregroundStyle(v.inStock ? Theme.ink : Theme.tertiary)
                                    .padding(.horizontal, 14).frame(height: 34).glassEffect(.regular, in: .capsule)
                            }
                        }
                    }
                }
            }
        }
    }

    /// "How do you want it?": pick up at the desk (free, the default) or shipped where the studio ships (mockup 5).
    func deliveryBlock(_ p: Product, _ front: Storefront, _ studio: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.shopHowTitle.uppercased()).bruceFont(11, weight: .heavy, width: .expanded).foregroundStyle(Theme.secondary)
            DeliveryRow(title: Copy.shopPickupAt(studio), subtitle: Copy.shopPickupFree, symbol: "building.2", selected: delivery == .pickup || !front.ships) { delivery = .pickup }
            if front.ships {
                DeliveryRow(title: Copy.shopShipPrice(front), subtitle: Copy.shopShipNote, symbol: "shippingbox", selected: delivery == .ship) { delivery = .ship }
            }
        }
    }

    /// The drop's window: "Pre-order until Sun 7 Feb · one print run", the countdown, "31 of 40" and Notify me; "Ready for
    /// pickup" once the studio has it at the desk, "The pre-order has closed" after the window.
    func dropBlock(_ d: Drop, _ p: Product, _ studio: String) -> some View {
        let on = m.isNotified(d.id)
        let state = d.state()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                DropTag(unlocked: d.unlocked)
                if d.sample { SampleTag() }
                Spacer()
                Label(d.countdownText(), systemImage: state == .ready ? "checkmark.seal.fill" : "clock").bruceFont(13, weight: .bold)
            }
            if state == .ready {
                Text(Copy.shopReadyBody(m.shopStorefront(d.studioId))).bruceFont(14).fixedSize(horizontal: false, vertical: true)
            } else if state == .closed {
                Text(Copy.shopDropClosed).bruceFont(14)
            } else if d.unlocked {
                Text(Copy.shopFinisherHint + " " + Copy.shopDropLine(d) + ".").bruceFont(14).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Copy.shopDropLine(d)).bruceFont(14).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(Copy.shopPickup(studio)).bruceFont(13).foregroundStyle(Theme.secondary)
                Spacer()
                Text(d.progressText).bruceFont(13, weight: .bold).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.chipGrey)
                    Capsule().fill(Theme.lime).frame(width: max(6, g.size.width * d.progress))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            if state == .upcoming || state == .open {
                Toggle(isOn: Binding(get: { on }, set: { v in Task { await m.setNotify(d, v) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.shopNotifyMe).bruceFont(16, weight: .semibold)
                        Text(state == .open ? "A push and an email when it is ready for pickup." : Copy.shopNotifyHint).bruceFont(13).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.limeInk)
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(Theme.lime.opacity(0.12)), in: .rect(cornerRadius: 22))
    }

    /// No checkout yet. A drop's Reserve opens the studio's own checkout while the window is open; else the desk, the
    /// product's own page or the studio's webshop.
    @ViewBuilder func actions(_ p: Product, _ front: Storefront?, _ drop: Drop?) -> some View {
        if p.sample {
            // Sample: the buttons are there to look at; each only says it is not for sale.
            let open = drop?.state() == .open
            LimeButton(title: open ? Copy.shopReserve(p.priceText) : p.fulfilment == .link ? Copy.shopWebshop : Copy.shopBuy(p.priceText),
                       systemImage: open || p.fulfilment == .link ? "arrow.up.right.square" : "bag") { m.flashSample() }
        } else if buyable(p, drop), let front {
            let draft = CheckoutDraft(product: p, storefront: front, variant: picked(p), qty: 1, delivery: front.ships ? delivery : .pickup)
            LimeButton(title: Copy.shopBuy(ShopMoney.kr(draft.totalOre)), systemImage: "bag") {
                m.checkoutDraft = draft
                m.present(.shopCheckout(p.id))
            }
        } else if let drop, drop.state() == .open {
            if let u = drop.reserveURL() {
                VStack(spacing: 6) {
                    Button { openURL(u) } label: {
                        Label(Copy.shopReserve(p.priceText), systemImage: "arrow.up.right.square").bruceFont(17, weight: .bold).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).frame(height: 40)
                    }
                    .buttonStyle(.glassProminent).tint(Theme.lime).controlSize(.large)
                    Text(Copy.shopReserveHint).bruceFont(11).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                }
            } else {
                Label(Copy.shopReserveAtDesk, systemImage: "person.wave.2").bruceFont(15, weight: .semibold)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .glassEffect(.regular, in: .capsule)
            }
        } else if let drop, drop.state() == .ready {
            Label(Copy.shopReadyTitle, systemImage: "checkmark.seal.fill").bruceFont(17, weight: .bold).foregroundStyle(.black)
                .frame(maxWidth: .infinity).frame(height: 40)
                .glassEffect(.regular.tint(Theme.lime), in: .capsule)
        } else if let drop, drop.state() == .upcoming {
            let on = m.isNotified(drop.id)
            if on {
                Button { Task { await m.setNotify(drop, false) } } label: {
                    Label("Notify me is on", systemImage: "bell.fill").bruceFont(17, weight: .bold).frame(maxWidth: .infinity).frame(height: 40)
                }
                .buttonStyle(.glass).controlSize(.large)
            } else {
                LimeButton(title: Copy.shopNotifyMe, systemImage: "bell") { Task { await m.setNotify(drop, true) } }
            }
        } else if let u = p.url ?? front?.webshop, p.fulfilment != .desk || p.url != nil {
            Button { openURL(u) } label: {
                Label(p.url != nil ? "Open in the webshop" : Copy.shopWebshop, systemImage: "arrow.up.right.square").bruceFont(17, weight: .bold).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 40)
            }
            .buttonStyle(.glassProminent).tint(Theme.lime).controlSize(.large)
        } else {
            Label(Copy.shopAskAtDesk, systemImage: "person.wave.2").bruceFont(17, weight: .bold)
                .frame(maxWidth: .infinity).frame(height: 40)
                .glassEffect(.regular, in: .capsule)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// One way to get it, with a check mark on the chosen one.
struct DeliveryRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).bruceFont(18).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).bruceFont(16, weight: .semibold).foregroundStyle(Theme.ink)
                    Text(subtitle).bruceFont(13).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").bruceFont(22).foregroundStyle(selected ? Theme.limeInk : Theme.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(Theme.lime.opacity(0.18)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Checkout (phase 4)

/// Mockup 5: what is being bought, how many, how it comes, the sums with the VAT, who sells it, and Pay, which opens
/// Stripe Checkout on the studio's account in an in-app Safari view (never an in-app purchase: physical goods,
/// App Review guideline 3.1.3(e)). Brüce never sees the card or an address.
struct ShopCheckoutSheet: View {
    @Environment(AppModel.self) var m
    let productId: String
    @State private var draft: CheckoutDraft?
    @State private var safari: SafariItem?
    @State private var busy = false

    var body: some View {
        Group {
            if let d = draft { content(d) } else { EmptyState(system: "bag", text: "This listing is no longer there.") }
        }
        .sheetChrome(Copy.shopCheckoutTitle)
        .onAppear { if draft == nil, let p = m.shopProduct(productId) { draft = m.checkoutDraft?.product.id == p.id ? m.checkoutDraft : m.checkoutDraft(for: p) } }
        .fullScreenCover(item: $safari) { item in SafariView(url: item.url).ignoresSafeArea() }
    }

    func content(_ d: CheckoutDraft) -> some View {
        let studio = m.studioName(d.product.studioId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ProductArt(kind: d.product.kind, corner: 14, symbolSize: 26).frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.product.title).bruceFont(17, weight: .bold)
                        Text([d.variant?.label, studio].compactMap { $0 }.joined(separator: " · ")).bruceFont(13).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Text(ShopMoney.exact(d.product.priceOre)).bruceFont(15, weight: .semibold).monospacedDigit()
                }
                HStack {
                    Text("Quantity").bruceFont(16, weight: .semibold)
                    Spacer()
                    Stepper(value: bind(\.qty), in: 1...CheckoutDraft.maxQty) { Text("\(d.qty)").bruceFont(17, weight: .bold).monospacedDigit() }
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(Copy.shopHowTitle.uppercased()).bruceFont(11, weight: .heavy, width: .expanded).foregroundStyle(Theme.secondary)
                    DeliveryRow(title: Copy.shopPickupAt(studio), subtitle: d.storefront.pickupNote ?? Copy.shopPickupFree, symbol: "building.2", selected: d.delivery == .pickup) { draft?.delivery = .pickup }
                    if d.storefront.ships {
                        DeliveryRow(title: Copy.shopShipPrice(d.storefront), subtitle: Copy.shopShipNote, symbol: "shippingbox", selected: d.delivery == .ship) { draft?.delivery = .ship }
                    }
                }
                VStack(spacing: 8) {
                    sum(d.itemLine, ShopMoney.exact(d.subtotalOre))
                    if d.delivery == .ship { sum("Shipping", ShopMoney.exact(d.shippingOre)) }
                    Divider()
                    HStack {
                        Text("Total").bruceFont(17, weight: .bold)
                        Spacer()
                        Text(ShopMoney.exact(d.totalOre)).bruceFont(20, weight: .heavy).monospacedDigit()
                    }
                    sum(Copy.shopVatLine(d.product.vatRate), ShopMoney.exact(d.vatOre), muted: true)
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                Text(Copy.shopSeller(d.storefront, vicinity: m.studio(d.product.studioId)?.vicinity)).bruceFont(13).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.gutter).padding(.bottom, 120)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let problem = d.problem {
                    Text(problem).bruceFont(13).foregroundStyle(Theme.red).multilineTextAlignment(.center)
                }
                LimeButton(title: Copy.shopPay(ShopMoney.exact(d.totalOre)), systemImage: "lock.fill") { pay(d) }
                    .disabled(busy || d.problem != nil).opacity(d.problem != nil ? 0.6 : 1)
                Text(Copy.shopPayMethods).bruceFont(12).foregroundStyle(Theme.secondary)
                Label(Copy.shopPaySafety, systemImage: "lock.shield").bruceFont(11).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.gutter)
        }
    }

    func sum(_ label: String, _ value: String, muted: Bool = false) -> some View {
        HStack {
            Text(label).bruceFont(14).foregroundStyle(muted ? Theme.secondary : Theme.ink)
            Spacer()
            Text(value).bruceFont(14, weight: muted ? .regular : .semibold).foregroundStyle(muted ? Theme.secondary : Theme.ink).monospacedDigit()
        }
    }

    func bind<T>(_ key: WritableKeyPath<CheckoutDraft, T>) -> Binding<T> {
        Binding(get: { draft![keyPath: key] }, set: { draft?[keyPath: key] = $0 })
    }

    func pay(_ d: CheckoutDraft) {
        busy = true
        Task {
            if let u = await m.startCheckout(d) { safari = SafariItem(url: u) }
            busy = false
        }
    }
}

struct SafariItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Stripe Checkout in SFSafariViewController: the member stays in the app, Safari's cookies and Apple Pay are there,
/// and the success URL (bruece://orders) brings them back to Menu › Orders.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController(url: url)
        c.dismissButtonStyle = .close
        c.preferredControlTintColor = UIColor(Theme.limeInk)
        return c
    }
    func updateUIViewController(_ c: SFSafariViewController, context: Context) {}
}

// MARK: - Orders

/// Menu › Orders: what the member bought from studio shops, the status as the server words it, and the pickup code.
struct OrdersView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        List {
            if m.orders.isEmpty {
                EmptyState(system: "bag", text: m.ordersLoaded || AppModel.demo ? Copy.shopOrdersEmpty : "Loading…").listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(m.orders) { o in
                OrderRow(order: o)
            }
            Section { } footer: { Text(Copy.shopOrdersNote) }
        }
        .listStyle(.insetGrouped)
        .sheetChrome(Copy.shopOrdersTitle)
        .task { await m.loadOrders() }
        .refreshable { await m.loadOrders() }
    }
}

struct OrderRow: View {
    @Environment(AppModel.self) var m
    let order: Order
    var body: some View {
        let o = order
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: o.symbol).bruceFont(20).foregroundStyle(o.isReady ? Theme.limeInk : Theme.secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(o.items.map(\.line).joined(separator: ", ")).bruceFont(16, weight: .semibold)
                    Text([o.sellerName ?? m.studioName(o.studioId), Copy.shopOrderDate(o)].filter { !$0.isEmpty }.joined(separator: " · ")).bruceFont(13).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(ShopMoney.kr(o.totalOre)).bruceFont(15, weight: .semibold).monospacedDigit()
            }
            Text(o.statusLine).bruceFont(13, weight: .bold).foregroundStyle(o.isReady ? Color.black : Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(o.isReady ? Theme.lime : Theme.chipGrey))
            if let code = o.pickupCode, !o.isDone {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.shopPickupCode.uppercased()).bruceFont(11, weight: .heavy, width: .expanded).foregroundStyle(Theme.secondary)
                    Text(code).font(.system(size: 30, weight: .heavy, design: .monospaced)).kerning(4)
                    if let note = o.pickupNote { Text(note).bruceFont(13).foregroundStyle(Theme.secondary) }
                }
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Pickup code \(code.map(String.init).joined(separator: " "))")
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Studio page

/// "Shop at the desk" on a studio page (mockup 2): the listings as a rail, who sells them and how to pay.
struct ShopRail: View {
    @Environment(AppModel.self) var m
    @Environment(\.openURL) private var openURL
    let studioId: Int
    var body: some View {
        let products = m.shopProducts(for: studioId)
        if let front = m.shopStorefront(studioId), !products.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(Copy.shopAtDesk.uppercased()).bruceHeading(17)
                    Spacer()
                    Text("\(products.count) item\(products.count == 1 ? "" : "s")").bruceFont(13, weight: .semibold).foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5).glassEffect(.regular, in: .capsule)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(products) { p in ProductTile(product: p, compact: true).frame(width: 124) }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .padding(.horizontal, -Theme.gutter)
                .scrollClipDisabled()
                HStack {
                    Text(Copy.shopSoldBy(front.sellerName, desk: products.contains { $0.fulfilment == .desk } && !front.sample, checkout: front.checkout)).bruceFont(13).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 8)
                    if front.sample {
                        Button { m.flashSample() } label: { Label(Copy.shopWebshop, systemImage: "arrow.up.right.square").bruceFont(13, weight: .bold) }
                            .buttonStyle(.glass).controlSize(.small)
                    } else if let u = front.webshop {
                        Button { openURL(u) } label: { Label(Copy.shopWebshop, systemImage: "arrow.up.right.square").bruceFont(13, weight: .bold) }
                            .buttonStyle(.glass).controlSize(.small)
                    } else {
                        Text(Copy.shopAskAtDesk).bruceFont(13, weight: .bold).padding(.horizontal, 10).padding(.vertical, 6).glassEffect(.regular, in: .capsule)
                    }
                }
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }
}

// MARK: - After a check-in

/// "Forgot your towel?" on the ticket after a check-in at a sauna or spa whose storefront lists a towel (mockup 2).
struct TowelCard: View {
    @Environment(AppModel.self) var m
    let towel: Product
    var body: some View {
        Button { m.dismissSheets(); m.push(.product(towel.id)) } label: {
            HStack(spacing: 12) {
                ProductArt(kind: .towel, corner: 12, symbolSize: 22).frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.shopTowelTitle).bruceFont(15, weight: .bold)
                    Text(Copy.shopTowelBody(towel)).bruceFont(13).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            .foregroundStyle(Theme.ink)
            .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityLabel("\(Copy.shopTowelTitle) \(Copy.shopTowelBody(towel))")
    }
}
