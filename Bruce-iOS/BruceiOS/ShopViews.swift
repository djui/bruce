import SwiftUI

// Studio shop on the iPhone (Shop.swift): Home's Shop section with the drop card, Home › Shop with its chips, a
// product page, the "Shop at the desk" rail on a studio page and the "Forgot your towel?" card on the ticket after a
// check-in at a sauna. Everything shows only while the city's catalogue has something in it (`m.showsShop`). The
// studio sells: the buttons say "Ask at the desk" or open its webshop, and Notify me only reminds.

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

/// A product in the Shop grid and the studio rail: picture, title, "449 kr · Ångan".
struct ProductTile: View {
    @Environment(AppModel.self) var m
    let product: Product
    var compact = false
    var body: some View {
        NavigationLink(value: Route.product(product.id)) {
            VStack(alignment: .leading, spacing: 4) {
                ProductArt(kind: product.kind, corner: 16, symbolSize: compact ? 30 : 36).aspectRatio(compact ? 4 / 3 : 2 / 1, contentMode: .fit)
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
        .accessibilityLabel("\(product.title), \(product.priceText), \(m.studioName(product.studioId))")
    }
    /// "Yogaloft", "Kärnan", "Ångan": the studio's first word, as the mockup lists them.
    var shortStudio: String { String(m.studioName(product.studioId).split(separator: " ").first ?? "") }
}

/// A drop (mockup 1): "DROP" tag, the title, where to pick it up, the countdown, "31 of 40" and a meter, with Notify me.
struct DropCard: View {
    @Environment(AppModel.self) var m
    let drop: Drop
    var body: some View {
        let product = m.shopProduct(drop.productId)
        let on = m.isNotified(drop.id)
        NavigationLink(value: Route.product(drop.productId)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(Copy.shopDropTag.uppercased()).bruceFont(10, weight: .heavy, width: .expanded).foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.lime, in: .capsule)
                    Spacer()
                    Image(systemName: product?.kind.symbol ?? "tshirt").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.white.opacity(0.35))
                }
                Text(drop.title).bruceFont(19, weight: .heavy, width: .expanded).lineLimit(2).minimumScaleFactor(0.8)
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
                    Button { Task { await m.setNotify(drop, !on) } } label: {
                        Label(on ? "Notifying" : Copy.shopNotifyMe, systemImage: on ? "bell.fill" : "bell").bruceFont(14, weight: .bold)
                            .foregroundStyle(on ? .white : .black)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(on ? Color.white.opacity(0.22) : Theme.lime, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "Notify me is on" : Copy.shopNotifyMe)
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
        .accessibilityLabel("Drop: \(drop.title), \(drop.countdownText()), \(drop.progressText) reserved, \(Copy.shopPickup(m.studioName(drop.studioId)))")
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
                Text(Copy.shopCatalogFooter).bruceFont(13).foregroundStyle(Theme.secondary).padding(.top, 8)
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
                Text(p.title.uppercased()).bruceScreenTitle(26).lineLimit(3).minimumScaleFactor(0.7)
                Text([studio, p.description].compactMap { $0 }.joined(separator: " · ")).bruceFont(14).foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(p.priceText).bruceFont(24, weight: .heavy).monospacedDigit()
                    Text(Copy.shopInclVAT).bruceFont(13).foregroundStyle(Theme.secondary)
                    Spacer()
                }
                if !p.variants.isEmpty { variants(p) }
                if let drop { dropBlock(drop, p, studio) }
                NavigationLink(value: Route.studio(p.studioId)) {
                    InfoRow(title: studio, subtitle: front.map { Copy.shopSoldBy($0.sellerName, desk: p.fulfilment == .desk) } ?? "Studio page").padding(14)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                if let note = front?.pickupNote {
                    Label(note, systemImage: "mappin.and.ellipse").bruceFont(14).foregroundStyle(Theme.secondary)
                }
                Text(Copy.shopNotAffiliated).bruceFont(13).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.gutter).padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom) { actions(p, front, drop).padding(Theme.gutter) }
    }

    func variants(_ p: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(p.kind == .apparel ? "SIZES" : "OPTIONS").bruceFont(11, weight: .heavy, width: .expanded).foregroundStyle(Theme.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        ForEach(p.variants) { v in
                            Text(v.label + (v.inStock ? "" : " · out")).bruceFont(14, weight: .semibold).foregroundStyle(v.inStock ? Theme.ink : Theme.tertiary)
                                .padding(.horizontal, 14).frame(height: 34).glassEffect(.regular, in: .capsule)
                        }
                    }
                }
            }
        }
    }

    /// The drop's window: "Pre-order until Sun 7 Feb · one print run", the countdown, "31 of 40" and Notify me.
    func dropBlock(_ d: Drop, _ p: Product, _ studio: String) -> some View {
        let on = m.isNotified(d.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Copy.shopDropTag.uppercased()).bruceFont(10, weight: .heavy, width: .expanded).foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.lime, in: .capsule)
                Spacer()
                Label(d.countdownText(), systemImage: "clock").bruceFont(13, weight: .bold)
            }
            Text(Copy.shopDropLine(d)).bruceFont(14).fixedSize(horizontal: false, vertical: true)
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
            Toggle(isOn: Binding(get: { on }, set: { v in Task { await m.setNotify(d, v) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.shopNotifyMe).bruceFont(16, weight: .semibold)
                    Text(Copy.shopNotifyHint).bruceFont(13).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.limeInk)
        }
        .padding(16)
        .glassEffect(.regular.tint(Theme.lime.opacity(0.12)), in: .rect(cornerRadius: 22))
    }

    /// Phase 2: no checkout. The desk, the product's own page or the studio's webshop.
    @ViewBuilder func actions(_ p: Product, _ front: Storefront?, _ drop: Drop?) -> some View {
        if let u = p.url ?? front?.webshop, p.fulfilment != .desk || p.url != nil {
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
                    Text(Copy.shopSoldBy(front.sellerName, desk: products.contains { $0.fulfilment == .desk })).bruceFont(13).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 8)
                    if let u = front.webshop {
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
