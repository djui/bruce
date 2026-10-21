import SwiftUI

// Train for it on the Mac (RacePlanner.swift), simpler than on iPhone: the plan sheet (phase strip, the weeks ×
// categories grid, sessions per week, start and stop, race-day reminders), the week line and "This week" in My classes
// › Races, and the week line and next class on Home. Monthly goals are iPhone-only, as Goals are.

extension RacePlan {
    var currentWeek: PlanWeek? { if case .active(let w) = status() { return w } else { return nil } }
}

/// One bar per week of the block; past weeks full, this week lime, the phase names under.
struct PlanPhaseStrip: View {
    let plan: RacePlan
    var onGradient = true
    var body: some View {
        let current = plan.currentWeek
        let block = plan.weeks.filter { $0.phase != .recovery }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(block) { w in
                    Capsule().fill(fill(w, current)).frame(height: 7)
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(plan.segments.enumerated()), id: \.offset) { _, seg in
                    Text(seg.phase.short).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(Double(seg.weeks))
                }
            }
            HStack { Text(block.first?.label ?? ""); Spacer(); Text(block.last?.label ?? "") }
                .font(.system(size: 11)).opacity(0.7)
        }
    }
    func fill(_ w: PlanWeek, _ current: PlanWeek?) -> Color {
        if w.id == current?.id { return Theme.lime }
        let past = current.map { w.index < $0.index } ?? (plan.status() == .done)
        if onGradient { return .white.opacity(past ? 0.85 : 0.3) }
        return past ? Theme.ink.opacity(0.55) : Theme.chipGrey
    }
}

/// Weeks × categories: sessions per week, this week outlined; a click steps a number (this week and later).
struct PlanGrid: View {
    let plan: RacePlan
    var onTap: ((PlanWeek, PlanCategory) -> Void)? = nil
    var body: some View {
        let rows = plan.rows.filter { c in plan.weeks.contains { $0.count(c) > 0 } }
        let current = plan.currentWeek
        let today = RaceDay.today()
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(" ").font(.system(size: 11)).frame(height: 18)
                ForEach(rows) { c in Text(c.short).font(.system(size: 13)).lineLimit(1).frame(height: 28, alignment: .leading) }
                Text("Total").font(.system(size: 13, weight: .bold)).frame(height: 26, alignment: .leading)
            }
            .frame(width: 66, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(plan.weeks) { w in
                        let past = w.sunday < today
                        VStack(spacing: 0) {
                            Text(w.label).font(.system(size: 11, weight: w.id == current?.id ? .bold : .regular)).foregroundStyle(Theme.secondary).frame(height: 18)
                            ForEach(rows) { c in
                                let n = w.count(c)
                                Button { onTap?(w, c) } label: {
                                    Text(n == 0 ? "–" : "\(n)").font(.system(size: 13, weight: n > 0 ? .semibold : .regular)).monospacedDigit()
                                        .foregroundStyle(n == 0 ? Theme.tertiary : Color.black)
                                        .frame(width: 26, height: 24)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(n == 0 ? Color.clear : Theme.lime.opacity(0.35 + 0.2 * Double(min(n, 3)))))
                                        .overlay(alignment: .topTrailing) { if w.edited.contains(c) { Circle().fill(Theme.ink).frame(width: 4, height: 4).padding(2) } }
                                }
                                .buttonStyle(.plain).disabled(past || onTap == nil)
                                .frame(height: 28)
                            }
                            Text("\(w.total)").font(.system(size: 13, weight: .bold)).frame(height: 26)
                        }
                        .frame(width: 30)
                        .opacity(past ? 0.55 : 1)
                        .background { if w.id == current?.id { RoundedRectangle(cornerRadius: 8).stroke(Theme.ink, lineWidth: 1.5) } }
                        .help("\(w.label) · \(w.phase.title)")
                    }
                }
            }
        }
    }
}

struct RacePlanSheet: View {
    @Environment(AppModel.self) var m
    let key: String
    @State private var perWeek = RacePlanSettings.defaultPerWeek
    @State private var weeks = RacePlanSettings.defaultWeeks

