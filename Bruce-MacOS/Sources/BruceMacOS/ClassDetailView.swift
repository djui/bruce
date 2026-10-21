import SwiftUI
import MapKit


struct RuleRow: View {
    let icon: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 17, weight: .light)).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(text).font(.system(size: 16, weight: .light)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// macOS share sheet anchored on the button (NSSharingServicePicker via ShareLink).
struct ShareButton: View {
    let url: URL
    var body: some View {
        ShareLink(item: url) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 20, weight: .light)).frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }
}

struct ClassDetailView: View {
    @Environment(AppModel.self) var m
    let classId: Int

    var c: BruceAPI.BruceClass? {
        m.classDetails[classId] ?? m.classesByDay.values.joined().first { $0.id == classId }
    }
    var studio: BruceAPI.Studio? { c.flatMap { m.studio($0.studioId) } }
    var booking: BruceAPI.Booking? { m.booking(forClass: classId) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                IconButton(system: "chevron.left", size: 20) { m.pop() }
                Spacer()
                // Class pages show the pill only for studios with a visit limit (no ∞ here, cf. screenshot 68).
                if let c, case .limited = m.studioLimitState(c.studioId) { StudioLimitPill(studioId: c.studioId) }
                ShareButton(url: ShareURL.forClass(classId, title: c?.title ?? ""))
                if booking == nil {
                    IconButton(system: m.isBookmarked(classId) ? "bookmark.fill" : "bookmark", size: 20) {
                        m.toggleBookmark(classId)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).frame(height: 56)
            if let c { content(c) } else {
                Spacer(); ProgressView(); Spacer()
            }
        }
        .task {
            await m.loadClassDetail(classId)
            if let sid = m.findClass(classId)?.studioId { await m.loadStudioLimits(sid) }
            await m.loadClassAttendees(classId)
        }
    }

