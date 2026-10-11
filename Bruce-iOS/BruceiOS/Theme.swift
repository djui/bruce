import SwiftUI

/// Visual tokens (colour values copied from Bruce-MacOS/Theme.swift), made adaptive for light and dark mode.
enum Theme {
    static let lime = Color(red: 0xCC / 255, green: 0xF0 / 255, blue: 0x3A / 255)
    static let neonLime = Color(red: 0xDA / 255, green: 0xFC / 255, blue: 0x55 / 255)
    /// Lime that stays readable as text/icon on light backgrounds.
    static let limeInk = Color(light: Color(red: 0.36, green: 0.46, blue: 0.0), dark: lime)

    static let ink = Color(.label)
    static let secondary = Color(.secondaryLabel)
    static let tertiary = Color(.tertiaryLabel)
    static let background = Color(.systemBackground)
    static let sectionGrey = Color(.secondarySystemBackground)
    static let chipGrey = Color(.tertiarySystemFill)
    static let divider = Color(.separator)
    static let cardBorder = Color(.separator)

    // Opening-hours colours (teal = open, orange = closing soon, red = closed).
    static let teal = Color(red: 0.16, green: 0.69, blue: 0.60)
    static let hoursOrange = Color(red: 0.95, green: 0.6, blue: 0.1)
    static let hoursRed = Color(red: 0.93, green: 0.22, blue: 0.24)

    static let red = Color(red: 1, green: 0.22, blue: 0.24)
    static let strikeRed = Color(red: 0xE0 / 255, green: 0x10 / 255, blue: 0x10 / 255)
    static let waitlistOrange = Color(red: 0xF5 / 255, green: 0x8A / 255, blue: 0x1F / 255)
    static let baseTag = Color(red: 0xCF / 255, green: 0xC8 / 255, blue: 0xC2 / 255)
    static let creditsBeige = Color(light: Color(red: 0xF9 / 255, green: 0xEC / 255, blue: 0xD9 / 255),
                                     dark: Color(red: 0.32, green: 0.27, blue: 0.2))
    static let darkBG = Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x26 / 255)
    static let darkCard = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)
    static let olive = Color(red: 0x84 / 255, green: 0x99 / 255, blue: 0x3E / 255)
    static let oliveRange = Color(red: 0x6E / 255, green: 0x7E / 255, blue: 0x38 / 255)
    static let tealPrice = Color(red: 0x1F / 255, green: 0xB5 / 255, blue: 0x8F / 255)

    static let gutter: CGFloat = 16

    /// Heavy, wide uppercase heading ("HOME", "EXPLORE", ...), the Bruce identity.
    static func screenTitle(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .black).width(.expanded) }
    static func heading(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .heavy).width(.expanded) }
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

// MARK: - Toolbar title

extension View {
    /// Big wide uppercase title pinned in the (glass) navigation bar.
    func bruceTitle(_ title: String) -> some View {
        self.navigationTitle(title.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(title.uppercased()).font(Theme.screenTitle(26)).lineLimit(1).minimumScaleFactor(0.6)
                        .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            }
    }
}

// MARK: - Buttons

/// Full-width lime Liquid Glass button (glassProminent tinted lime, black label).
struct LimeButton: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label { Text(title).font(.system(size: 17, weight: .bold)) } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity).frame(height: 40)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.lime)
        .controlSize(.large)
    }
}

struct RedButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 40)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.red)
        .controlSize(.large)
    }
}

/// Selectable glass chip; selected chips get a lime-tinted glass.
struct GlassChip<Label: View>: View {
    let selected: Bool
    var action: () -> Void
    @ViewBuilder var label: Label
    var body: some View {
        Button(action: action) {
            label.font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Theme.ink)
                .padding(.horizontal, 14).frame(height: 36)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(Theme.lime).interactive() : .regular.interactive(), in: .capsule)
    }
}

extension GlassChip where Label == Text {
    init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.init(selected: selected, action: action) { Text(title) }
    }
}

