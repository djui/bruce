import SwiftUI

// Races (Races.swift): Explore › Races, the race page, My classes › Races, Home's "Next race" and the editor for a
// race added by hand. Race names are plain text on the app's own colours (no logos, no race or brand colours), sign-up
// always happens on the race's own page, and every race page says Brüce is not affiliated with the organiser.

/// Race-bib date: month, day, and the last day (multi-day events) or the weekday.
struct BibDate: View {
    let race: Race
    var day: String? = nil
    var scale: CGFloat = 1
    var body: some View {
        let first = day ?? race.date
        let multi = day == nil && race.isMultiDay
        VStack(spacing: 0) {
            Text(RaceDay.format(first, "MMM").uppercased()).font(.system(size: 11 * scale, weight: .heavy).width(.expanded))
            Text(RaceDay.format(first, "d")).font(.system(size: 25 * scale, weight: .black).width(.expanded)).monospacedDigit()
            Text(multi ? "–" + RaceDay.format(race.lastDay, "d") : RaceDay.format(first, "EEE").uppercased())
                .font(.system(size: 11 * scale, weight: .bold))
        }
        .foregroundStyle(.black)
        .frame(width: 58 * scale, height: 66 * scale)
        .background(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous).fill(.white))
        .overlay(alignment: .top) {
            HStack { hole; Spacer(); hole }.padding(.horizontal, 6 * scale).padding(.top, 5 * scale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(race.dateText(day: day))
    }
    var hole: some View { Circle().fill(Color.black.opacity(0.2)).frame(width: 4 * scale, height: 4 * scale) }
}

/// Explore › Races card: bib date, type and city, name, venue and countdown, the price or status pill.
struct RaceCard: View {
    let race: Race
    var mine = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BibDate(race: race)
            VStack(alignment: .leading, spacing: 3) {
                Text(race.kindLabel.uppercased()).bruceFont(11, weight: .heavy, width: .expanded).opacity(0.85).lineLimit(1)
                Text(race.name).bruceFont(19, weight: .heavy, width: .expanded).lineLimit(2).minimumScaleFactor(0.75)
                Text(subtitle).bruceFont(14, weight: .medium).opacity(0.9).lineLimit(2)
                let pill = race.pillText()
                if !pill.isEmpty {
                    Text(pill).bruceFont(13, weight: .semibold)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: Capsule())
                        .padding(.top, 5)
                }
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            if mine {
                Image(systemName: "checkmark.circle.fill").bruceFont(20, weight: .semibold).foregroundStyle(.black, Theme.lime)
                    .accessibilityLabel("In My races")
            }
        }
        .padding(14)
        .background {
            ZStack(alignment: .bottomTrailing) {
                RaceStyle.gradient(race.type)
                Image(systemName: race.symbol).font(.system(size: 96, weight: .ultraLight)).foregroundStyle(.white.opacity(0.10))
                    .offset(x: 14, y: 16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    var subtitle: String {
        [race.venue ?? race.format, race.distanceText, race.countdownShort()].compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }
}

/// Explore › Races chips: country and past races (menu), then All and the types.
struct RaceFilterChips: View {
    @Binding var types: Set<RaceType>
    @Binding var countries: Set<String>
    @Binding var includePast: Bool

    var body: some View {
        let n = countries.count + (includePast ? 1 : 0)
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Menu {
                        Section("Country") {
                            Button { countries = [] } label: { check("All countries", countries.isEmpty) }
                            ForEach(Races.countries, id: \.code) { c in
                                Button {
                                    if countries.contains(c.code) { countries.remove(c.code) } else { countries.insert(c.code) }
                                } label: { check(c.name, countries.contains(c.code)) }
                            }
                        }
                        Toggle("Show past races", isOn: $includePast)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                            if n > 0 { Text("\(n)").monospacedDigit() }
                        }
                        .bruceFont(15, weight: .semibold)
                        .foregroundStyle(n > 0 ? Color.black : Theme.ink)
                        .padding(.horizontal, 14).frame(height: 36)
                        .contentShape(Capsule())
                    }
                    .glassEffect(n > 0 ? .regular.tint(Theme.lime).interactive() : .regular.interactive(), in: .capsule)
                    .accessibilityLabel("Country and past races")
                    GlassChip("All", selected: types.isEmpty) { withAnimation { types = [] } }
                    ForEach(RaceType.allCases) { t in
                        GlassChip(selected: types.contains(t), action: {
                            withAnimation { if types.contains(t) { types.remove(t) } else { types.insert(t) } }
                        }) {
                            HStack(spacing: 6) {
                                Circle().fill(RaceStyle.dot(t)).frame(width: 9, height: 9)
                                Text(t.title)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    @ViewBuilder func check(_ title: String, _ on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

/// Explore › Races list under month headers.
struct RaceList: View {
    @Environment(AppModel.self) var m
    let races: [Race]
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if m.races.isEmpty {
                if let e = m.racesError { EmptyState(system: "wifi.exclamationmark", text: e) }
                else { ProgressView("Loading races…").frame(maxWidth: .infinity, minHeight: 300) }
            } else if races.isEmpty {
                EmptyState(system: "flag.checkered", text: Copy.racesEmpty)
            }
            ForEach(Races.byMonth(races)) { g in
                Text(g.title.uppercased()).bruceFont(13, weight: .heavy, width: .expanded).foregroundStyle(Theme.secondary)
                    .padding(.top, 10).accessibilityAddTraits(.isHeader)
                ForEach(g.races) { r in
                    NavigationLink(value: Route.race(r.id)) { RaceCard(race: r, mine: m.isMyRace(r.id)) }
                        .buttonStyle(.plain)
                }
            }
            if !races.isEmpty {
                Text(Copy.raceCatalogFooter).bruceFont(13).foregroundStyle(Theme.secondary).padding(.top, 14)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 8)
    }
}

// MARK: - Race page

struct RaceDetailView: View {
    @Environment(AppModel.self) var m
    @Environment(\.openURL) private var openURL
    let raceId: String
    @State private var calendarOpen = false
    @State private var noteDraft = ""
    @FocusState private var noteFocused: Bool

    var race: Race? { m.race(raceId) }
    var mine: MyRace? { m.myRace(forKey: raceId) }

    var body: some View {
        Group {
            if let race { content(race) }
            // Opened before the catalog is in (a reminder tapped on a cold start): wait for it before saying "gone".
            else if m.races.isEmpty && m.racesError == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { EmptyState(system: "flag.checkered", text: Copy.raceGone) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let u = race?.url {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share the race page")
                }
            }
        }
        .sheet(isPresented: $calendarOpen) {
            if let race, let e = CalendarEvent(race: race, day: mine?.day) {
                EventEditor(event: e) { saved in
                    calendarOpen = false
                    if saved { m.flash(Copy.calendarAdded, icon: "calendar.badge.checkmark") }
                }
                .ignoresSafeArea()
            }
        }
        .task { await m.loadRaces() }
        .onAppear { noteDraft = mine?.note ?? "" }
        .onDisappear { saveNote() }
    }

    func content(_ r: Race) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(r)
                VStack(alignment: .leading, spacing: 16) {
                    facts(r)
                    if let u = r.url { signupButton(r, u) }
                    if !r.isCustom && !r.checkedOn.isEmpty { feeCard(r) }
                    if r.opensLater() { signupCard(r) }
                    if let mine { yourRace(r, mine) }
                    footnotes(r)
                }
                .padding(Theme.gutter)
            }
        }
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) { actionBar(r) }
    }

    func hero(_ r: Race) -> some View {
        ZStack(alignment: .bottomLeading) {
            RaceStyle.gradient(r.type)
            Image(systemName: r.symbol).font(.system(size: 210, weight: .ultraLight)).foregroundStyle(.white.opacity(0.13))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 34, y: 56)
            LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(r.sport?.title ?? r.type.title).bruceFont(13, weight: .semibold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                Text(r.name.uppercased()).bruceFont(28, weight: .black, width: .expanded).lineLimit(3).minimumScaleFactor(0.6)
                if !r.placeLine.isEmpty { Text(r.placeLine).bruceFont(16, weight: .medium) }
            }
            .foregroundStyle(.white).padding(Theme.gutter)
        }
        .frame(height: 300).clipped()
        .accessibilityElement(children: .combine)
    }

    func facts(_ r: Race) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(r.longDateText(day: mine?.day)).bruceFont(20, weight: .bold).fixedSize(horizontal: false, vertical: true)
            if let f = r.factsLine { line("point.topleft.down.to.point.bottomright.curvepath", f) }
            line("clock", r.countdownText(day: mine?.day))
            if let s = r.signupLine() { line("ticket", s) }
            if r.status != .open, !r.opensLater(), let s = r.statusText() { line(RaceStyle.statusSymbol(r.status), s) }
            if r.klassiker == true { line("rosette", "A leg of En Svensk Klassiker") }
        }
    }

