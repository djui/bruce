import SwiftUI

/// Visual tokens matching the Bruce Studios iOS app.
enum Theme {
    static let lime = Color(red: 0xCC / 255, green: 0xF0 / 255, blue: 0x3A / 255)
    static let ink = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    static let secondary = Color(white: 0.45)
    static let tertiary = Color(white: 0.6)
    static let sectionGrey = Color(red: 0xF3 / 255, green: 0xF4 / 255, blue: 0xF6 / 255)
    static let chipGrey = Color(red: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF2 / 255)
    static let searchGrey = Color(red: 0xEE / 255, green: 0xEE / 255, blue: 0xF0 / 255)
    static let divider = Color(white: 0.88)
    static let cardBorder = Color(white: 0.85)
    static let baseTag = Color(red: 0xCF / 255, green: 0xC8 / 255, blue: 0xC2 / 255)
    static let creditsBeige = Color(red: 0xF9 / 255, green: 0xEC / 255, blue: 0xD9 / 255)
    static let strikeRed = Color(red: 0xE0 / 255, green: 0x10 / 255, blue: 0x10 / 255)
    static let waitlistOrange = Color(red: 0xF5 / 255, green: 0x8A / 255, blue: 0x1F / 255)
    /// Parakey's teal (their app icon and buttons).
    static let parakey = Color(red: 0x00 / 255, green: 0x8C / 255, blue: 0xB0 / 255)
    static let darkPanel = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)

    static let windowSize = CGSize(width: 390, height: 780)
    static let gutter: CGFloat = 16

    /// Heavy, wide uppercase screen title ("HOME", "EXPLORE", ...).
    static func screenTitle(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .black).width(.expanded)
    }
}

extension View {
    func lightCanvas() -> some View {
        self.background(Color.white).foregroundStyle(Theme.ink).environment(\.colorScheme, .light)
    }
}

// MARK: - Shared components

/// "HOME"-style header of a main tab: the tab's own buttons, then Notifications and Menu, which end every
/// main tab's header so they never move between tabs.
struct ScreenHeader<Trailing: View>: View {
    @Environment(AppModel.self) var m
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title.uppercased()).font(Theme.screenTitle()).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            trailing
            IconButton(system: "bell", size: 22, badge: m.unreadNotifications) { m.present(.notifications) }.help("Notifications")
            IconButton(system: "line.3.horizontal", size: 22) { m.present(.menu) }.help("Menu")
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// Sheet / pushed-page nav bar: leading X or chevron, centered bold title, optional trailing.
struct NavBar<Trailing: View>: View {
    enum Leading { case close, back, none }
    let title: String
    var leading: Leading = .back
    var action: () -> Void = {}
    @ViewBuilder var trailing: Trailing
    var body: some View {
        ZStack {
            Text(title).font(.system(size: 17, weight: .bold))
            HStack {
                switch leading {
                case .close: IconButton(system: "xmark", size: 20, action: action)
                case .back: IconButton(system: "chevron.left", size: 20, action: action)
                case .none: EmptyView()
                }
                Spacer()
                trailing
            }
        }
        .frame(height: 52)
        .padding(.horizontal, Theme.gutter)
    }
}

extension NavBar where Trailing == EmptyView {
    init(title: String, leading: Leading = .back, action: @escaping () -> Void = {}) {
        self.init(title: title, leading: leading, action: action) { EmptyView() }
    }
}