    var entry: MyRaceEntry? { m.myRaceEntries.first { $0.mine.key == key } }
    var race: Race? { entry?.race ?? m.race(key) }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Copy.planTrainForIt, leading: .close, action: { m.dismissSheets() })
            ScrollView {
                if let r = race {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(r.name).font(.system(size: 20, weight: .bold))
                        Text([r.dateText(day: entry?.mine.day), r.countdownText(day: entry?.mine.day)].joined(separator: " · "))
                            .font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary)
                        if let e = entry, let plan = m.racePlan(for: e) { active(r, e, plan) } else { preview(r) }
                    }
                    .padding(Theme.gutter)
                }
            }
        }
        .onAppear { if let p = entry?.mine.plan { perWeek = p.perWeek; weeks = p.weeks } }
    }

    @ViewBuilder func preview(_ r: Race) -> some View {
        let day = entry?.day ?? r.date
        if (RaceDay.days(until: day) ?? -1) < 0 {
            Text("Race day has passed.").foregroundStyle(Theme.secondary)
        } else if let plan = RacePlan(raceDay: day, type: r.type, sport: r.sport, settings: RacePlanSettings(startedOn: RaceDay.today(), weeks: weeks, perWeek: perWeek)) {
            Text(Copy.planIntro).font(.system(size: 15, weight: .light)).fixedSize(horizontal: false, vertical: true)
            steppers(perWeek: $perWeek, weeks: $weeks)
            PlanPhaseStrip(plan: plan, onGradient: false)
            PlanGrid(plan: plan)
            Text(Copy.planNotCoaching).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            LimeButton(title: "Start plan") { m.startPlan(r, perWeek: perWeek, weeks: weeks) }
        }
    }

    func active(_ r: Race, _ e: MyRaceEntry, _ plan: RacePlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(plan.headline()).font(.system(size: 16, weight: .bold))
                Spacer()
                if let st = m.planWeekStatus(e, plan) { Text(st.progressText).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary) }
            }
            PlanPhaseStrip(plan: plan, onGradient: false)
            PlanGrid(plan: plan) { w, c in
                m.setPlanCount(key, week: w, category: c, to: (w.count(c) + 1) % (RacePlanSettings.maxPerCell + 1), template: plan.template, perWeek: plan.settings.perWeek)
            }
            Text(Copy.planGridHint).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary)
            steppers(perWeek: Binding(get: { plan.settings.perWeek }, set: { v in m.updatePlan(key) { $0.perWeek = v } }),
                     weeks: Binding(get: { plan.settings.weeks }, set: { v in m.updatePlan(key) { $0.weeks = v } }))
            Toggle(Copy.planRemindWeek, isOn: Binding(get: { e.mine.remindWeek }, set: { m.setRaceReminder(r, week: $0) })).toggleStyle(.switch).tint(Theme.lime)
            Toggle(Copy.planRemindEve, isOn: Binding(get: { e.mine.remindEve }, set: { m.setRaceReminder(r, eve: $0) })).toggleStyle(.switch).tint(Theme.lime)
            if let p = e.mine.plan {
                Toggle("\(Copy.planAutoTaper) · \(Copy.planAutoTaperHint)", isOn: Binding(get: { p.autoTaper }, set: { m.setPlanTaper(key, $0) })).toggleStyle(.switch).tint(Theme.lime)
            }
            Text(Copy.planNotCoaching).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Stop plan") { m.stopPlan(key); m.dismissSheets() }.foregroundStyle(.red).buttonStyle(.plain).font(.system(size: 15, weight: .semibold))
        }
    }

    func steppers(perWeek: Binding<Int>, weeks: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("\(perWeek.wrappedValue) classes a week (Base, Build, Peak)", value: perWeek, in: RacePlanSettings.perWeekRange)
            Stepper("\(weeks.wrappedValue) week block, counted back from race week", value: weeks, in: RacePlanSettings.weeksRange)
        }
        .font(.system(size: 14))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sectionGrey))
    }
}

/// "This week · W43  2 of 4" under My classes › Races.
struct PlanWeekList: View {
    @Environment(AppModel.self) var m
    let entry: MyRaceEntry
    let plan: RacePlan
    var body: some View {
        if let st = m.planWeekStatus(entry, plan) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("This week · \(st.week.label)").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Text("\(st.done) of \(st.planned)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
                ForEach(m.raceWeekRules(plan)) { r in
                    HStack {
                        Text("Race week: \(r.title), \(r.label)").font(.system(size: 14))
                        Spacer()
                        Button("Pause") { m.pauseForRaceWeek(r, key: entry.mine.key) }
                    }
                }
                ForEach(st.slots) { s in row(s) }
                Text(Copy.planNotCoaching).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .task { await m.loadPlanWeekClasses() }
        }
    }

    func row(_ s: PlanSlot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.category.symbol).frame(width: 28, height: 28)
                .background(Circle().fill(s.state == .done ? Theme.lime : Theme.chipGrey))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.category.title).font(.system(size: 15, weight: .semibold))
                Text(detail(s)).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary).lineLimit(1)
                if s.suggestion?.strike == true { Text(Copy.planStrike).font(.system(size: 12)).foregroundStyle(Theme.waitlistOrange) }
            }
            Spacer()
            switch s.state {
            case .done: Text("Done").font(.system(size: 13, weight: .semibold))
            case .booked: Text("Booked").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
            case .autoBook: Text("Auto-book").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
            case .suggested:
                if let sug = s.suggestion {
                    Menu("Book") {
                        Button("Book this class") { m.bookPlanned(sug) }
                        Button("Book every week") { m.setAutoBook(true, for: sug.c) }
                    }
                    .fixedSize()
                }
            case .open: Button("Find") { m.showPlanCategory(s.category) }
            }
        }
        .padding(.vertical, 4)
    }

    func detail(_ s: PlanSlot) -> String {
        if let i = s.item {
            return ([BruceDate.format(i.start, i.kind == .done ? "EEE d MMM" : "EEE d MMM HH:mm")] + [i.studioId.map { m.studioName($0) }].compactMap { $0 }).joined(separator: " · ")
        }
        if let g = s.suggestion {
            return ([BruceDate.format(g.c.start, "EEE HH:mm"), m.studioName(g.c.studioId)] + [g.fewSpots.map { "\($0) spots left" }].compactMap { $0 }).joined(separator: " · ")
        }
        return Copy.planNothingNear
    }
}