    func content(_ c: BruceAPI.BruceClass) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Studio notice banner above the hero, as in the original class page.
                if let a = BruceAPI.currentAlert(c.studio?.alerts ?? studio?.alerts), let msg = a.message {
                    Text(msg).font(.system(size: 15, weight: .light)).foregroundStyle(a.isCritical ? .white : .primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(a.isCritical ? Color(red: 0.91, green: 0.30, blue: 0.29) : Theme.sectionGrey))
                        .padding(.horizontal, Theme.gutter).padding(.bottom, 16)
                }
                hero(c)
                VStack(alignment: .leading, spacing: 0) {
                    if let b = booking, b.isCheckedIn {
                        // Checked in: keep the class with its ticket, then offer the rating (as the original).
                        Group {
                            if let r = m.reviewableBooking(forClass: c.id) {
                                LimeButton(title: Copy.reviewTitle) { m.present(.review(r.id)) }
                            } else {
                                LimeButton(title: "Show ticket") { m.present(.ticket(b.id)) }
                            }
                        }
                        .padding(.top, 24)
                    } else if booking != nil {
                        RedButton(title: "Cancel booking") { m.present(.bookingRules(c.id)) }.padding(.top, 24)
                    } else if m.standby(forClass: c.id) != nil {
                        HStack(spacing: 12) {
                            RedButton(title: "Leave waitlist") { m.askLeaveWaitlist(c.id) }
                            // A spot opened ("Free spot" notification): it is not booked for you, so offer Book.
                            if (c.availableSpots ?? 0) > 0 { LimeButton(title: "Book") { m.present(.bookingRules(c.id)) } }
                            else { similarButton(c) }
                        }
                        .padding(.top, 24)
                    } else if (c.availableSpots ?? 1) <= 0 {
                        // Fully booked: waitlist plus "Similar classes", as in the official app. Comes before the
                        // visit-limit drop-in, so a full class offers the waitlist rather than "Buy for SEK n".
                        HStack(spacing: 12) {
                            RedButton(title: "Join waitlist") { Task { await m.joinWaitlist(c.id) } }
                            similarButton(c)
                        }
                        .padding(.top, 24)
                        if m.visitLimitReached(c) { limitNotice.padding(.top, 16) }
                    } else if m.visitLimitReached(c) {
                        // Plan's visits at this studio are used up: the original offers a paid drop-in instead of
                        // Book. The purchase call was never captured, so the button only explains that.
                        if let p = m.dropInPrice(c) {
                            LimeButton(title: "Buy for \(p.currency) \(p.amount)") { m.flash(Copy.dropInUnavailable) }.padding(.top, 24)
                        } else {
                            Text("Visit limit reached").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.secondary)
                                .frame(maxWidth: .infinity).frame(height: 54).background(Capsule().fill(Theme.chipGrey)).padding(.top, 24)
                        }
                        limitNotice.padding(.top, 16)
                    } else {
                        LimeButton(title: "Book") { m.present(.bookingRules(c.id)) }.padding(.top, 24)
                    }
                    Text(classDateLine(c)).font(.system(size: 18, weight: .semibold)).padding(.top, 20)
                    if let i = c.instructor, !i.isEmpty {
                        Text(i).font(.system(size: 17, weight: .light)).foregroundStyle(Theme.secondary).padding(.top, 4)
                    }
                    if let r = BookingRules(c) {
                        if let b = booking { bookedBox(r, checkedIn: b.checkedInAt.flatMap(BruceDate.parse)) } else { rulesLines(c, r) }
                    }
                    if m.isLoggedIn, c.start.map({ $0 > Date() }) ?? false { AutoBookToggle(c: c) }
                    if m.offersWaitlistAutoBook(c) { WaitlistAutoBookToggle(c: c) }
                    if let a = c.availableSpots {
                        Text(a > 5 ? "5+ spots left" : a <= 0 ? "Fully booked" : "\(a) spot\(a == 1 ? "" : "s") left")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(a <= 0 ? Color(red: 0.86, green: 0.15, blue: 0.15) : Theme.secondary).padding(.top, 22)
                    }
                    if let studio, studio.usesParakey { ParakeyRow(studio: studio, forClass: true).padding(.top, 22) }
                    whoIsBooked(c).padding(.top, 18).padding(.bottom, 24)
                }
                .padding(.horizontal, Theme.gutter)
                StudioInfoBlock(studio: studio, description: c.description, alerts: Alerts.forClass(c, studio: studio))
                Color.clear.frame(height: 1).id("bottom")
            }
        }
        .onAppear {
            if m.demoScrollBottom { m.demoScrollBottom = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
        }
    }

    var limitNotice: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "info.circle").font(.system(size: 26, weight: .light))
            Text(Copy.visitLimitReached).font(.system(size: 16, weight: .light)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.sectionGrey))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
    }

    func similarButton(_ c: BruceAPI.BruceClass) -> some View {
        Button { m.present(.similarClasses(c.id)) } label: {
            Text("Similar classes").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).frame(height: 54)
                .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func rulesLines(_ c: BruceAPI.BruceClass, _ r: BookingRules) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let t = c.bookableLatestTime.flatMap(BruceDate.parse) {
                iconLine("calendar.badge.checkmark", "Book until: \(BruceDate.time(t))")
            }
            iconLine("clock", "Check-in: \(BruceDate.time(r.checkInFrom)) - \(BruceDate.time(r.lateCheckIn))")
            iconLine("calendar.badge.minus", "Cancel until: \(BookingRules.long(r.lateCancel))")
        }
        .padding(.top, 22)
    }

    func bookedBox(_ r: BookingRules, checkedIn: Date? = nil) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let checkedIn {
                Label("Checked in \(BruceDate.time(checkedIn))", systemImage: "checkmark.seal.fill").font(.system(size: 15, weight: .semibold))
            }
            RuleRow(icon: "viewfinder", title: "Check in",
                    text: "\(BruceDate.format(r.start, "d MMM yyyy")), \(BruceDate.time(r.checkInFrom)) – \(BruceDate.time(r.lateCheckIn))")
            if checkedIn == nil {
                RuleRow(icon: "calendar.badge.minus", title: "Late cancellation · 1 strike", text: "Cancel after \(BookingRules.long(r.lateCancel))")
                RuleRow(icon: "calendar.badge.minus", title: "Short-notice cancellation · 2 strikes", text: "Cancel after \(BookingRules.long(r.shortNotice))")
                RuleRow(icon: "calendar.badge.minus", title: "Last-minute cancellation · 3 strikes", text: "Cancel after \(BookingRules.long(r.lastMinute))")
                Button { m.present(.addToCalendar(classId)) } label: {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.2))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).padding(.top, 4)
            }
        }
        .padding(18)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
        .padding(.top, 22)
    }

    /// Everyone booked (GET /v52/booking?class_id=), as in the original: members without a public
    /// profile show as "Hidden". Invite asks friends to this class; membership invite codes stay under Account.
    func whoIsBooked(_ c: BruceAPI.BruceClass) -> some View {
        let people = m.attendees(forClass: classId)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                Button { m.present(.classInvite(classId)) } label: {
                    VStack(spacing: 8) {
                        Circle().fill(Theme.lime).frame(width: 80, height: 80)
                            .overlay(Image(systemName: "plus").font(.system(size: 30, weight: .light)).foregroundStyle(.black))
                        Text("Invite").font(.system(size: 15, weight: .light))
                    }
                }
                .buttonStyle(.plain)
                if people.isEmpty {
                    Text("No one has booked this class yet").font(.system(size: 17, weight: .light))
                        .foregroundStyle(Theme.secondary).padding(.top, 28)
                } else {
                    ForEach(people) { p in
                        VStack(spacing: 8) {
                            if p.hidden {
                                Circle().fill(Theme.chipGrey).frame(width: 80, height: 80)
                                    .overlay(Image(systemName: "eyeglasses").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.secondary))
                                Text("Hidden").font(.system(size: 15, weight: .light)).italic().foregroundStyle(Theme.secondary)
                            } else {
                                Avatar(fileId: p.photo, initials: p.initials, size: 80)
                                Text(p.name ?? "").font(.system(size: 15, weight: .light)).lineLimit(1)
                            }
                        }
                        .frame(width: 84)
                    }
                }
            }
        }
    }

    func hero(_ c: BruceAPI.BruceClass) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemotePhoto(fileId: c.photo ?? c.studio?.photo ?? studio?.photo, w: 402, h: 287)
            Color.black.opacity(0.35)
            VStack(spacing: 6) {
                Text(c.title).font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center)
                Text([studio?.name ?? c.studio?.name, studio?.vicinity ?? c.studio?.vicinity].compactMap { $0 }.joined(separator: " | "))
                    .font(.system(size: 17))
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(categoryTitle(c) ?? "").font(.system(size: 16)).padding(Theme.gutter)
        }
        .foregroundStyle(.white)
        .frame(height: booking == nil ? 220 : 280).clipped()
    }

    /// Label comes only from the class's own `class_categories` (main first).
    func categoryTitle(_ c: BruceAPI.BruceClass) -> String? {
        let cats = c.classCategories ?? []
        guard let id = (cats.first { $0.main == true } ?? cats.first)?.categoryId else { return nil }
        return m.categories.first { $0.id == id }?.title
    }

    func iconLine(_ sym: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: sym).font(.system(size: 17, weight: .light)).frame(width: 24)
            Text(text).font(.system(size: 17, weight: .light))
        }
    }
}

