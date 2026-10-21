import SwiftUI

// Train for it (RacePlanner.swift) on iPhone: the plan sheet (phase strip, weeks × categories grid, sessions per week,
// start and stop), the week bar and "This week" in My classes › Races, and the week line and next class on Home's
// Next race card. It is a class mix, not coaching: every week can be changed, and the copy says it doesn't plan long
// runs, rides or swims.

extension RacePlan {
    var currentWeek: PlanWeek? { if case .active(let w) = status() { return w } else { return nil } }
}

/// Base · Build · Peak · Race: one bar per week of the block, past weeks full, this week lime, the phase names under.
struct PlanPhaseStrip: View {
    let plan: RacePlan
    /// White on a race gradient, or ink on the sheet.
    var onGradient = true

    var body: some View {
        let current = plan.currentWeek
        let block = plan.weeks.filter { $0.phase != .recovery }
        let groups = plan.segments.reduce(into: [(phase: PlanPhase, weeks: [PlanWeek])]()) { acc, seg in
            let start = acc.map(\.weeks.count).reduce(0, +)
            acc.append((seg.phase, Array(block[start..<min(block.count, start + seg.weeks)])))
        }
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let gap: CGFloat = 3
                let n = CGFloat(max(block.count, 1))
                let unit = max(4, (geo.size.width - gap * (n - 1)) / n)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: gap) {
                                ForEach(g.weeks) { w in
                                    Capsule().fill(fill(w, current)).frame(width: unit, height: 7)
                                }
                            }
                            Text(g.phase.short).bruceFont(11, weight: .bold).lineLimit(1).minimumScaleFactor(0.6)
                                .opacity(g.weeks.contains { $0.id == current?.id } ? 1 : 0.75)
                        }
                        .frame(width: unit * CGFloat(g.weeks.count) + gap * CGFloat(max(0, g.weeks.count - 1)), alignment: .leading)
                    }
                }
            }
            .frame(height: 26)
            HStack {
                Text(block.first?.label ?? "")
                Spacer()
                Text(block.last?.label ?? "")
            }
            .bruceFont(11, weight: .medium).opacity(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plan.segments.map { "\($0.phase.title) \($0.weeks) week\($0.weeks == 1 ? "" : "s")" }.joined(separator: ", ") + ". " + plan.headline())
    }

    func fill(_ w: PlanWeek, _ current: PlanWeek?) -> Color {
        if w.id == current?.id { return Theme.lime }
        let past = (current.map { w.index < $0.index } ?? (plan.status() == .done))
        if onGradient { return .white.opacity(past ? 0.85 : 0.3) }
        return past ? Theme.ink.opacity(0.55) : Theme.chipGrey
    }
}

/// The weeks × categories table of the report: sessions per week and category, this week outlined, the member's own
/// changes dotted. Tapping a number (this week and later) steps it 0 → 3.
struct PlanGrid: View {
    let plan: RacePlan
    var onTap: ((PlanWeek, PlanCategory) -> Void)? = nil