/// "0 / 3" glass pill.
struct CountPill: View {
    let used: Int
    let total: Int
    var body: some View {
        Text("\(used) / \(total)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
            .padding(.horizontal, 12).frame(height: 32)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Studio visit pill: "n / m", or ∞ when unlimited for the user's tier.
struct StudioLimitPill: View {
    @Environment(AppModel.self) var m
    let studioId: Int
    var body: some View {
        switch m.studioLimitState(studioId) {
        case .limited(let l): Text("\(m.studioVisitsThisMonth(studioId)) / \(l)").monospacedDigit().padding(.horizontal, 4)
        case .notIncluded: Text("0 / 0").padding(.horizontal, 4)
        case .unlimited: Image(systemName: "infinity")
        case .unknown: EmptyView()
        }
    }
}

// MARK: - Content building blocks

struct SectionHeaderBar: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .background(.bar)
    }
}

struct EmptyState: View {
    let system: String
    let text: String
    var body: some View {
        ContentUnavailableView { Image(systemName: system).font(.system(size: 56, weight: .light)) } description: {
            Text(text).font(.system(size: 16))
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

/// Row with title, grey subtitle(s) and optional chevron.
struct InfoRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    var footnote: String?
    var chevron = true
    @ViewBuilder var accessory: Accessory
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.ink)
                if let subtitle { Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.secondary) }
                if let footnote { Text(footnote).font(.system(size: 13)).foregroundStyle(Theme.tertiary) }
            }
            Spacer()
            accessory
            if chevron { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.tertiary) }
        }
        .contentShape(Rectangle())
    }
}

extension InfoRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, footnote: String? = nil, chevron: Bool = true) {
        self.init(title: title, subtitle: subtitle, footnote: footnote, chevron: chevron) { EmptyView() }
    }
}

/// Remote Cloudinary photo; offline (demo) a deterministic gradient so cards still look like photos.
struct RemotePhoto: View, Equatable {
    let fileId: String?
    var w = 402, h = 252
    var symbol: String? = nil
    var body: some View {
        // Fills whatever frame the parent gives it; no GeometryReader (cheaper layout in long lists).
        Rectangle().fill(.clear)
            .overlay {
                if let url = BruceAPI.imageURL(fileId, w: w, h: h) {
                    StoredImage(url: url) { placeholder }
                } else { placeholder }
            }
            .clipped()
    }

    static let palettes: [[Color]] = [
        [Color(red: 0.20, green: 0.24, blue: 0.16), Color(red: 0.55, green: 0.66, blue: 0.16)],
        [Color(red: 0.10, green: 0.25, blue: 0.27), Color(red: 0.16, green: 0.62, blue: 0.56)],
        [Color(red: 0.25, green: 0.16, blue: 0.12), Color(red: 0.78, green: 0.46, blue: 0.20)],
        [Color(red: 0.14, green: 0.14, blue: 0.22), Color(red: 0.42, green: 0.40, blue: 0.70)],
        [Color(red: 0.12, green: 0.12, blue: 0.12), Color(red: 0.38, green: 0.38, blue: 0.40)],
    ]
    var placeholder: some View {
        let key = (fileId ?? "").unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let p = Self.palettes[key % Self.palettes.count]
        return ZStack {
            LinearGradient(colors: p, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.18), .clear], center: .topTrailing, startRadius: 10, endRadius: 260)
            Image(systemName: symbol ?? "figure.strengthtraining.traditional")
                .font(.system(size: 120, weight: .ultraLight)).foregroundStyle(.white.opacity(0.10))
                .offset(x: 90, y: 20)
        }
    }
}