/// Grabber sheet shown after tapping Book / Cancel booking.
struct BookingRulesSheet: View {
    @Environment(AppModel.self) var m
    let classId: Int
    var c: BruceAPI.BruceClass? { m.classDetails[classId] ?? m.classesByDay.values.joined().first { $0.id == classId } }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(white: 0.85)).frame(width: 92, height: 8).padding(.top, 12)
            if let c, let r = BookingRules(c) {
                let booking = m.booking(forClass: classId)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 20) {
                        Text(c.title).font(.system(size: 20, weight: .bold))
                        Text("\(classDateLine(c)) at \(m.studioName(c.studioId))").font(.system(size: 17, weight: .light))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 28).padding(.bottom, 26)
                    Rectangle().fill(Theme.divider).frame(height: 1)
                    VStack(alignment: .leading, spacing: 18) {
                        RuleRow(icon: "viewfinder", title: "Late check-in · 1 strike", text: "Check-in after \(BookingRules.long(r.lateCheckIn))")
                        RuleRow(icon: "calendar.badge.minus", title: "Late cancellation · 1 strike", text: "Cancel after \(BookingRules.long(r.lateCancel))")
                        RuleRow(icon: "calendar.badge.minus", title: "Short-notice cancellation · 2 strikes", text: "Cancel after \(BookingRules.long(r.shortNotice))")
                        RuleRow(icon: "calendar.badge.minus", title: "Last-minute cancellation · 3 strikes", text: "Cancel after \(BookingRules.long(r.lastMinute))")
                        RuleRow(icon: "calendar.badge.exclamationmark", title: "No-show · \(Policy.noShowStrikes) strikes", text: Copy.noShow)
                    }
                    .padding(.top, 26)
                    if booking != nil {
                        Text(Copy.cancelCost(strikes: r.cancelStrikes()))
                            .font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).padding(.top, 24)
                    }
                    Group {
                        if let b = booking {
                            RedButton(title: m.loading ? "Cancelling…" : "Cancel booking") {
                                Task { await m.cancel(b); m.dismissSheets() }
                            }
                        } else {
                            LimeButton(title: m.loading ? "Booking…" : "Book") {
                                Task { await m.book(classId: c.id, title: c.title); m.dismissSheets() }
                            }
                        }
                    }
                    .disabled(m.loading).padding(.top, 28)
                    HStack(alignment: .top, spacing: 24) {
                        Image(systemName: "info.circle").font(.system(size: 18, weight: .light))
                        Text(Copy.strikeFooter(unlockPrice: m.unblockPriceKr))
                            .font(.system(size: 17, weight: .light)).foregroundStyle(Theme.tertiary).lineSpacing(8)
                    }
                    .padding(.top, 28).padding(.bottom, 20)
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
        .background(Color.white)
        .clipShape(UnevenRoundedCorners(radius: 14))
    }
}