    var body: some View {
        let rows = plan.rows.filter { c in plan.weeks.contains { $0.count(c) > 0 } }
        let current = plan.currentWeek
        let today = RaceDay.today()
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 18)
                Color.clear.frame(height: 20)
                ForEach(rows) { c in Text(c.short).bruceFont(13, weight: .medium).lineLimit(1).frame(height: 32, alignment: .leading) }
                Text("Total").bruceFont(13, weight: .bold).frame(height: 30, alignment: .leading)
            }
            .frame(width: 70, alignment: .leading)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(plan.weeks) { w in
                            column(w, rows: rows, current: w.id == current?.id, past: w.sunday < today,
                                   phaseStart: w.index == 0 || plan.weeks[w.index - 1].phase != w.phase)
                                .id(w.id)
                        }
                    }
                    .padding(.trailing, 30)
                }
                .onAppear { if let c = current { proxy.scrollTo(c.id, anchor: .center) } }
            }
        }
    }

    func column(_ w: PlanWeek, rows: [PlanCategory], current: Bool, past: Bool, phaseStart: Bool) -> some View {
        VStack(spacing: 0) {
            Text(phaseStart ? w.phase.short : " ").bruceFont(11, weight: .heavy).foregroundStyle(Theme.secondary)
                .fixedSize().frame(width: 32, height: 18, alignment: .leading)
            Text(w.label).bruceFont(11, weight: current ? .bold : .medium).foregroundStyle(current ? Theme.ink : Theme.secondary)
                .frame(height: 20)
            ForEach(rows) { c in cell(w, c, editable: !past && onTap != nil) }
            Text("\(w.total)").bruceFont(14, weight: .bold).monospacedDigit().frame(height: 30)
        }
        .frame(width: 34)
        .opacity(past ? 0.55 : 1)
        .background {
            if current { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.limeInk, lineWidth: 2).padding(.top, 18) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(w.label), \(w.phase.title): " + rows.compactMap { w.count($0) > 0 ? "\(w.count($0)) \($0.title)" : nil }.joined(separator: ", "))
    }

    func cell(_ w: PlanWeek, _ c: PlanCategory, editable: Bool) -> some View {
        let n = w.count(c)
        return Button { onTap?(w, c) } label: {
            Text(n == 0 ? "–" : "\(n)").bruceFont(14, weight: n > 0 ? .semibold : .regular).monospacedDigit()
                .foregroundStyle(n == 0 ? Theme.tertiary : Color.black)
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(n == 0 ? Color.clear : Theme.lime.opacity(0.35 + 0.2 * Double(min(n, 3)))))
                .overlay(alignment: .topTrailing) {
                    if w.edited.contains(c) { Circle().fill(Theme.ink).frame(width: 5, height: 5).padding(3) }
                }
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .frame(height: 32)
    }
}

// MARK: - The plan sheet

struct RacePlanSheet: View {
    @Environment(AppModel.self) var m
    let key: String
    @State private var perWeek = RacePlanSettings.defaultPerWeek
    @State private var weeks = RacePlanSettings.defaultWeeks
    @State private var confirmStop = false

    var entry: MyRaceEntry? { m.myRaceEntries.first { $0.mine.key == key } }
    var race: Race? { entry?.race ?? m.race(key) }

    var body: some View {
        ScrollView {
            if let r = race {
                VStack(alignment: .leading, spacing: 18) {
                    header(r)
                    if let e = entry, let plan = m.racePlan(for: e) { active(r, e, plan) } else { preview(r) }
                }
                .padding(Theme.gutter)
            } else {
                EmptyState(system: "flag.checkered", text: Copy.raceGone)
            }
        }
        .sheetChrome(Copy.planTrainForIt)
        .alert("Stop this plan?", isPresented: $confirmStop) {
            Button("Stop plan", role: .destructive) { m.stopPlan(key); m.dismissSheets() }
            Button("Keep it", role: .cancel) {}
        } message: { Text("The weekly mix, your changes and goals made from it go. The race stays in My races.") }
        .onAppear { if let p = entry?.mine.plan { perWeek = p.perWeek; weeks = p.weeks } }
    }

    func header(_ r: Race) -> some View {
        let day = entry?.mine.day
        return VStack(alignment: .leading, spacing: 4) {
            Text(r.name.uppercased()).bruceHeading(22).lineLimit(2).minimumScaleFactor(0.7)
            Text([r.dateText(day: day), r.countdownText(day: day)].joined(separator: " · ")).bruceFont(15).foregroundStyle(Theme.secondary)
        }
    }

