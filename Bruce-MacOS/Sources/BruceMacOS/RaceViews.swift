import SwiftUI
import AppKit

// Races on the Mac (Races.swift), simpler than on iPhone: Explore › Races, the race page, My classes › Races, Home's
// "Next race" and the editor for a race added by hand. Race names are plain text on the app's own colours; every race
// page says Brüce is not affiliated with the organiser, and sign-up opens the race's own page in the browser.

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

struct RaceCard: View {
    let race: Race
    var mine = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BibDate(race: race)
            VStack(alignment: .leading, spacing: 3) {
                Text(race.kindLabel.uppercased()).font(.system(size: 11, weight: .heavy).width(.expanded)).opacity(0.85).lineLimit(1)
                Text(race.name).font(.system(size: 19, weight: .heavy).width(.expanded)).lineLimit(2).minimumScaleFactor(0.75)
                Text([race.venue ?? race.format, race.distanceText, race.countdownShort()].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 14, weight: .medium)).opacity(0.9).lineLimit(2)
                let pill = race.pillText()
                if !pill.isEmpty {
                    Text(pill).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.22)))
                        .padding(.top, 5)
                }
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            if mine { Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.black, Theme.lime).help("In My races") }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(RaceStyle.gradient(race.type)))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Explore › Races: chips for type, country and past races, then the races under month headers.
struct RaceExploreList: View {
    @Environment(AppModel.self) var m
    @State private var types: Set<RaceType> = []
    @State private var countries: Set<String> = []
    @State private var includePast = false

    var races: [Race] { Races.filter(m.races, types: types, countries: countries, includePast: includePast) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ExploreView.chipView(selected: types.isEmpty) { Text("All") } action: { types = [] }
                    ForEach(RaceType.allCases) { t in
                        ExploreView.chipView(selected: types.contains(t)) {
                            HStack(spacing: 6) { Circle().fill(RaceStyle.dot(t)).frame(width: 9, height: 9); Text(t.title) }
                        } action: { if types.contains(t) { types.remove(t) } else { types.insert(t) } }
                    }
                    ForEach(Races.countries, id: \.code) { c in
                        ExploreView.chipView(selected: countries.contains(c.code)) { Text(c.name) } action: {
                            if countries.contains(c.code) { countries.remove(c.code) } else { countries.insert(c.code) }
                        }
                    }
                    ExploreView.chipView(selected: includePast) { Text("Past") } action: { includePast.toggle() }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 14).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if m.races.isEmpty {
                        if let e = m.racesError { EmptyState(system: "wifi.exclamationmark", text: e).frame(height: 360) }
                        else { ProgressView("Loading races…").frame(maxWidth: .infinity, minHeight: 300) }
                    } else if races.isEmpty {
                        EmptyState(system: "flag.checkered", text: Copy.racesEmpty).frame(height: 360)
                    }
                    ForEach(Races.byMonth(races)) { g in
                        Text(g.title.uppercased()).font(.system(size: 13, weight: .heavy).width(.expanded)).foregroundStyle(Theme.secondary).padding(.top, 10)
                        ForEach(g.races) { r in
                            Button { m.push(.race(r.id)) } label: { RaceCard(race: r, mine: m.isMyRace(r.id)) }.buttonStyle(.plain)
                        }
                    }
                    if !races.isEmpty { Text(Copy.raceCatalogFooter).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary).padding(.top, 12) }
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 20)
            }
        }
        .task { await m.loadRaces() }
    }
}

// MARK: - Race page

struct RaceDetailView: View {
    @Environment(AppModel.self) var m
    let raceId: String
    @State private var noteDraft = ""
    @State private var working = false