/// Tap on the "n / m" pill: visits used at the studio this month, what is left and when it resets, and every
/// tier's monthly limit at the studio with the user's plan marked (`user_visit_limit?studio_id=` `STUDIO` entry,
/// else the studio list's `visit_limit.items`).
struct VisitLimitSheet: View {
    @Environment(AppModel.self) var m
    let studioId: Int

    var body: some View {
        let tiers = m.tierLimits(studioId)
        VStack(spacing: 0) {
            NavBar(title: "", leading: m.sheets.count > 1 ? .back : .close) {
                m.sheets.count > 1 ? m.popSheet() : m.dismissSheets()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Visit limits at this studio").font(.system(size: 24, weight: .bold)).padding(.bottom, 8)
                        if tiers.isEmpty {
                            Text("No plan limits available for this studio.").foregroundStyle(Theme.secondary)
                        }
                        ForEach(tiers, id: \.tier) { t in
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(t.tier).font(.system(size: 18, weight: .heavy).width(.expanded))
                                    Text(t.limit > 0 ? "\(t.limit) visits / mo" : t.limit == 0 ? "Unlimited visits" : "Not included")
                                        .font(.system(size: 17, weight: .light)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                if t.tier == m.tier {
                                    Text("YOUR PLAN").font(.system(size: 11, weight: .semibold).width(.expanded)).foregroundStyle(Theme.lime)
                                        .padding(.horizontal, 10).padding(.vertical, 6).background(Rectangle().fill(Theme.ink))
                                }
                            }
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.sectionGrey))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cardBorder))
                        }
                        LimeButton(title: "Change plan") { m.pushSheet(.plans) }.padding(.top, 16)
                    }
                    .padding(Theme.gutter).padding(.top, 12)
                }
            }
        }
        .task {
            await m.loadStudioDetail(studioId)
            await m.loadStudioLimits(studioId)
        }
    }

    var header: some View {
        let used = m.studioVisitsThisMonth(studioId)
        let reset = m.visitLimitReset(studioId)
        let caption = Font.system(size: 13, weight: .semibold).width(.expanded)
        return VStack(alignment: .leading, spacing: 8) {
            Text(m.studioName(studioId)).font(.system(size: 20, weight: .bold))
            switch m.studioLimitState(studioId) {
            case .limited(let total):
                (Text("\(used)").foregroundStyle(Theme.lime) + Text("/\(total)"))
                    .font(.system(size: 56, weight: .light)).monospacedDigit().padding(.top, 8)
                Text("VISITS USED THIS MONTH").font(caption).foregroundStyle(.white.opacity(0.75))
                Text(Copy.visitsLeft(max(0, (m.studioVisitLimit(studioId)?.remaining) ?? (total - used)),
                                     month: BruceDate.format(Date(), "MMMM"), reset: BruceDate.format(reset, "MMMM d")))
                    .font(.system(size: 16, weight: .light)).padding(.top, 6)
            case .unlimited:
                Image(systemName: "infinity").font(.system(size: 48, weight: .light)).foregroundStyle(Theme.lime).padding(.top, 8)
                Text("UNLIMITED VISITS ON YOUR PLAN").font(caption).foregroundStyle(.white.opacity(0.75))
            case .notIncluded:
                Text("0/0").font(.system(size: 56, weight: .light)).padding(.top, 8)
                Text("NOT INCLUDED IN YOUR PLAN").font(caption).foregroundStyle(.white.opacity(0.75))
            case .unknown:
                ProgressView().controlSize(.small).padding(.top, 8)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.gutter).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.darkPanel)
    }
}

