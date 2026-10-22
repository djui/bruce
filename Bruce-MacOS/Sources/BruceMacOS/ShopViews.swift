import SwiftUI

// Studio shop on the Mac (Shop.swift; ShopViews.swift on the iPhone): Home's Shop section with the drop card, Home › Shop
// with its chips, a product page, the "Shop at the desk" rail on a studio page and "Forgot your towel?" on the ticket.
// Everything shows only while the city's catalogue has something in it. The studio sells; the buttons say "Ask at the
// desk" or open its webshop in the browser, and Notify me only reminds. Sample listings (SampleShop.swift) wear a
// "Sample" tag and their buttons only say "Sample item, not for sale".

/// A product's picture: the kind's tint and symbol (listings carry no photos).
struct ProductArt: View {
    let kind: ProductKind
    var corner: CGFloat = 14
    var symbolSize: CGFloat = 30
    static func tint(_ k: ProductKind) -> Color {
        switch k {
        case .towel: Color(red: 0.95, green: 0.91, blue: 0.84)
        case .mat: Color(red: 0.88, green: 0.92, blue: 0.85)
        case .socks: Color(red: 0.87, green: 0.91, blue: 0.95)
        case .apparel: Color(red: 0.93, green: 0.97, blue: 0.77)
        case .sauna: Color(red: 0.95, green: 0.88, blue: 0.87)
        case .other: Color(red: 0.91, green: 0.91, blue: 0.93)
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
        Text(Copy.shopSampleTag.uppercased()).font(.system(size: 10, weight: .heavy).width(.expanded)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.black.opacity(0.78)))
    }
}

/// The line at the top of Home › Shop while a sample listing is in it.
struct SampleNote: View {
    var body: some View {
        Label(Copy.shopSampleNote, systemImage: "info.circle").font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.lime.opacity(0.18)))
    }
}

/// A product in the grid and the studio rail: picture, title, "449 kr · Ångan".
struct ProductTile: View {
    @Environment(AppModel.self) var m
    let product: Product
    var compact = false
    var body: some View {
        Button { m.push(.product(product.id)) } label: {
            VStack(alignment: .leading, spacing: 3) {
                ProductArt(kind: product.kind, symbolSize: compact ? 26 : 32).aspectRatio(compact ? 4 / 3 : 2 / 1, contentMode: .fit)
                    .overlay(alignment: .topLeading) { if product.sample { SampleTag().padding(6) } }
                Text(product.title).font(.system(size: 14, weight: .bold)).lineLimit(1).padding(.top, 2)
                Text(product.priceText + (compact ? "" : " · " + String(m.studioName(product.studioId).split(separator: " ").first ?? "")))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A drop: "DROP" tag, the title, where to pick it up, the countdown, "31 of 40" and a meter, with Notify me.
struct DropCard: View {
    @Environment(AppModel.self) var m
    let drop: Drop
    var body: some View {
        let product = m.shopProduct(drop.productId)
        let on = m.isNotified(drop.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                DropTag(unlocked: drop.unlocked)
                if drop.sample { SampleTag() }
                Spacer()
                Image(systemName: product?.kind.symbol ?? "tshirt").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.white.opacity(0.35))
            }
            Button { m.push(.product(drop.productId)) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(drop.title).font(.system(size: 18, weight: .heavy).width(.expanded)).lineLimit(2)
                    Text(Copy.shopPickup(m.studioName(drop.studioId))).font(.system(size: 13)).opacity(0.85)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack {
                Label(drop.countdownText(), systemImage: "clock").font(.system(size: 12, weight: .bold))
                Spacer()
                Text(drop.progressText).font(.system(size: 12, weight: .bold)).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(Theme.lime).frame(width: max(6, g.size.width * drop.progress))
                }
            }
            .frame(height: 6)
            HStack {
                if let product { Text(product.priceText).font(.system(size: 15, weight: .heavy)) }
                Spacer()
                switch drop.state() {
                case .open where drop.sample:
                    Button { m.flashSample() } label: { cardButton("Reserve", "arrow.up.right.square", lime: true) }.buttonStyle(.plain)
                case .open where drop.reserveURL() != nil:
                    Button { NSWorkspace.shared.open(drop.reserveURL()!) } label: { cardButton("Reserve", "arrow.up.right.square", lime: true) }.buttonStyle(.plain)
                case .open, .upcoming:
                    Button { Task { await m.setNotify(drop, !on) } } label: { cardButton(on ? "Notifying" : Copy.shopNotifyMe, on ? "bell.fill" : "bell", lime: !on) }.buttonStyle(.plain)
                case .ready: cardButton(Copy.shopReadyTitle, "checkmark.seal.fill", lime: true)
                case .closed: cardButton("Closed", "clock", lime: false)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.12, green: 0.44, blue: 0.47), Color(red: 0.06, green: 0.18, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    func cardButton(_ title: String, _ symbol: String, lime: Bool) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 13, weight: .bold))
            .foregroundStyle(lime ? .black : .white)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(lime ? Theme.lime : Color.white.opacity(0.22)))
    }
}

/// "DROP" or "UNLOCKED" as a lime tag.
struct DropTag: View {
    var unlocked = false
    var body: some View {
        Text((unlocked ? Copy.shopUnlocked : Copy.shopDropTag).uppercased()).font(.system(size: 10, weight: .heavy).width(.expanded)).foregroundStyle(.black)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Theme.lime))
    }
}