    // A race without a plan: what it would look like, and Start.
    @ViewBuilder func preview(_ r: Race) -> some View {
        let day = entry?.day ?? r.date
        if r.isPast(day: entry?.mine.day) || (RaceDay.days(until: day) ?? -1) < 0 {
            Text("Race day has passed.").bruceFont(16).foregroundStyle(Theme.secondary)
        } else if let plan = RacePlan(raceDay: day, type: r.type, sport: r.sport,
                                      settings: RacePlanSettings(startedOn: RaceDay.today(), weeks: weeks, perWeek: perWeek)) {
            Text(Copy.planIntro).bruceFont(16).fixedSize(horizontal: false, vertical: true)
            settingsCard(perWeek: $perWeek, weeks: $weeks, blockWeeks: plan.blockWeeks)
            VStack(alignment: .leading, spacing: 12) {
                Text(plan.status() == .upcoming ? "Starts \(RaceDay.format(plan.firstDay, "EEE d MMM"))" : "\(plan.blockWeeks) weeks to race week")
                    .bruceFont(15, weight: .semibold)
                PlanPhaseStrip(plan: plan, onGradient: false)
                PlanGrid(plan: plan)
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            Text(Copy.planNotCoaching).bruceFont(14).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            LimeButton(title: "Start plan", systemImage: "figure.run") {
                m.startPlan(r, perWeek: perWeek, weeks: weeks)
            }
        }
    }

    func active(_ r: Race, _ e: MyRaceEntry, _ plan: RacePlan) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.headline()).bruceFont(17, weight: .bold)
                    Spacer()
                    if let st = m.planWeekStatus(e, plan) { Text(st.progressText).bruceFont(14).foregroundStyle(Theme.secondary) }
                }
                PlanPhaseStrip(plan: plan, onGradient: false)
                PlanGrid(plan: plan) { w, c in
                    let n = (w.count(c) + 1) % (RacePlanSettings.maxPerCell + 1)
                    m.setPlanCount(key, week: w, category: c, to: n, template: plan.template, perWeek: plan.settings.perWeek)
                }
                Text(Copy.planGridHint).bruceFont(13).foregroundStyle(Theme.secondary)
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            settingsCard(perWeek: Binding(get: { plan.settings.perWeek }, set: { v in m.updatePlan(key) { $0.perWeek = v } }),
                         weeks: Binding(get: { plan.settings.weeks }, set: { v in m.updatePlan(key) { $0.weeks = v } }),
                         blockWeeks: plan.blockWeeks)
            reminders(r, e)
            goalsCard(plan)
            Text(Copy.planNotCoaching).bruceFont(14).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive) { confirmStop = true } label: {
                Text("Stop plan").bruceFont(16, weight: .semibold).frame(maxWidth: .infinity).frame(height: 40)
            }
            .buttonStyle(.glass).foregroundStyle(Theme.red)
        }
    }

    func settingsCard(perWeek: Binding<Int>, weeks: Binding<Int>, blockWeeks: Int) -> some View {
        VStack(spacing: 10) {
            Stepper(value: perWeek, in: RacePlanSettings.perWeekRange) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(perWeek.wrappedValue) classes a week").bruceFont(16, weight: .semibold)
                    Text("In Base, Build and Peak. Race week has fewer.").bruceFont(13).foregroundStyle(Theme.secondary)
                }
            }
            Divider()
            Stepper(value: weeks, in: RacePlanSettings.weeksRange) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(weeks.wrappedValue) week block").bruceFont(16, weight: .semibold)
                    Text(blockWeeks < weeks.wrappedValue ? "\(blockWeeks) weeks left to race day" : "Counted back from race week")
                        .bruceFont(13).foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    func reminders(_ r: Race, _ e: MyRaceEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { e.mine.remindWeek }, set: { m.setRaceReminder(r, week: $0) })) {
                Label(Copy.planRemindWeek, systemImage: "bell").bruceFont(15)
            }
            Toggle(isOn: Binding(get: { e.mine.remindEve }, set: { m.setRaceReminder(r, eve: $0) })) {
                Label(Copy.planRemindEve, systemImage: "moon").bruceFont(15)
            }
            Text(Copy.planRemindHint).bruceFont(13).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    func goalsCard(_ plan: RacePlan) -> some View {
        let on = plan.settings.goals
        let targets = plan.monthTargets(month: Date()).sorted { $0.count > $1.count }.prefix(4)
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { on }, set: { m.setPlanGoals(key, $0) })) {
                Label("Monthly goals from this plan", systemImage: "target").bruceFont(16, weight: .semibold)
            }
            .disabled(targets.isEmpty && !on)
            Text(targets.isEmpty ? Copy.planGoalsNone : targets.map { "\($0.category.short) \($0.count)" }.joined(separator: " · ") + " in \(BruceDate.format(Date(), "MMMM"))")
                .bruceFont(14).foregroundStyle(Theme.secondary)
            Text(Copy.planGoalsHint).bruceFont(13).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if on { Button("Open goals") { m.pushSheet(.goals) }.bruceFont(15, weight: .semibold) }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