struct RedButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(Capsule().fill(Color(red: 1, green: 0.22, blue: 0.24)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Facilities strip, description, map, address and "More about" row (shared by class + studio pages).
struct StudioInfoBlock: View {
    @Environment(AppModel.self) var m
    let studio: BruceAPI.Studio?
    var description: String?
    /// Alerts shown in red under the description (class pages; the studio page shows them at the top).
    var alerts: [String] = []
    var showMoreAbout = true

    var address: BruceAPI.Address? {
        studio?.studioAddresses?.first { $0.main == true }?.address ?? studio?.studioAddresses?.first?.address
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let facilities = (studio?.studioFacilities ?? []).compactMap { $0.facility }
            if !facilities.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
                    ForEach(facilities, id: \.self) { f in
                        HStack(spacing: 14) {
                            Image(systemName: facilityIcon(f.code)).font(.system(size: 18, weight: .light))
                            Text(f.title ?? "").font(.system(size: 17, weight: .medium))
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter + 12).padding(.vertical, 14)
                .background(Theme.sectionGrey)
            }
            if !(description ?? studio?.description ?? "").isEmpty || !alerts.isEmpty {
                RichDescription(description: description ?? studio?.description, alerts: alerts, size: 17, weight: .light,
                                lineSpacing: 8, alertColor: Theme.strikeRed, buttonColor: Theme.secondary)
                    .padding(.horizontal, Theme.gutter + 12).padding(.vertical, 24)
            }
            if let a = address, let lat = a.latitude, let lon = a.longitude {
                MapSnippet(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    .frame(height: 320)
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            NSWorkspace.shared.open(URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)")!)
                        } label: {
                            Circle().fill(Theme.lime).frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "arrow.turn.up.right").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.lime)
                                        .frame(width: 30, height: 30)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black).rotationEffect(.degrees(45)))
                                )
                        }
                        .buttonStyle(.plain).padding(.trailing, Theme.gutter).offset(y: 40)
                    }
                    .zIndex(1)
                VStack(alignment: .leading, spacing: 6) {
                    Text(studio?.name ?? "").font(.system(size: 19, weight: .semibold))
                    Text([a.address, [a.zipCode, a.city].compactMap { $0 }.joined(separator: " ")].compactMap { $0 }.joined(separator: ", "))
                        .font(.system(size: 17, weight: .light)).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 18)
            }
            if showMoreAbout, let s = studio {
                Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, Theme.gutter)
                Button { m.push(.studio(s.id)) } label: {
                    HStack {
                        Text("More about \(s.name)").font(.system(size: 18, weight: .medium)).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                    }
                    .padding(.horizontal, Theme.gutter).frame(height: 92).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    func facilityIcon(_ code: String?) -> String {
        switch code ?? "" {
        case "shower": return "shower"
        case "locker", "lockers": return "cabinet"
        case "changing": return "hanger"
        case "sauna": return "thermometer.variable"
        case "towel", "towels": return "rectangle.portrait"
        case "parking": return "parkingsign.circle"
        case "rental", "mat": return "figure.yoga"
        default: return "checkmark.circle"
        }
    }
}