struct IconButton: View {
    let system: String
    var size: CGFloat = 22
    var weight: Font.Weight = .light
    var badge = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: weight))
                .frame(width: 34, height: 34)
                .overlay(alignment: .topTrailing) {
                    if badge { Circle().fill(Color.red).frame(width: 9, height: 9).offset(x: -2, y: 3) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LimeButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(Capsule().fill(Theme.lime))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// "0 / 3" outlined pill.
struct CountPill: View {
    let used: Int
    let total: Int
    var body: some View {
        Text("\(used) / \(total)").font(.system(size: 17, weight: .light))
            .padding(.horizontal, 10).frame(height: 30)
            .overlay(Capsule().stroke(Theme.ink, lineWidth: 1))
    }
}

/// Top-bar studio visit pill: "n / m", or ∞ when the studio's limit for the tier is 0 (unlimited).
/// Tapping it opens the visit-limit sheet, as in the original.
struct StudioLimitPill: View {
    @Environment(AppModel.self) var m
    let studioId: Int
    var body: some View {
        Button { m.present(.visitLimit(studioId)) } label: { label.contentShape(Capsule()) }
            .buttonStyle(.plain)
            .help("Visit limit at this studio")
    }
    @ViewBuilder var label: some View {
        switch m.studioLimitState(studioId) {
        case .limited(let l): CountPill(used: m.studioVisitsThisMonth(studioId), total: l)
        case .notIncluded: CountPill(used: 0, total: 0)
        case .unlimited:
            Image(systemName: "infinity").font(.system(size: 17, weight: .medium))
                .frame(width: 50, height: 30).overlay(Capsule().stroke(Theme.ink, lineWidth: 1))
        case .unknown: EmptyView()
        }
    }
}

/// Underlined text tabs ("Bookings  Waitlist  Bookmarks").
struct UnderlineTabs: View {
    let titles: [String]
    var badges: [String?] = []
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 32) {
            ForEach(titles.indices, id: \.self) { i in
                Button { selection = i } label: {
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Text(titles[i]).font(.system(size: 16, weight: .medium))
                                .foregroundStyle(selection == i ? Theme.ink : Theme.tertiary)
                            if i < badges.count, let b = badges[i] {
                                Text(b).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(selection == i ? Theme.ink : Theme.tertiary)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Capsule().fill(Theme.chipGrey))
                            }
                        }
                        Rectangle().fill(selection == i ? Theme.ink : .clear).frame(height: 2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
    }
}

struct SectionHeaderBar: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 16, weight: .light))
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .background(Theme.sectionGrey)
    }
}

struct EmptyState: View {
    let system: String
    let text: String
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: system).font(.system(size: 76, weight: .regular))
            Text(text).font(.system(size: 16, weight: .light)).multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Row with title, grey subtitle(s) and optional chevron (Account, Membership, ...).
struct InfoRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    var footnote: String?
    var chevron = true
    @ViewBuilder var accessory: Accessory
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 17, weight: .medium))
                    if let subtitle { Text(subtitle).font(.system(size: 15, weight: .light)).foregroundStyle(Theme.tertiary) }
                    if let footnote { Text(footnote).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.tertiary) }
                }
                Spacer()
                accessory
                if chevron { Image(systemName: "chevron.right").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.tertiary) }
            }
            .padding(.vertical, 16)
            .padding(.trailing, Theme.gutter)
            Rectangle().fill(Theme.divider).frame(height: 0.5)
        }
        .padding(.leading, Theme.gutter)
        .contentShape(Rectangle())
    }
}

extension InfoRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, footnote: String? = nil, chevron: Bool = true) {
        self.init(title: title, subtitle: subtitle, footnote: footnote, chevron: chevron) { EmptyView() }
    }
}