// MARK: - This week (My classes › Races)

/// "THIS WEEK · W43   2 of 4": the planned sessions with Done, Booked, Auto-book, or a class to Book.
struct PlanWeekSection: View {
    @Environment(AppModel.self) var m
    let entry: MyRaceEntry
    let plan: RacePlan

    var body: some View {
        if let st = m.planWeekStatus(entry, plan) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("THIS WEEK · \(st.week.label)").bruceHeading(16)
                    Spacer()
                    Text("\(st.done) of \(st.planned)").bruceFont(15, weight: .semibold).monospacedDigit().foregroundStyle(Theme.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                let pause = m.raceWeekRules(plan)
                if !pause.isEmpty { pauseCard(pause) }
                if st.slots.isEmpty {
                    Text("Nothing planned this week.").bruceFont(15).foregroundStyle(Theme.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(st.slots) { s in
                            PlanSlotRow(slot: s)
                            if s.id != st.slots.last?.id { Divider().padding(.leading, 62) }
                        }
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                }
                if !st.extra.isEmpty {
                    Text("Also this week: " + st.extra.map(\.title).joined(separator: ", ")).bruceFont(13).foregroundStyle(Theme.secondary)
                }
                Text("Hold Book to book a class every week. " + Copy.planNotCoaching).bruceFont(13).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .task { await m.loadPlanWeekClasses() }
        }
    }

    func pauseCard(_ rules: [AutoBookRule]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Copy.planRaceWeekPause, systemImage: "flag.checkered").bruceFont(15, weight: .semibold).fixedSize(horizontal: false, vertical: true)
            ForEach(rules) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.title).bruceFont(15, weight: .semibold)
                        Text("\(r.label) · \(m.studioName(r.studioId))").bruceFont(13).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button { m.pauseForRaceWeek(r, key: entry.mine.key) } label: {
                        Text("Pause").bruceFont(15, weight: .semibold).padding(.horizontal, 12).frame(height: 32)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(Theme.lime.opacity(0.12)), in: .rect(cornerRadius: 24))
    }
}

struct PlanSlotRow: View {
    @Environment(AppModel.self) var m
    let slot: PlanSlot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: slot.category.symbol).bruceFont(15, weight: .semibold)
                .foregroundStyle(slot.state == .done ? Color.black : Theme.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(slot.state == .done ? Theme.lime : Theme.chipGrey))
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.category.title).bruceFont(16, weight: .semibold).lineLimit(1)
                Text(detail).bruceFont(14).foregroundStyle(Theme.secondary).lineLimit(2)
                if slot.suggestion?.strike == true {
                    Label(Copy.planStrike, systemImage: "exclamationmark.triangle").bruceFont(13, weight: .medium).foregroundStyle(Theme.hoursOrange)
                }
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { if let id = slot.item?.classId ?? slot.suggestion?.c.id, m.findClass(id) != nil || m.classDetails[id] != nil { m.push(.classDetail(id)) } }
        .accessibilityElement(children: .combine)
    }

    var detail: String {
        if let i = slot.item {
            let when = i.kind == .done ? BruceDate.format(i.start, "EEE d MMM") : BruceDate.format(i.start, "EEE d MMM HH:mm")
            return ([when] + [i.studioId.map { m.studioName($0) }].compactMap { $0 }).joined(separator: " · ")
        }
        if let s = slot.suggestion {
            var parts = [BruceDate.format(s.c.start, "EEE d MMM HH:mm"), m.studioName(s.c.studioId)]
            if let n = s.fewSpots { parts.append(n == 1 ? "1 spot left" : "\(n) spots left") }
            if let o = s.opens { parts.append("opens \(BruceDate.format(o, "EEE HH:mm"))") }
            return parts.joined(separator: " · ")
        }
        return Copy.planNothingNear
    }

    @ViewBuilder var trailing: some View {
        switch slot.state {
        case .done:
            Label("Done", systemImage: "checkmark").labelStyle(.titleAndIcon).bruceFont(14, weight: .semibold).foregroundStyle(Theme.limeInk)
        case .booked:
            Text("Booked").bruceFont(14, weight: .semibold).foregroundStyle(Theme.secondary)
        case .autoBook:
            Label("Auto-book", systemImage: "arrow.triangle.2.circlepath").labelStyle(.titleAndIcon).bruceFont(14, weight: .semibold)
                .foregroundStyle(Theme.secondary)
        case .suggested:
            if let s = slot.suggestion {
                if s.opens != nil {
                    Button { Task { await m.setWatchOpening(true, for: s.c) } } label: {
                        Text(m.isWatchingOpening(s.c.id) ? "Waiting" : "When it opens").bruceFont(14, weight: .bold).padding(.horizontal, 10).frame(height: 32)
                    }
                    .buttonStyle(.glass)
                    .disabled(m.isWatchingOpening(s.c.id))
                } else {
                    Menu {
                        Button("Book this class", systemImage: "checkmark.circle") { m.bookPlanned(s) }
                        Button("Book every week", systemImage: "arrow.triangle.2.circlepath") { m.setAutoBook(true, for: s.c) }
                    } label: {
                        Text("Book").bruceFont(15, weight: .bold).foregroundStyle(.black).padding(.horizontal, 14).frame(height: 32)
                            .background(Capsule().fill(Theme.lime))
                    } primaryAction: { m.bookPlanned(s) }
                    .accessibilityHint("Hold for Book every week")
                }
            }
        case .open:
            Button { m.showPlanCategory(slot.category) } label: {
                Text("Find").bruceFont(14, weight: .semibold).padding(.horizontal, 12).frame(height: 32)
            }
            .buttonStyle(.glass)
        }
    }
}