struct MapSnippet: View {
    let coordinate: CLLocationCoordinate2D
    var body: some View {
        if !AppModel.remoteAssets { OfflineMap() } else {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1400, longitudinalMeters: 1400)),
            interactionModes: []) {
            Annotation("", coordinate: coordinate) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 28)).foregroundStyle(.black)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))

        }
    }
}

/// Parakey-connected studio (`integration_door_type` "parakey"): the door opens with the Parakey app, using
/// an access key Bruce creates at check-in. For a class the key is valid from ten minutes before the start.
struct ParakeyRow: View {
    @Environment(AppModel.self) var m
    let studio: BruceAPI.Studio
    let forClass: Bool
    var body: some View {
        Button { m.present(.parakey(studio.id)) } label: {
            HStack(spacing: 14) {
                Image(systemName: "key.radiowaves.forward.fill").font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.parakey).frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Doors open with Parakey").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(forClass ? "Check in, then unlock with the Parakey app – from ten minutes before class."
                                  : "Check in, then unlock the door with the Parakey app.")
                        .font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(14).contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
        }
        .buttonStyle(.plain)
    }
}

struct ParakeySheet: View {
    @Environment(AppModel.self) var m
    let studioId: Int
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Parakey", leading: m.sheets.count > 1 ? .back : .close) {
                m.sheets.count > 1 ? m.popSheet() : m.dismissSheets()
            }
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "key.radiowaves.forward.fill").font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 110, height: 110)
                        .background(Theme.parakey, in: Circle()).padding(.top, 24)
                    Text("\(m.studioName(studioId)) is a Parakey connected studio. Parakey lets you use your phone as a key instead of key fobs and plastic cards.")
                    Text("When you check in with Bruce at a Parakey connected studio, an access key is created that you use to unlock doors and gates with the Parakey app on your phone. For classes the key is valid from ten minutes before the start.")
                    if let email = m.user?.parakeyEmail, !email.isEmpty {
                        Label("Your Bruce account is linked with Parakey (\(email)).", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Link("Get Parakey for iPhone", destination: Parakey.storeURL).font(.system(size: 15, weight: .semibold))
                    Link("Read more at help.parakey.co", destination: Parakey.helpURL).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                }
                .font(.system(size: 15, weight: .light)).multilineTextAlignment(.center).padding(.horizontal, Theme.gutter)
            }
        }
    }
}