    func line(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).bruceFont(16).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.limeInk)
        }
    }

    func feeCard(_ r: Race) -> some View {
        let steps = r.steps, cur = r.currentStep()
        let headline = cur.map { $0.priceText + (steps.count > 1 ? " now" : "") } ?? (r.status == .soldOut ? "Sold out" : "On the race page")
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Entry fee").bruceFont(15).foregroundStyle(Theme.secondary)
                Spacer()
                Text(headline).bruceFont(17, weight: .bold).multilineTextAlignment(.trailing)
            }
            if steps.count > 1 { PriceLadder(steps: steps, current: cur) }
            if let note = r.priceNote { Text(note).bruceFont(14).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
            if r.status == .open, !r.isPast(), let next = nextPriceLine(r) {
                Divider()
                Toggle(isOn: Binding(get: { mine?.remindPrice ?? false }, set: { m.setRaceReminder(r, price: $0) })) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next).bruceFont(15, weight: .semibold)
                            Text(Copy.raceRemindPrice).bruceFont(13).foregroundStyle(Theme.secondary)
                        }
                    } icon: { Image(systemName: "bell") }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    /// "775 SEK from 1 Nov", or "1,045 SEK until 14 Feb" when the next price is not known yet.
    func nextPriceLine(_ r: Race) -> String? {
        if let n = r.nextStep(), let f = n.from { return "\(n.priceText) from \(RaceDay.format(f, "d MMM"))" }
        if let c = r.currentStep(), let u = c.until { return "\(c.priceText) until \(RaceDay.format(u, "d MMM"))" }
        return nil
    }

    func signupCard(_ r: Race) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(r.statusText() ?? "", systemImage: "calendar.badge.clock").bruceFont(16, weight: .semibold)
            Toggle(Copy.raceRemindSignup, isOn: Binding(get: { mine?.remindSignup ?? false }, set: { m.setRaceReminder(r, signup: $0) }))
                .bruceFont(15)
        }
        .padding(16)
        .glassEffect(.regular.tint(Theme.lime.opacity(0.12)), in: .rect(cornerRadius: 24))
    }

    func signupButton(_ r: Race, _ u: URL) -> some View {
        let host = r.host ?? "the race page"
        let title = r.isCustom ? "Open \(host)" : (r.status == .open || r.status == .opensSoon ? "Sign up on \(host)" : "Open \(host)")
        return Button { openURL(u) } label: {
            Label(title, systemImage: "arrow.up.right.square").bruceFont(17, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).frame(height: 40)
        }
        .buttonStyle(.glass).controlSize(.large)
        .accessibilityHint("Opens the race's own page in Safari")
    }

    func yourRace(_ r: Race, _ mine: MyRace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR RACE").bruceHeading(16)
            if r.isMultiDay {
                HStack {
                    Text("Your day").bruceFont(16)
                    Spacer()
                    Picker("Your day", selection: Binding(get: { mine.day ?? "" }, set: { d in
                        var x = mine; x.day = d.isEmpty ? nil : d; m.saveMyRace(x)
                    })) {
                        Text("Every day").tag("")
                        ForEach(r.days, id: \.self) { d in Text(RaceDay.format(d, "EEE d MMM")).tag(d) }
                    }
                    .pickerStyle(.menu)
                }
            }
            TextField("Your start, e.g. Doubles Open or 10 km", text: $noteDraft)
                .focused($noteFocused).submitLabel(.done)
                .onSubmit { saveNote() }
                .onChange(of: noteFocused) { _, f in if !f { saveNote() } }
                .bruceFont(16)
                .padding(.horizontal, 14).frame(height: 44)
                .background(Theme.chipGrey, in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 10) {
                if r.isCustom {
                    Button { m.present(.editRace(mine.id)) } label: {
                        Label("Edit", systemImage: "pencil").bruceFont(15, weight: .semibold).padding(.horizontal, 12).frame(height: 34)
                    }
                    .buttonStyle(.glass)
                }
                Spacer()
                Button(role: .destructive) { m.removeFromMyRaces(mine.key) } label: {
                    Text("Remove from My races").bruceFont(15, weight: .semibold)
                }
                .foregroundStyle(Theme.red)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    func footnotes(_ r: Race) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if r.isCustom { Text(Copy.raceCustom) }
            else if r.checkedOn.isEmpty { Text(Copy.raceGone) }
            else if let c = Copy.raceFactsChecked(r) { Text(c) }
            Text(Copy.raceNotAffiliated)
        }
        .bruceFont(13).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        .padding(.top, 4)
    }

    @ViewBuilder func actionBar(_ r: Race) -> some View {
        Group {
            if mine == nil {
                LimeButton(title: "Add to My races", systemImage: "plus") { m.addToMyRaces(r) }
            } else {
                LimeButton(title: "Add to Calendar", systemImage: "calendar.badge.plus") { calendarOpen = true }
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 8)
    }

    func saveNote() {
        guard var x = mine else { return }
        let n = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (x.note ?? "") != n else { return }
        x.note = n.isEmpty ? nil : n
        m.saveMyRace(x)
    }
}