// MARK: - Home

/// Home, after Spotlight: the live drop and a row of listings, with "Show all" into Home › Shop.
struct ShopHomeSection: View {
    @Environment(AppModel.self) var m
    var body: some View {
        if let shop = m.shop, !shop.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(Copy.shopTitle).font(.system(size: 24, weight: .bold))
                    Spacer()
                    Button("Show all") { m.push(.shop) }.buttonStyle(.plain).font(.system(size: 15, weight: .medium))
                }
                if let d = shop.homeDrop() { DropCard(drop: d) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(shop.products.prefix(8)) { p in ProductTile(product: p).frame(width: 150) }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 22)
        }
    }
}

// MARK: - Home › Shop

/// The city's catalogue: chips (All, Drops, Towels, Mats, Grip socks…), the live drops and a grid of listings.
struct ShopView: View {
    @Environment(AppModel.self) var m
    @State private var chip: String?
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let shop = m.shop ?? ShopCatalog()
        let drops = shop.liveDrops()
        let kind = chip.flatMap(ProductKind.init(rawValue:))
        let products = chip == "drops" ? [] : shop.filtered(kind: kind)
        VStack(spacing: 0) {
            NavBar(title: Copy.shopTitle, leading: .back) { m.pop() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if shop.hasSamples { SampleNote() }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chipButton("All", nil)
                            if !drops.isEmpty { chipButton("Drops", "drops") }
                            ForEach(shop.kinds, id: \.self) { k in chipButton(k.title, k.rawValue) }
                        }
                    }
                    if chip == nil || chip == "drops" { ForEach(drops) { d in DropCard(drop: d) } }
                    if !products.isEmpty {
                        if chip == nil { Text("Near you").font(.system(size: 20, weight: .bold)).padding(.top, 6) }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) { ForEach(products) { p in ProductTile(product: p) } }
                    } else if chip != "drops" {
                        Text(shop.isEmpty ? "Nothing listed in \(m.cityName) yet." : Copy.shopEmptyKind).foregroundStyle(Theme.secondary).padding(.top, 30)
                    }
                    if shop.hasReal { Text(Copy.shopCatalogFooter).font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.top, 8) }
                }
                .padding(Theme.gutter)
            }
        }
        .onAppear { if let k = m.demoShopKind { chip = k; m.demoShopKind = nil } }
        .task { await m.loadShop() }
    }

    func chipButton(_ title: String, _ key: String?) -> some View {
        Button { chip = key } label: {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(chip == key ? .white : Theme.ink)
                .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(chip == key ? Theme.ink : Theme.chipGrey))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Product page

struct ProductView: View {
    @Environment(AppModel.self) var m
    let productId: String
    @State private var variantId: String?
    @State private var delivery: Delivery = .pickup

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "", leading: .back) { m.pop() }
            if let p = m.shopProduct(productId) { content(p) }
            else { EmptyState(system: "bag", text: m.shop == nil ? "Loading…" : "This listing is no longer there.") }
        }
        .task { await m.loadShop(); m.tapProduct(productId) }
    }

    func content(_ p: Product) -> some View {
        let front = m.shopStorefront(p.studioId)
        let drop = m.shopDrop(for: p)
        let studio = m.studioName(p.studioId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ProductArt(kind: p.kind, corner: 18, symbolSize: 64).frame(height: 200)
                    .overlay(alignment: .topLeading) { if p.sample { SampleTag().padding(12) } }
                Text(p.title.uppercased()).font(Theme.screenTitle(24)).lineLimit(3).minimumScaleFactor(0.7)
                Text([studio, p.description].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(p.priceText).font(.system(size: 24, weight: .heavy)).monospacedDigit()
                    Text(Copy.shopInclVAT).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                if !p.variants.isEmpty {
                    let pickable = m.canBuy(p), current = picked(p)?.id
                    HStack(spacing: 8) {
                        ForEach(p.variants) { v in
                            Button { variantId = v.id } label: {
                                Text(v.label + (v.inStock ? "" : " · out")).font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(pickable && v.id == current ? .black : v.inStock ? Theme.ink : Theme.tertiary)
                                    .padding(.horizontal, 12).frame(height: 30).background(Capsule().fill(pickable && v.id == current ? Theme.lime : Theme.chipGrey))
                            }
                            .buttonStyle(.plain).disabled(!pickable || !v.inStock)
                        }
                    }
                }
                if let drop { dropBlock(drop, studio) }
                if buyable(p, drop), let front { deliveryBlock(p, front, studio) }
                actions(p, front)
                Button { m.push(.studio(p.studioId)) } label: {
                    InfoRow(title: studio, subtitle: front.map { Copy.shopSoldBy($0.sellerName, desk: p.fulfilment == .desk && !$0.sample, checkout: $0.checkout) } ?? "Studio page")
                }
                .buttonStyle(.plain)
                if let note = front?.pickupNote { Label(note, systemImage: "mappin.and.ellipse").font(.system(size: 14)).foregroundStyle(Theme.secondary) }
                Text(p.sample ? Copy.shopSampleProductNote : Copy.shopNotAffiliated).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.gutter)
        }
    }

    func dropBlock(_ d: Drop, _ studio: String) -> some View {
        let on = m.isNotified(d.id)
        let state = d.state()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                DropTag(unlocked: d.unlocked)
                if d.sample { SampleTag() }
                Spacer()
                Label(d.countdownText(), systemImage: state == .ready ? "checkmark.seal.fill" : "clock").font(.system(size: 13, weight: .bold))
            }
            Text(state == .ready ? Copy.shopReadyBody(m.shopStorefront(d.studioId)) : state == .closed ? Copy.shopDropClosed
                 : d.unlocked ? Copy.shopFinisherHint + " " + Copy.shopDropLine(d) + "." : Copy.shopDropLine(d)).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(Copy.shopPickup(studio)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(d.progressText).font(.system(size: 13, weight: .bold)).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.chipGrey)
                    Capsule().fill(Theme.lime).frame(width: max(6, g.size.width * d.progress))
                }
            }
            .frame(height: 6)
            if state == .upcoming || state == .open {
                Toggle(isOn: Binding(get: { on }, set: { v in Task { await m.setNotify(d, v) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.shopNotifyMe).font(.system(size: 15, weight: .semibold))
                        Text(state == .open ? "A push and an email when it is ready for pickup." : Copy.shopNotifyHint).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }
            if state == .open, d.sample {
                LimeButton(title: Copy.shopReserve(m.shopProduct(d.productId)?.priceText ?? "")) { m.flashSample() }
            } else if state == .open, let u = d.reserveURL() {
                LimeButton(title: Copy.shopReserve(m.shopProduct(d.productId)?.priceText ?? "")) { NSWorkspace.shared.open(u) }
                Text(Copy.shopReserveHint).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            } else if state == .open {
                Text(Copy.shopReserveAtDesk).font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.lime.opacity(0.14)))
    }

    /// Buy is on the page when the studio takes payment through Brüce (phase 4) and the listing is open to buy.
    func buyable(_ p: Product, _ drop: Drop?) -> Bool { m.canBuy(p) && (drop == nil || drop?.state() == .open) }
    func picked(_ p: Product) -> ProductVariant? { p.variants.first { $0.id == variantId && $0.inStock } ?? p.inStockVariants.first }

    func deliveryBlock(_ p: Product, _ front: Storefront, _ studio: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.shopHowTitle.uppercased()).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.secondary)
            DeliveryRow(title: Copy.shopPickupAt(studio), subtitle: Copy.shopPickupFree, symbol: "building.2", selected: delivery == .pickup || !front.ships) { delivery = .pickup }
            if front.ships {
                DeliveryRow(title: Copy.shopShipPrice(front), subtitle: Copy.shopShipNote, symbol: "shippingbox", selected: delivery == .ship) { delivery = .ship }
            }
        }
    }

    /// Buy (the checkout sheet) where the studio is connected; else a drop's Reserve is in its block, or the desk, the
    /// product's own page or the studio's webshop (in the browser).
    @ViewBuilder func actions(_ p: Product, _ front: Storefront?) -> some View {
        if p.sample {
            // Sample: the buttons are there to look at; each only says it is not for sale (a drop's Reserve is in its block).
            if m.shopDrop(for: p)?.state() != .open { LimeButton(title: p.fulfilment == .link ? Copy.shopWebshop : Copy.shopBuy(p.priceText)) { m.flashSample() } }
        } else if buyable(p, m.shopDrop(for: p)), let front {
            let draft = CheckoutDraft(product: p, storefront: front, variant: picked(p), qty: 1, delivery: front.ships ? delivery : .pickup)
            LimeButton(title: Copy.shopBuy(ShopMoney.kr(draft.totalOre))) { m.checkoutDraft = draft; m.present(.shopCheckout(p.id)) }
        } else if let d = m.shopDrop(for: p), d.state() == .open || d.state() == .ready {
            EmptyView()
        } else if let u = p.url ?? front?.webshop, p.fulfilment != .desk || p.url != nil {
            LimeButton(title: p.url != nil ? "Open in the webshop" : Copy.shopWebshop) { NSWorkspace.shared.open(u) }
        } else {
            Text(Copy.shopAskAtDesk).font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).frame(height: 54)
                .background(Capsule().fill(Theme.chipGrey))
        }
    }
}