/// Remote Cloudinary photo with dark overlay fallback.
struct RemotePhoto: View {
    let fileId: String?
    var w = 402, h = 252
    var body: some View {
        GeometryReader { geo in
            if let url = BruceAPI.imageURL(fileId, w: w, h: h) {
                StoredImage(url: url) { placeholder }
                .frame(width: geo.size.width, height: geo.size.height).clipped()
            } else { placeholder }
        }
    }
    var placeholder: some View {
        LinearGradient(colors: [Color(white: 0.35), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
    }
}

struct Avatar: View {
    let fileId: String?
    var initials: String = ""
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle().fill(Theme.chipGrey)
            if let url = BruceAPI.imageURL(fileId, w: 132, h: 132) {
                StoredImage(url: url) { Text(initials).font(.system(size: size * 0.35, weight: .semibold)) }
            } else {
                Text(initials).font(.system(size: size * 0.35, weight: .semibold))
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

/// Class row used in Explore/Classes, Friends and Visits lists.
/// `badge` shows an orange "Waitlist" line (teal "Booked" once the spot turned into a booking); otherwise `full` shows red
/// "Fully booked". `wellness` adds a boxed tag under the duration. With `classId`, friends booked on the
/// class show as small faces under the row.
struct ClassRow: View {
    @Environment(AppModel.self) var m
    let time: String
    let duration: String
    let title: String
    let studio: String
    let meta: String
    var showMenu = true
    var badge: String?
    var full = false
    var wellness = false
    /// When set, the ⋮ button opens the class action sheet.
    var classId: Int? = nil
    /// "Free cancel until 18:30" on booked rows (BookingRules.cancelChip).
    var cancelChip: BookingRules.CancelChip? = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(time).font(.system(size: 17, weight: .semibold))
                    Text(duration).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary)
                    if wellness {
                        Text("Wellness").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.cardBorder))
                            .padding(.top, 2)
                    }
                }
                .frame(width: 62, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    Text(studio).font(.system(size: 16, weight: .light)).lineLimit(1)
                    if !meta.isEmpty { Text(meta).font(.system(size: 16, weight: .light)).foregroundStyle(Theme.secondary).lineLimit(1) }
                    if let badge {
                        HStack(spacing: 6) {
                            // "Booked" = a waitlist spot that turned into a booking, "Spot open" = a free spot to book (teal); "Waitlist" orange.
                            let tint = badge == "Waitlist" ? Theme.waitlistOrange : Theme.teal
                            Image(systemName: badge == "Booked" ? "checkmark.circle.fill" : badge == Copy.spotOpen ? "person.crop.circle.badge.plus" : "bell.fill").font(.system(size: 11)).foregroundStyle(tint)
                            Text(badge).font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
                        }
                        .padding(.top, 6)
                    } else if full {
                        Text("Fully booked").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.strikeRed).padding(.top, 4)
                    }
                    if let chip = cancelChip {
                        let tint: Color = switch chip.tone { case .free: Color(red: 0.05, green: 0.5, blue: 0.2); case .warn: Theme.waitlistOrange; case .bad: Theme.strikeRed }
                        HStack(spacing: 6) {
                            Image(systemName: chip.tone == .free ? "clock" : "exclamationmark.triangle.fill").font(.system(size: 11))
                            Text(chip.text).font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(tint).padding(.top, 4)
                    }
                    if let classId, case let friends = m.friendsBooked(classId), !friends.isEmpty {
                        FriendFaces(users: friends).padding(.top, 6)
                    }
                }
                Spacer(minLength: 0)
                if showMenu {
                    Button { if let classId { m.classActions = classId } } label: {
                        Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.secondary).frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.top, -2)
                }
            }
            .padding(.vertical, 18).padding(.trailing, Theme.gutter)
            Rectangle().fill(Theme.divider).frame(height: 0.5)
        }
        .padding(.leading, Theme.gutter - 4)
        .contentShape(Rectangle())
    }
}

/// Overlapping faces of friends booked on a class (class rows), with a "+n" after five.
struct FriendFaces: View {
    let users: [BruceAPI.UserLite]
    var size: CGFloat = 28
    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(users.prefix(5), id: \.id) { u in
                Avatar(fileId: u.photo, initials: u.initials, size: size)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
            if users.count > 5 {
                Text("+\(users.count - 5)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                    .padding(.leading, size * 0.3 + 4)
            }
        }
        .help("Booked by " + users.compactMap(\.firstName).formatted(.list(type: .and)))
    }
}

/// "Filter active" note at the end of a filtered Explore list; clicking it opens the filter panel.
struct FilterActiveFooter: View {
    @Environment(AppModel.self) var m
    var body: some View {
        Button { m.filterOpen = true } label: {
            Text("Filter active").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 16).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


/// Stand-in for MapKit views in offline demo mode (no tile requests).
struct OfflineMap: View {
    var body: some View {
        ZStack {
            Color(red: 0.93, green: 0.93, blue: 0.92)
            Image(systemName: "map").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Color(white: 0.6))
        }
    }
}

struct OnlineOnly<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { if AppModel.remoteAssets { content() } else { OfflineMap() } }
}