/// My classes › Races, without a plan: the offer under the next race.
struct TrainForItPrompt: View {
    @Environment(AppModel.self) var m
    let entry: MyRaceEntry
    var body: some View {
        Button { m.present(.racePlan(entry.mine.key)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.run").bruceFont(17, weight: .semibold).foregroundStyle(.black)
                    .frame(width: 36, height: 36).background(Circle().fill(Theme.lime))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.planTrainForIt).bruceFont(16, weight: .semibold)
                    Text("A weekly class mix up to race day, booked when you tap").bruceFont(13).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            .foregroundStyle(Theme.ink)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// Home's Next race card: where the block stands and the next class to book.
struct PlanHomeLine: View {
    @Environment(AppModel.self) var m
    let entry: MyRaceEntry
    let plan: RacePlan
    var body: some View {
        let st = m.planWeekStatus(entry, plan)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.headline()).bruceFont(14, weight: .bold)
                Spacer(minLength: 6)
                if let st { Text(st.progressText).bruceFont(14, weight: .semibold).monospacedDigit() }
            }
            if let st, st.planned > 0 {
                HStack(spacing: 4) {
                    ForEach(st.slots) { s in
                        Capsule().fill(s.state == .done ? Theme.lime : .white.opacity(s.state == .booked || s.state == .autoBook ? 0.7 : 0.28)).frame(height: 6)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Under Home's Next race card: the next planned class to book.
struct PlanNextClassRow: View {
    @Environment(AppModel.self) var m
    let suggestion: PlanSuggestion
    var body: some View {
        let s = suggestion
        HStack(spacing: 12) {
            Image(systemName: s.category.symbol).bruceFont(15, weight: .semibold)
                .frame(width: 36, height: 36).background(Circle().fill(Theme.chipGrey))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(s.category.title) · \(BruceDate.format(s.c.start, "EEE HH:mm"))").bruceFont(16, weight: .semibold).lineLimit(1)
                Text(([m.studioName(s.c.studioId)] + [s.fewSpots.map { $0 == 1 ? "1 spot left" : "\($0) spots left" }].compactMap { $0 }).joined(separator: " · "))
                    .bruceFont(14).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            Spacer(minLength: 6)
            Button { m.bookPlanned(s) } label: {
                Text("Book").bruceFont(15, weight: .bold).foregroundStyle(.black).padding(.horizontal, 16).frame(height: 34)
                    .background(Capsule().fill(Theme.lime))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture { m.push(.classDetail(s.c.id)) }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