struct DeliveryRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17)).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(selected ? Theme.ink : Theme.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Theme.lime.opacity(0.22) : Theme.chipGrey))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Checkout (phase 4)

/// What is being bought, how many, how it comes, the sums with the VAT, who sells it, and Pay, which opens Stripe
/// Checkout on the studio's account in the browser. Brüce never sees the card or an address.
struct ShopCheckoutSheet: View {
    @Environment(AppModel.self) var m
    let productId: String
    @State private var draft: CheckoutDraft?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Copy.shopCheckoutTitle, leading: .close) { m.dismissSheets() }
            if let d = draft { content(d) } else { EmptyState(system: "bag", text: "This listing is no longer there.") }
        }
        .onAppear { if draft == nil, let p = m.shopProduct(productId) { draft = m.checkoutDraft?.product.id == p.id ? m.checkoutDraft : m.checkoutDraft(for: p) } }
    }

    func content(_ d: CheckoutDraft) -> some View {
        let studio = m.studioName(d.product.studioId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ProductArt(kind: d.product.kind, corner: 12, symbolSize: 24).frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.product.title).font(.system(size: 16, weight: .bold))
                        Text([d.variant?.label, studio].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Text(ShopMoney.exact(d.product.priceOre)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                }
                HStack {
                    Text("Quantity").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Stepper(value: Binding(get: { draft?.qty ?? 1 }, set: { draft?.qty = $0 }), in: 1...CheckoutDraft.maxQty) { Text("\(d.qty)").font(.system(size: 16, weight: .bold)).monospacedDigit() }
                        .fixedSize()
                }
                Text(Copy.shopHowTitle.uppercased()).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.secondary)
                DeliveryRow(title: Copy.shopPickupAt(studio), subtitle: d.storefront.pickupNote ?? Copy.shopPickupFree, symbol: "building.2", selected: d.delivery == .pickup) { draft?.delivery = .pickup }
                if d.storefront.ships {
                    DeliveryRow(title: Copy.shopShipPrice(d.storefront), subtitle: Copy.shopShipNote, symbol: "shippingbox", selected: d.delivery == .ship) { draft?.delivery = .ship }
                }
                VStack(spacing: 8) {
                    sum(d.itemLine, ShopMoney.exact(d.subtotalOre))
                    if d.delivery == .ship { sum("Shipping", ShopMoney.exact(d.shippingOre)) }
                    Divider()
                    HStack {
                        Text("Total").font(.system(size: 16, weight: .bold))
                        Spacer()
                        Text(ShopMoney.exact(d.totalOre)).font(.system(size: 19, weight: .heavy)).monospacedDigit()
                    }
                    sum(Copy.shopVatLine(d.product.vatRate), ShopMoney.exact(d.vatOre), muted: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.chipGrey))
                Text(Copy.shopSeller(d.storefront, vicinity: m.studio(d.product.studioId)?.vicinity)).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if let problem = d.problem { Text(problem).font(.system(size: 13)).foregroundStyle(.red) }
                LimeButton(title: Copy.shopPay(ShopMoney.exact(d.totalOre))) { pay(d) }.disabled(busy || d.problem != nil).opacity(d.problem != nil ? 0.6 : 1)
                Text(Copy.shopPayMethods).font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
                Label(Copy.shopPaySafety, systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.gutter)
        }
    }

    func sum(_ label: String, _ value: String, muted: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(muted ? Theme.secondary : Theme.ink)
            Spacer()
            Text(value).font(.system(size: 13, weight: muted ? .regular : .semibold)).foregroundStyle(muted ? Theme.secondary : Theme.ink).monospacedDigit()
        }
    }

    func pay(_ d: CheckoutDraft) {
        busy = true
        Task {
            if let u = await m.startCheckout(d) { NSWorkspace.shared.open(u); m.dismissSheets() }
            busy = false
        }
    }
}

