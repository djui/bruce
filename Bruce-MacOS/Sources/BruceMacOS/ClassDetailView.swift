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
                if let msg = studio?.notice {
                    Text(msg).font(.system(size: 15, weight: .light)).foregroundStyle(.white).multilineTextAlignment(.center)
                        .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.91, green: 0.30, blue: 0.29)))
                        .padding(.horizontal, Theme.gutter).padding(.bottom, 16)
                }
                hero(c)
                VStack(alignment: .leading, spacing: 0) {
                    if booking != nil {
                        RedButton(title: "Cancel booking") { m.present(.bookingRules(c.id)) }.padding(.top, 24)
                    } else if m.standby(forClass: c.id) != nil {
                        RedButton(title: "Leave waitlist") { m.askLeaveWaitlist(c.id) }.padding(.top, 24)
                    } else if (c.availableSpots ?? 1) <= 0 {
                        RedButton(title: "Join waitlist") { Task { await m.joinWaitlist(c.id) } }.padding(.top, 24)
                    } else {
                        LimeButton(title: "Book") { m.present(.bookingRules(c.id)) }.padding(.top, 24)
                    }
                    Text(classDateLine(c)).font(.system(size: 18, weight: .semibold)).padding(.top, 20)
                    if let i = c.instructor, !i.isEmpty {
                        Text(i).font(.system(size: 17, weight: .light)).foregroundStyle(Theme.secondary).padding(.top, 4)
                    }
                    if let r = BookingRules(c) {
                        if booking != nil { bookedBox(r) } else { rulesLines(c, r) }
                    }
                    if let a = c.availableSpots {
                        Text(a > 5 ? "5+ spots left" : a <= 0 ? "Fully booked" : "\(a) spot\(a == 1 ? "" : "s") left")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(a <= 0 ? Color(red: 0.86, green: 0.15, blue: 0.15) : Theme.secondary).padding(.top, 22)
                    }
                    whoIsBooked(c).padding(.top, 18).padding(.bottom, 24)
                }
                .padding(.horizontal, Theme.gutter)
                StudioInfoBlock(studio: studio, description: c.description)
                Color.clear.frame(height: 1).id("bottom")
            }
        }
        .onAppear {
            if m.demoScrollBottom { m.demoScrollBottom = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
        }
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

    func bookedBox(_ r: BookingRules) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RuleRow(icon: "viewfinder", title: "Check in",
                    text: "\(BruceDate.format(r.start, "d MMM yyyy")), \(BruceDate.time(r.checkInFrom)) – \(BruceDate.time(r.lateCheckIn))")
            RuleRow(icon: "calendar.badge.minus", title: "Late cancellation", text: "Cancel after \(BookingRules.long(r.lateCancel))")
            RuleRow(icon: "calendar.badge.minus", title: "Short-notice cancellation", text: "Cancel after \(BookingRules.long(r.shortNotice))")
        }
        .padding(18)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
        .padding(.top, 22)
    }

    /// Everyone booked (GET /v52/booking?class_id=), as in the original: members without a public
    /// profile show as "Hidden". Invite shares this class with friends; membership invite codes stay under Account.
    func whoIsBooked(_ c: BruceAPI.BruceClass) -> some View {
        let people = m.attendees(forClass: classId)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ShareLink(item: ShareURL.forClass(classId, title: c.title),
                          message: Text(Copy.classInvite(c, studio: m.studioName(c.studioId)))) {
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
                        RuleRow(icon: "viewfinder", title: "Late check-in", text: "Check-in after \(BookingRules.long(r.lateCheckIn))")
                        RuleRow(icon: "calendar.badge.minus", title: "Late cancellation", text: "Cancel after \(BookingRules.long(r.lateCancel))")
                        RuleRow(icon: "calendar.badge.minus", title: "Short-notice cancellation", text: "Cancel after \(BookingRules.long(r.shortNotice))")
                        RuleRow(icon: "calendar.badge.minus", title: "Last-minute cancellation", text: "Cancel after \(BookingRules.long(r.lastMinute))")
                        RuleRow(icon: "calendar.badge.exclamationmark", title: "No-show", text: Copy.noShow)
                    }
                    .padding(.top, 26)
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
            if let d = description ?? studio?.description, !d.isEmpty {
                Text(d).font(.system(size: 17, weight: .light)).lineSpacing(8)
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