    var race: Race? { m.race(raceId) }
    var mine: MyRace? { m.myRace(forKey: raceId) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                IconButton(system: "chevron.left", size: 20) { saveNote(); m.pop() }
                Spacer()
                if let u = race?.url { ShareButton(url: u) }
            }
            .padding(.horizontal, Theme.gutter).frame(height: 56)
            if let race { content(race) }
            else if m.races.isEmpty && m.racesError == nil { Spacer(); ProgressView(); Spacer() }
            else { EmptyState(system: "flag.checkered", text: Copy.raceGone) }
        }
        .task { await m.loadRaces() }
        .onAppear { noteDraft = mine?.note ?? "" }
        .onDisappear { saveNote() }
    }

    func content(_ r: Race) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero(r)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(r.longDateText(day: mine?.day)).font(.system(size: 20, weight: .bold))
                        if let f = r.factsLine { line("point.topleft.down.to.point.bottomright.curvepath", f) }
                        line("clock", r.countdownText(day: mine?.day))
                        if let s = r.signupLine() { line("ticket", s) }
                        if let s = r.statusText(), r.status != .open, !r.opensLater() { line(RaceStyle.statusSymbol(r.status), s) }
                        if r.klassiker == true { line("rosette", "A leg of En Svensk Klassiker") }
                    }
                    if let u = r.url {
                        Button { NSWorkspace.shared.open(u) } label: {
                            Label((r.status == .open || r.status == .opensSoon) && !r.isCustom ? "Sign up on \(r.host ?? "the race page")" : "Open \(r.host ?? "the link")",
                                  systemImage: "arrow.up.right.square")
                                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.5)).contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if !r.isCustom && !r.checkedOn.isEmpty { fees(r) }
                    if r.opensLater() {
                        Toggle(isOn: Binding(get: { mine?.remindSignup ?? false }, set: { m.setRaceReminder(r, signup: $0) })) {
                            Text("\(r.statusText() ?? "") · \(Copy.raceRemindSignup.lowercased())").font(.system(size: 15))
                        }
                        .toggleStyle(.switch).tint(Theme.lime)
                    }
                    if let e = m.myRaceEntries.first(where: { $0.mine.key == raceId }), let plan = m.racePlan(for: e) {
                        Button { m.present(.racePlan(raceId)) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(Copy.planTrainForIt) · \(plan.headline())").font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    if let st = m.planWeekStatus(e, plan) { Text(st.progressText).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary) }
                                }
                                PlanPhaseStrip(plan: plan, onGradient: false)
                            }
                            .padding(14).contentShape(Rectangle())
                            .background(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder))
                        }
                        .buttonStyle(.plain)
                    }
                    if let mine { yourRace(r, mine) }
                    VStack(alignment: .leading, spacing: 6) {
                        if r.isCustom { Text(Copy.raceCustom) }
                        else if r.checkedOn.isEmpty { Text(Copy.raceGone) }
                        else if let c = Copy.raceFactsChecked(r) { Text(c) }
                        Text(Copy.raceNotAffiliated)
                    }
                    .font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 16)
            }
            if !r.isPast(day: mine?.day) {
                LimeButton(title: mine?.plan == nil ? Copy.planTrainForIt : "Your plan") { m.present(.racePlan(raceId)) }
                    .padding(.horizontal, Theme.gutter).padding(.top, 10)
            }
            Group {
                if mine == nil {
                    Button("Add to My races") { m.addToMyRaces(r) }.buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).frame(height: 30)
                } else {
                    LimeButton(title: working ? "Adding…" : "Add to Calendar") {
                        guard !working, let e = CalendarEvent(race: r, day: mine?.day) else { return }
                        working = true
                        Task {
                            let how = await CalendarWriter.add(e)
                            working = false
                            m.flash(how == .saved ? Copy.calendarAdded : "Opened in Calendar: confirm the event there")
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
        }
    }

    func hero(_ r: Race) -> some View {
        ZStack(alignment: .bottomLeading) {
            RaceStyle.gradient(r.type)
            Image(systemName: r.symbol).font(.system(size: 160, weight: .ultraLight)).foregroundStyle(.white.opacity(0.13))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).offset(x: 20, y: 20)
            VStack(alignment: .leading, spacing: 6) {
                Text(r.sport?.title ?? r.type.title).font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(.white.opacity(0.22)))
                Text(r.name.uppercased()).font(.system(size: 26, weight: .black).width(.expanded)).lineLimit(3).minimumScaleFactor(0.6)
                if !r.placeLine.isEmpty { Text(r.placeLine).font(.system(size: 15, weight: .medium)) }
            }
            .foregroundStyle(.white).padding(16)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func line(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).font(.system(size: 15, weight: .light)).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: symbol).font(.system(size: 15, weight: .light))
        }
    }

    func fees(_ r: Race) -> some View {
        let steps = r.steps, cur = r.currentStep()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Entry fee").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(cur.map { $0.priceText + (steps.count > 1 ? " now" : "") } ?? (r.status == .soldOut ? "Sold out" : "On the race page"))
                    .font(.system(size: 16, weight: .bold))
            }
            if steps.count > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                        VStack(spacing: 3) {
                            Text(RaceMoney.grouped(s.amount)).font(.system(size: 13, weight: s == cur ? .bold : .regular))
                            Text(s.from.map { "from \(RaceDay.format($0, "d MMM"))" } ?? s.until.map { "until \(RaceDay.format($0, "d MMM"))" } ?? "now")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(s == cur ? Theme.lime : Theme.chipGrey))
                    }
                }
            }
            if let n = r.priceNote { Text(n).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary) }
            if r.status == .open, !r.isPast(), r.nextPriceChange() != nil {
                Toggle(isOn: Binding(get: { mine?.remindPrice ?? false }, set: { m.setRaceReminder(r, price: $0) })) {
                    Text("Next price step · \(Copy.raceRemindPrice.lowercased())").font(.system(size: 14))
                }
                .toggleStyle(.switch).tint(Theme.lime)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sectionGrey))
    }

    func yourRace(_ r: Race, _ mine: MyRace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your race").font(.system(size: 17, weight: .bold))
            if r.isMultiDay {
                Picker("Your day", selection: Binding(get: { mine.day ?? "" }, set: { d in var x = mine; x.day = d.isEmpty ? nil : d; m.saveMyRace(x) })) {
                    Text("Every day").tag("")
                    ForEach(r.days, id: \.self) { d in Text(RaceDay.format(d, "EEE d MMM")).tag(d) }
                }
            }
            TextField("Your start, e.g. Doubles Open or 10 km", text: $noteDraft).textFieldStyle(.roundedBorder).onSubmit { saveNote() }
            if !r.isPast(day: mine.day) {
                Toggle(Copy.planRemindWeek, isOn: Binding(get: { mine.remindWeek }, set: { m.setRaceReminder(r, week: $0) })).toggleStyle(.switch).tint(Theme.lime)
                Toggle(Copy.planRemindEve, isOn: Binding(get: { mine.remindEve }, set: { m.setRaceReminder(r, eve: $0) })).toggleStyle(.switch).tint(Theme.lime)
            }
            HStack {
                if r.isCustom { Button("Edit…") { m.present(.editRace(mine.id)) } }
                Spacer()
                Button("Remove from My races") { m.removeFromMyRaces(mine.key) }.foregroundStyle(.red)
            }
            .font(.system(size: 14))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder))
    }

    func saveNote() {
        guard var x = mine else { return }
        let n = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (x.note ?? "") != n else { return }
        x.note = n.isEmpty ? nil : n
        m.saveMyRace(x)
    }
}