// MARK: - Orders

/// Menu › Orders: what the member bought from studio shops, the status and the pickup code.
struct OrdersView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Copy.shopOrdersTitle, leading: m.sheets.count > 1 ? .back : .close) { m.popSheet() }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if m.orders.isEmpty {
                        EmptyState(system: "bag", text: m.ordersLoaded || AppModel.demo ? Copy.shopOrdersEmpty : "Loading…").padding(.top, 30)
                    }
                    ForEach(m.orders) { o in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: o.symbol).font(.system(size: 18)).foregroundStyle(Theme.secondary).frame(width: 26)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(o.items.map(\.line).joined(separator: ", ")).font(.system(size: 15, weight: .semibold))
                                    Text([o.sellerName ?? m.studioName(o.studioId), Copy.shopOrderDate(o)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Text(ShopMoney.kr(o.totalOre)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                            }
                            Text(o.statusLine).font(.system(size: 12, weight: .bold)).foregroundStyle(o.isReady ? .black : Theme.ink)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(o.isReady ? Theme.lime : Theme.chipGrey))
                            if let code = o.pickupCode, !o.isDone {
                                Text(Copy.shopPickupCode.uppercased()).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.secondary)
                                Text(code).font(.system(size: 28, weight: .heavy, design: .monospaced)).kerning(4)
                                if let note = o.pickupNote { Text(note).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.chipGrey.opacity(0.6)))
                    }
                    Text(Copy.shopOrdersNote).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.gutter)
            }
        }
        .task { await m.loadOrders() }
    }
}