/// The known entry fees as bars, the one that applies today in lime.
struct PriceLadder: View {
    let steps: [PriceStep]
    let current: PriceStep?
    var body: some View {
        let amounts = steps.map { Double($0.amount) }
        let lo = amounts.min() ?? 0, hi = amounts.max() ?? 1
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                let on = s == current
                VStack(spacing: 4) {
                    Text(RaceMoney.grouped(s.amount)).bruceFont(12, weight: on ? .bold : .medium).monospacedDigit()
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Theme.lime : Theme.chipGrey)
                        .frame(height: 22 + 34 * (Double(s.amount) - lo) / max(hi - lo, 1))
                    Text(label(s)).bruceFont(11).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(steps.map { "\($0.priceText) \(label($0))" }.joined(separator: ", "))
    }
    func label(_ s: PriceStep) -> String {
        if let f = s.from { return "from \(RaceDay.format(f, "d MMM"))" }
        if let u = s.until { return "until \(RaceDay.format(u, "d MMM"))" }
        return "now"
    }
}

// MARK: - My classes › Races

struct MyRacesSection: View {
    @Environment(AppModel.self) var m
    var body: some View {
        let up = m.upcomingMyRaces, past = m.pastMyRaces
        VStack(alignment: .leading, spacing: 12) {
            if up.isEmpty && past.isEmpty {
                EmptyState(system: "flag.checkered", text: Copy.myRacesEmpty)
                HStack(spacing: 10) {
                    Button { m.showRaceCatalog() } label: {
                        Text("Find a race").bruceFont(16, weight: .bold).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 40)
                    }
                    .buttonStyle(.glassProminent).tint(Theme.lime)
                    Button { m.present(.editRace(nil)) } label: {
                        Text("Add your own").bruceFont(16, weight: .bold).foregroundStyle(Theme.ink).frame(maxWidth: .infinity).frame(height: 40)
                    }
                    .buttonStyle(.glass)
                }
            }
            if let next = up.first {
                NavigationLink(value: Route.race(next.race.id)) { NextRaceBanner(entry: next) }.buttonStyle(.plain)
            }
            if up.count > 1 {
                header("Later", up.count - 1 == 1 ? "1 race" : "\(up.count - 1) races")
                rows(Array(up.dropFirst()))
            }
            if !past.isEmpty {
                header("Done", past.count == 1 ? "1 race" : "\(past.count) races")
                rows(past)
            }
            if !(up.isEmpty && past.isEmpty) {
                Text(Copy.myRacesDevice).bruceFont(13).foregroundStyle(Theme.secondary).padding(.top, 6)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
        .task { await m.loadRaces() }
    }

    func header(_ t: String, _ trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t.uppercased()).bruceHeading(16)
            Spacer()
            Text(trailing).bruceFont(14).foregroundStyle(Theme.secondary)
        }
        .padding(.top, 10)
        .accessibilityAddTraits(.isHeader)
    }

    func rows(_ list: [MyRaceEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { e in
                NavigationLink(value: Route.race(e.race.id)) { MyRaceRow(entry: e) }.buttonStyle(.plain)
                if e.id != list.last?.id { Divider().padding(.leading, 84) }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// My classes › Races: the next race, big.
struct NextRaceBanner: View {
    let entry: MyRaceEntry
    var body: some View {
        let r = entry.race
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(([r.sport?.title ?? r.type.title] + [entry.mine.note].compactMap { $0?.isEmpty == false ? $0 : nil }).joined(separator: " · "))
                    .bruceFont(13, weight: .semibold).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.22), in: Capsule())
                Spacer(minLength: 8)
                Text(r.countdownShort(day: entry.mine.day)).bruceFont(22, weight: .black, width: .expanded).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(r.name).bruceFont(22, weight: .heavy, width: .expanded).lineLimit(2).minimumScaleFactor(0.75).padding(.top, 4)
            Text(([RaceDay.format(entry.day, "EEE d MMM")] + [r.venue ?? (r.city.isEmpty ? nil : r.city)].compactMap { $0 }).joined(separator: " · "))
                .bruceFont(15, weight: .medium).opacity(0.9)
            if let h = entry.hint() {
                Label(h, systemImage: entry.mine.remindSignup || entry.mine.remindPrice ? "bell.fill" : "info.circle")
                    .bruceFont(14, weight: .semibold).padding(.top, 6)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                RaceStyle.gradient(r.type)
                Image(systemName: r.symbol).font(.system(size: 110, weight: .ultraLight)).foregroundStyle(.white.opacity(0.10)).offset(x: 16, y: 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct MyRaceRow: View {
    let entry: MyRaceEntry
    var body: some View {
        let r = entry.race
        HStack(spacing: 14) {
            BibDate(race: r, day: entry.mine.day, scale: 0.82)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.name).bruceFont(16, weight: .semibold).lineLimit(2)
                Text(entry.hint() ?? [r.venue ?? (r.city.isEmpty ? nil : r.city), r.distanceText].compactMap { $0 }.joined(separator: " · "))
                    .bruceFont(14).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            .foregroundStyle(Theme.ink)
            Spacer(minLength: 4)
            Text(countdown).bruceFont(15, weight: .bold).monospacedDigit().foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    var countdown: String {
        guard let d = entry.daysToGo(), !entry.isPast() else { return entry.isPast() ? "Done" : "" }
        return d <= 0 ? "Today" : "\(d) d"
    }
}

// MARK: - Home

/// Home: the next race in My races with its countdown, above Spotlight.
struct NextRaceCard: View {
    @Environment(AppModel.self) var m
    var body: some View {
        if let e = m.nextMyRace {
            let r = e.race
            let days = e.daysToGo() ?? 0
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("NEXT RACE").bruceHeading(19)
                    Spacer()
                    Button { m.showMyRaces() } label: { Text("My races").bruceFont(15, weight: .semibold) }.buttonStyle(.glass)
                }
                NavigationLink(value: Route.race(r.id)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(days <= 0 ? "RACE" : "\(days)").bruceFont(days <= 0 ? 34 : 56, weight: .black, width: .expanded)
                                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                                Text(days <= 0 ? "DAY" : days == 1 ? "DAY" : "DAYS").bruceFont(12, weight: .heavy, width: .expanded).opacity(0.85)
                            }
                            .fixedSize()
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).bruceFont(19, weight: .heavy, width: .expanded).lineLimit(3).minimumScaleFactor(0.75)
                                Text(e.whenLine).bruceFont(14, weight: .medium).opacity(0.9)
                                if !r.placeLine.isEmpty { Text(r.placeLine.replacingOccurrences(of: " | ", with: ", ")).bruceFont(14).opacity(0.85) }
                            }
                            Spacer(minLength: 0)
                        }
                        if let h = e.hint() {
                            Label(h, systemImage: e.mine.remindSignup || e.mine.remindPrice ? "bell.fill" : "info.circle")
                                .bruceFont(14, weight: .semibold)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .background {
                        ZStack(alignment: .bottomTrailing) {
                            RaceStyle.gradient(r.type)
                            Image(systemName: r.symbol).font(.system(size: 120, weight: .ultraLight)).foregroundStyle(.white.opacity(0.10)).offset(x: 16, y: 22)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next race: \(r.name), \(r.countdownText(day: e.mine.day))")
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 26)
        }
    }
}

// MARK: - Add or edit a race by hand

struct RaceEditor: View {
    @Environment(AppModel.self) var m
    let raceId: UUID?
    @State private var name = ""
    @State private var date = BruceDate.calendar.date(byAdding: .day, value: 56, to: Date()) ?? Date()
    @State private var type: RaceType = .running
    @State private var city = ""
    @State private var link = ""
    @State private var note = ""
    @State private var loaded = false

    var existing: MyRace? { raceId.flatMap { id in m.myRaces.first { $0.id == id } } }
    var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (link.isEmpty || Races.webURL(link) != nil) }

    var body: some View {
        Form {
            if raceId == nil {
                Section {
                    Button { m.showRaceCatalog() } label: { Label("Pick one from Explore › Races", systemImage: "flag.checkered") }
                } footer: { Text("About 30 races in Sweden, Norway and Denmark, with prices and sign-up dates.") }
            }
            Section("Race") {
                TextField("Name", text: $name).textInputAutocapitalization(.words)
                // Race days are Stockholm days (RaceDay), wherever the phone is.
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .environment(\.timeZone, BruceDate.tz).environment(\.calendar, BruceDate.calendar)
                Picker("Type", selection: $type) { ForEach(RaceType.allCases) { Text($0.title).tag($0) } }
                TextField("City", text: $city).textInputAutocapitalization(.words)
            }
            Section {
                TextField("Link to the race page", text: $link)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Your start, e.g. 10 km or Doubles Open", text: $note)
            } footer: {
                Text(link.isEmpty || Races.webURL(link) != nil ? "Optional. Brüce only opens the link." : "That doesn't look like a web address.")
            }
            if let existing {
                Section {
                    Button("Remove from My races", role: .destructive) { m.dismissSheets(); m.removeFromMyRaces(existing.key) }
                }
            }
            Section { } footer: { Text(Copy.raceCustom) }
        }
        .bruceFont(16)
        .sheetChrome(raceId == nil ? "Add a race" : "Edit race")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = existing {
                name = e.name; date = RaceDay.date(e.date) ?? date; type = e.type
                city = e.city ?? ""; link = e.url ?? ""; note = e.note ?? ""
            }
        }
    }

    func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var r = existing ?? MyRace(name: n, date: RaceDay.iso(date))
        r.name = n; r.date = RaceDay.iso(date); r.type = type
        r.city = c.isEmpty ? nil : c
        r.url = Races.webURL(link)?.absoluteString
        r.note = t.isEmpty ? nil : t
        m.saveMyRace(r)
        m.dismissSheets()
        if existing == nil { m.flash(Copy.raceAdded, icon: "flag.checkered") }
    }
}