// MARK: - My classes › Races and Home

struct MyRacesList: View {
    @Environment(AppModel.self) var m
    var body: some View {
        let up = m.upcomingMyRaces, past = m.pastMyRaces
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { m.showRaceCatalog() } label: { Label("Find a race", systemImage: "flag.checkered") }
                    Spacer()
                    Button { m.present(.editRace(nil)) } label: { Label("Add your own", systemImage: "plus") }
                }
                .font(.system(size: 15, weight: .medium)).buttonStyle(.plain).padding(.top, 12)
                if up.isEmpty && past.isEmpty { EmptyState(system: "flag.checkered", text: Copy.myRacesEmpty).frame(height: 360) }
                if let next = up.first {
                    Button { m.push(.race(next.race.id)) } label: { NextRaceTile(entry: next, plan: m.racePlan(for: next)) }.buttonStyle(.plain)
                    if m.racePlan(for: next) == nil, (next.daysToGo() ?? 0) > 0 {
                        Button { m.present(.racePlan(next.mine.key)) } label: { Label("\(Copy.planTrainForIt): a weekly class mix up to race day", systemImage: "figure.run") }
                            .buttonStyle(.plain).font(.system(size: 14, weight: .medium))
                    }
                }
                if let ap = m.activePlan { PlanWeekList(entry: ap.entry, plan: ap.plan).padding(.top, 6) }
                ForEach(up.dropFirst() + past) { e in
                    Button { m.push(.race(e.race.id)) } label: { row(e) }.buttonStyle(.plain)
                }
                if !(up.isEmpty && past.isEmpty) {
                    Text(Copy.myRacesDevice).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 20)
        }
        .task { await m.loadRaces() }
    }

    func row(_ e: MyRaceEntry) -> some View {
        HStack(spacing: 14) {
            BibDate(race: e.race, day: e.mine.day, scale: 0.82).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.cardBorder))
            VStack(alignment: .leading, spacing: 3) {
                Text(e.race.name).font(.system(size: 16, weight: .semibold))
                Text(e.hint() ?? [e.race.venue ?? e.race.city, e.race.distanceText].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(e.isPast() ? "Done" : e.race.countdownShort(day: e.mine.day)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// The next race with its countdown (My classes › Races and Home).
struct NextRaceTile: View {
    let entry: MyRaceEntry
    var plan: RacePlan? = nil
    var body: some View {
        let r = entry.race, days = entry.daysToGo() ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(days <= 0 ? "RACE" : "\(days)").font(.system(size: days <= 0 ? 30 : 50, weight: .black).width(.expanded)).lineLimit(1).minimumScaleFactor(0.5)
                    Text(days == 1 || days <= 0 ? "DAY" : "DAYS").font(.system(size: 12, weight: .heavy).width(.expanded)).opacity(0.85)
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.name).font(.system(size: 18, weight: .heavy).width(.expanded)).lineLimit(3).minimumScaleFactor(0.75)
                    Text(entry.whenLine).font(.system(size: 14, weight: .medium)).opacity(0.9)
                    if !r.placeLine.isEmpty { Text(r.placeLine.replacingOccurrences(of: " | ", with: ", ")).font(.system(size: 14)).opacity(0.85) }
                }
                Spacer(minLength: 0)
            }
            if let plan, plan.isRunning() {
                PlanPhaseStrip(plan: plan)
                Text(plan.headline()).font(.system(size: 13, weight: .semibold))
            } else if let h = entry.hint() {
                Label(h, systemImage: entry.mine.remindSignup || entry.mine.remindPrice ? "bell.fill" : "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.16)))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(RaceStyle.gradient(r.type)))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

/// Home: "Next race" above Spotlight when My races has an upcoming race.
struct NextRaceSection: View {
    @Environment(AppModel.self) var m
    var body: some View {
        if let e = m.nextMyRace {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Next race").font(.system(size: 24, weight: .bold))
                    Spacer()
                    Button("My races") { m.showMyRaces() }.buttonStyle(.plain).font(.system(size: 15, weight: .medium))
                }
                Button { m.push(.race(e.race.id)) } label: { NextRaceTile(entry: e, plan: m.racePlan(for: e)) }.buttonStyle(.plain)
                if let plan = m.racePlan(for: e), let st = m.planWeekStatus(e, plan) {
                    HStack {
                        Text(st.progressText).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if let s = st.nextToBook {
                            Text("\(s.category.title) · \(BruceDate.format(s.c.start, "EEE HH:mm")) · \(m.studioName(s.c.studioId))")
                                .font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary).lineLimit(1)
                            Button("Book") { m.bookPlanned(s) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 20)
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

    var existing: MyRace? { raceId.flatMap { id in m.myRaces.first { $0.id == id } } }
    var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (link.isEmpty || Races.webURL(link) != nil) }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: raceId == nil ? "Add a race" : "Edit race", leading: .close, action: { m.dismissSheets() }) {
                Button("Save") { save() }.disabled(!valid).buttonStyle(.plain).font(.system(size: 16, weight: .bold))
            }
            Form {
                TextField("Name", text: $name)
                DatePicker("Date", selection: $date, displayedComponents: .date)   // Stockholm days (RaceDay), wherever the Mac is
                    .environment(\.timeZone, BruceDate.tz).environment(\.calendar, BruceDate.calendar)
                Picker("Type", selection: $type) { ForEach(RaceType.allCases) { Text($0.title).tag($0) } }
                TextField("City", text: $city)
                TextField("Link to the race page", text: $link)
                TextField("Your start", text: $note)
                Text(Copy.raceCustom).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary)
                if let existing {
                    Button("Remove from My races") { m.dismissSheets(); m.removeFromMyRaces(existing.key) }.foregroundStyle(.red)
                }
            }
            .padding(Theme.gutter)
            Spacer()
        }
        .onAppear {
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
        if existing == nil { m.flash(Copy.raceAdded) }
    }
}