struct Avatar: View {
    let fileId: String?
    var initials: String = ""
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Theme.lime.opacity(0.85), Theme.teal.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(.black.opacity(0.75))
            if let url = BruceAPI.imageURL(fileId, w: 132, h: 132) {
                StoredImage(url: url) { Color.clear }
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

/// Class row used in Explore/Classes, Friends, My classes and Visits lists.
struct ClassRow: View {
    @Environment(AppModel.self) var m
    let c: BruceAPI.BruceClass
    var meta: String? = nil
    var badge: String? = nil
    var showMenu = true
    var trailing: AnyView? = nil

    var body: some View {
        let st = m.studio(c.studioId)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(BruceDate.time(c.start)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                Text(c.durationMinutes.map { "\($0) min" } ?? "").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            .frame(width: 58, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                Text(st?.name ?? c.studio?.name ?? "").font(.system(size: 15)).lineLimit(1)
                let line = meta ?? [st?.vicinity ?? c.studio?.vicinity, c.instructor].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " | ")
                if !line.isEmpty { Text(line).font(.system(size: 15)).foregroundStyle(Theme.secondary).lineLimit(1) }
                if let badge {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.waitlistOrange).frame(width: 7, height: 7)
                        Text(badge).font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.waitlistOrange.opacity(0.18), in: Capsule())
                    .padding(.top, 4)
                } else if let a = c.availableSpots, a <= 0 {
                    Text("Fully booked").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.red).padding(.top, 2)
                }
            }
            .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            if let trailing { trailing }
            if showMenu { ClassMenu(classId: c.id) }
        }
        .padding(.vertical, 14).padding(.horizontal, Theme.gutter)
        .contentShape(Rectangle())
    }
}

/// The ⋮ class actions as a native (glass) menu.
struct ClassMenu: View {
    @Environment(AppModel.self) var m
    @Environment(\.pushRoute) var pushRoute
    let classId: Int
    var body: some View {
        let c = m.findClass(classId)
        Menu {
            Button(m.isBookmarked(classId) ? "Remove bookmark" : "Add bookmark",
                   systemImage: m.isBookmarked(classId) ? "bookmark.slash" : "bookmark") { m.toggleBookmark(classId) }
            Button("Invite friends", systemImage: "person.2") { m.present(.invite) }
            ShareLink(item: ShareURL.forClass(classId, title: c?.title ?? "")) { Label("Share", systemImage: "square.and.arrow.up") }
            if let sid = c?.studioId {
                Button("Show studio", systemImage: "building.2") { (pushRoute ?? m.push)(.studio(sid)) }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.secondary)
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }
    }
}

/// Liquid-glass toast.
struct ToastView: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 24)
    }
}

/// Stand-in for MapKit in offline demo mode (no tile requests).
struct OfflineMap: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemGray5), Color(.systemGray4)], startPoint: .top, endPoint: .bottom)
            Path { p in
                for i in stride(from: 0, through: 1200, by: 60) {
                    p.move(to: CGPoint(x: CGFloat(i), y: 0)); p.addLine(to: CGPoint(x: CGFloat(i) - 400, y: 900))
                    p.move(to: CGPoint(x: 0, y: CGFloat(i))); p.addLine(to: CGPoint(x: 900, y: CGFloat(i) - 300))
                }
            }
            .stroke(Color(.systemBackground).opacity(0.6), lineWidth: 2)
            Label("Map offline in demo mode", systemImage: "map").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary).padding(.horizontal, 12).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        }
        .clipped()
    }
}

func durationText(_ c: BruceAPI.BruceClass) -> String { c.durationMinutes.map { "\($0) min" } ?? "" }

/// Groups classes by Stockholm day, sorted.
func groupedByDay<T>(_ items: [T], date: (T) -> Date?) -> [(Date, [T])] {
    let g = Dictionary(grouping: items) { BruceDate.calendar.startOfDay(for: date($0) ?? .distantPast) }
    return g.keys.sorted().map { ($0, g[$0]!) }
}


/// Original-style tabs: text with an underline indicator and count badges (no floating glass capsule).
struct UnderlineTabs: View {
    let titles: [String]
    var badges: [String?] = []
    @Binding var selection: Int
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 26) {
            ForEach(titles.indices, id: \.self) { i in
                let sel = selection == i
                Button { withAnimation(.snappy(duration: 0.25)) { selection = i } } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Text(titles[i]).font(.system(size: 16, weight: sel ? .bold : .medium))
                                .foregroundStyle(sel ? Theme.ink : Theme.secondary)
                            if i < badges.count, let b = badges[i] {
                                Text(b).font(.system(size: 12, weight: .bold)).monospacedDigit()
                                    .foregroundStyle(sel ? Color.black : Theme.secondary)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(sel ? Theme.lime : Theme.chipGrey))
                            }
                        }
                        ZStack {
                            Color.clear.frame(height: 3)
                            if sel { Capsule().fill(Theme.ink).frame(height: 3).matchedGeometryEffect(id: "underline", in: ns) }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
    }
}