// MARK: - Studio page

/// "Shop at the desk" on a studio page: the listings as a rail, who sells them and how to pay.
struct ShopRail: View {
    @Environment(AppModel.self) var m
    let studioId: Int
    var body: some View {
        let products = m.shopProducts(for: studioId)
        if let front = m.shopStorefront(studioId), !products.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(Copy.shopAtDesk).font(.system(size: 17, weight: .bold))
                    Spacer()
                    Text("\(products.count) item\(products.count == 1 ? "" : "s")").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { ForEach(products) { p in ProductTile(product: p, compact: true).frame(width: 120) } }
                }
                HStack {
                    Text(Copy.shopSoldBy(front.sellerName, desk: products.contains { $0.fulfilment == .desk } && !front.sample, checkout: front.checkout)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 8)
                    if front.sample { Button(Copy.shopWebshop) { m.flashSample() }.font(.system(size: 13, weight: .semibold)) }
                    else if let u = front.webshop { Button(Copy.shopWebshop) { NSWorkspace.shared.open(u) }.font(.system(size: 13, weight: .semibold)) }
                    else { Text(Copy.shopAskAtDesk).font(.system(size: 13, weight: .bold)) }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sectionGrey))
            .padding(.horizontal, Theme.gutter).padding(.top, 12)
        }
    }
}

// MARK: - After a check-in

/// "Forgot your towel?" on the ticket after a check-in at a sauna or spa whose storefront lists a towel.
struct TowelCard: View {
    @Environment(AppModel.self) var m
    let towel: Product
    var body: some View {
        Button { m.dismissSheets(); m.push(.product(towel.id)) } label: {
            HStack(spacing: 12) {
                ProductArt(kind: .towel, corner: 10, symbolSize: 20).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.shopTowelTitle).font(.system(size: 15, weight: .bold))
                    Text(Copy.shopTowelBody(towel)).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            .padding(12).contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sectionGrey))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.gutter)
    }
}
