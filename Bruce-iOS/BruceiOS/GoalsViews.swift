import SwiftUI

// MARK: - Monthly goals (Goals.swift): the month's ring, one card per goal, and the visit calendar

enum GoalStyle {
    /// Goal accents by `GoalCategory.tone`: lime, swim blue, yoga lilac, orange.
    static let tones: [Color] = [Theme.lime, Color(red: 0.35, green: 0.78, blue: 0.98), Color(red: 0.78, green: 0.71, blue: 0.95), Theme.waitlistOrange]
    static func color(_ tone: Int) -> Color { tones[min(max(tone, 0), tones.count - 1)] }
}

extension AppModel {
    func goalTone(_ g: MonthlyGoal) -> Int { GoalCategory.tone(g.category, categoryTitle: categoryTitle(forKey: g.category)) }
    func goalSymbol(_ key: String?) -> String { GoalCategory.symbol(key, categoryTitle: categoryTitle(forKey: key)) }
}

struct GoalsView: View {
    @Environment(AppModel.self) var m
    /// Opened from Statistics (inside the sheet) rather than the My classes tab.
    var inSheet = false

    var body: some View {
        let month = m.goalsMonth()
        let title = "\(BruceDate.format(Date(), "MMMM")) goals"
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !inSheet { PageHeading(text: title) }
                if m.goals.isEmpty {
                    emptyCard
                } else {
                    summary(month)
                    ForEach(month.progress) { p in
                        Button { edit(p.goal.id) } label: { GoalCard(p: p, daysLeft: month.daysLeft) }.buttonStyle(.plain)
                    }
                }
                Text("THIS MONTH").bruceHeading(18).padding(.top, 14)
                GoalsCalendar(days: Goals.calendar(goals: m.goals, visits: m.visitHistory ?? [], categoryTitle: { m.categoryTitle(forKey: $0) },
                                                   mainCategory: { m.mainCategory(ofStudio: $0) }),
                              blanks: Goals.leadingBlanks())
                Text("Counts classes and drop-in visits you checked in to. Goals are saved on this iPhone.")
                    .bruceFont(13).foregroundStyle(Theme.secondary).padding(.top, 4)
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 30).padding(.top, 4)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .modifier(GoalsChrome(inSheet: inSheet, title: title))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { edit(nil) } label: { Image(systemName: "plus") }.accessibilityLabel("New goal")
            }
        }
        .task { await m.fetchVisitHistory() }
        .refreshable { await m.fetchVisitHistory(force: true) }
    }

    func edit(_ id: UUID?) {
        if inSheet || !m.sheets.isEmpty { m.pushSheet(.editGoal(id)) } else { m.present(.editGoal(id)) }
    }

    func summary(_ month: GoalsMonth) -> some View {
        let streak = Goals.streakWeeks(m.visitHistory ?? [])
        return HStack(spacing: 18) {
            GoalRing(done: month.done, target: month.target)
            VStack(alignment: .leading, spacing: 4) {
                Text(month.status).bruceFont(19, weight: .heavy)
                Text(month.hint).bruceFont(14).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if streak >= 2 {
                    Label("\(streak) weeks in a row", systemImage: "flame.fill").bruceFont(12.5, weight: .semibold).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.lime, in: .capsule).padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.sectionGrey, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    var emptyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "target").bruceFont(30).foregroundStyle(Theme.limeInk)
            Text("Set a monthly goal").bruceFont(19, weight: .heavy)
            Text("For example 20 gym visits and 2 swims. Progress counts your checked-in visits this month.")
                .bruceFont(14).foregroundStyle(Theme.secondary)
            LimeButton(title: "New goal") { edit(nil) }.padding(.top, 4)
        }
        .padding(16)
        .background(Theme.sectionGrey, in: .rect(cornerRadius: 24))
    }
}

/// Wide title in a tab, standard chrome in a sheet.
private struct GoalsChrome: ViewModifier {
    let inSheet: Bool
    let title: String
    func body(content: Content) -> some View {
        if inSheet { content.sheetChrome(title) } else { content.pushedPage(title) }
    }
}

struct GoalRing: View {
    let done: Int
    let target: Int
    var size: CGFloat = 132
    var line: CGFloat = 14
    var body: some View {
        let f = target > 0 ? min(1, Double(done) / Double(target)) : 0
        ZStack {
            Circle().stroke(Color(.systemFill), lineWidth: line)
            Circle().trim(from: 0, to: f).stroke(Theme.lime, style: StrokeStyle(lineWidth: line, lineCap: .round)).rotationEffect(.degrees(-90))
            if size > 80 {
                VStack(spacing: 0) {
                    Text("\(done)").font(.system(size: size * 0.23, weight: .black).width(.expanded)).monospacedDigit()
                    Text("of \(target)").bruceFont(14).foregroundStyle(Theme.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement().accessibilityLabel("\(done) of \(target) visits")
    }
}

struct GoalCard: View {
    @Environment(AppModel.self) var m
    let p: GoalProgress
    let daysLeft: Int
    var body: some View {
        let tone = GoalStyle.color(m.goalTone(p.goal))
        let pace = min(1, p.expected / Double(max(1, p.goal.target)))
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: m.goalSymbol(p.goal.category)).bruceFont(16, weight: .semibold).foregroundStyle(.black)
                    .frame(width: 36, height: 36).background(tone, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.goal.title).bruceFont(16, weight: .bold)
                    if let s = p.goal.studioName { Text("Only at \(s)").bruceFont(13).foregroundStyle(Theme.secondary) }
                }
                Spacer()
                if p.goal.remind { Image(systemName: "bell.fill").bruceFont(12).foregroundStyle(Theme.secondary) }
                Text("\(p.done) / \(p.goal.target)").bruceFont(17, weight: .bold).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill))
                    Capsule().fill(tone).frame(width: g.size.width * p.fraction)
                    Rectangle().fill(Theme.ink.opacity(0.5)).frame(width: 2, height: 16).offset(x: g.size.width * pace - 1)
                }
            }
            .frame(height: 10)
            HStack {
                Text(leftMeta)
                Spacer()
                Text(rightMeta)
            }
            .bruceFont(13).foregroundStyle(p.behind ? Theme.waitlistOrange : Theme.secondary)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.sectionGrey, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit goal")
    }

    /// Small goals show the last visit, bigger ones the pace.
    var leftMeta: String {
        if p.goal.target <= 4, !p.isDone, let v = p.lastVisit {
            return "Last: \(m.studioName(for: v)), \(BruceDate.format(v.date, "d MMM"))"
        }
        return p.paceText
    }
    var rightMeta: String {
        if p.isDone { return p.done > p.goal.target ? "\(p.done - p.goal.target) extra" : "Goal reached" }
        return p.goal.target >= 8 ? "\(p.toGo) to go · \(daysLeft) days left" : "\(p.toGo) to go"
    }
}

struct GoalsCalendar: View {
    let days: [GoalCalendarDay]
    let blanks: Int
    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        LazyVGrid(columns: cols, spacing: 6) {
            // Ids must not clash with the day numbers (1...31) or the blanks (negative) in the same grid.
            ForEach(Array(100..<107), id: \.self) { i in
                Text(["M", "T", "W", "T", "F", "S", "S"][i - 100]).bruceFont(11, weight: .semibold).foregroundStyle(Theme.tertiary)
            }
            ForEach(Array(-blanks..<0), id: \.self) { _ in Color.clear.frame(height: 1) }
            ForEach(days) { d in
                let fill: Color = d.tone.map { GoalStyle.color($0) } ?? Color(.tertiarySystemFill)
                RoundedRectangle(cornerRadius: 9).fill(fill.opacity(d.isFuture ? 0.5 : 1))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(d.isToday ? Theme.ink : .clear, lineWidth: 2))
                    .overlay(Text("\(d.day)").bruceFont(11, weight: .semibold)
                        .foregroundStyle(d.tone != nil ? Color.black : d.isToday ? Theme.ink : Theme.secondary))
                    .accessibilityLabel("\(d.day): \(d.tone == nil ? "no visit" : "visit")")
            }
        }
    }
}

/// My classes: this month's goals at a glance.
struct GoalsCompactCard: View {
    @Environment(AppModel.self) var m
    var body: some View {
        let month = m.goalsMonth()
        NavigationLink(value: Route.goals) {
            HStack(spacing: 14) {
                if m.goals.isEmpty {
                    Image(systemName: "target").bruceFont(20, weight: .semibold).foregroundStyle(.black)
                        .frame(width: 44, height: 44).background(Theme.lime, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set a monthly goal").bruceFont(16, weight: .bold)
                        Text("Gym visits, swims, yoga… counted from your check-ins").bruceFont(13).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                } else {
                    GoalRing(done: month.done, target: month.target, size: 44, line: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(BruceDate.format(Date(), "MMMM")) goals").bruceFont(16, weight: .bold)
                        Text("\(month.done) of \(month.target) · \(month.status) · \(month.daysLeft) days left").bruceFont(13).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").bruceFont(14, weight: .semibold).foregroundStyle(Theme.tertiary)
            }
            .foregroundStyle(Theme.ink)
            .padding(12)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.gutter).padding(.top, 10)
        .task { await m.fetchVisitHistory() }
    }
}

// MARK: - New goal / edit goal

struct GoalEditor: View {
    @Environment(AppModel.self) var m
    @Environment(\.dismiss) var dismiss
    @Environment(\.sheetIsRoot) var isRoot
    let goalId: UUID?
    /// "any" = any visit (nil key).
    @State private var key = "gym"
    @State private var target = 12
    @State private var studioId: Int?
    @State private var remind = false
    @State private var loaded = false

    var categoryKey: String? { key == "any" ? nil : key }
    var existing: MonthlyGoal? { goalId.flatMap { id in m.goals.first { $0.id == id } } }

    /// Gym, the user's own categories (by history), a few common ones, any class, any visit.
    var chipKeys: [String] {
        var counts: [Int: Int] = [:]
        for v in (m.visitHistory ?? []).prefix(400) {
            if v.isSolo { if let c = v.studioRef.flatMap(m.mainCategory(ofStudio:)), c != 1 { counts[c, default: 0] += 1 } }
            else { for c in Set(v.categoryIds) { counts[c, default: 0] += 1 } }
        }
        var ids = counts.sorted { $0.value > $1.value }.map(\.key).filter { id in m.categories.contains { $0.id == id } }.prefix(4).map { $0 }
        for d in [27, 2, 22] where ids.count < 4 && !ids.contains(d) && m.categories.contains(where: { $0.id == d }) { ids.append(d) }
        var keys = ["gym"] + ids.map(String.init) + ["newStudios", "anyClass", "any"]
        if !keys.contains(key) { keys.insert(key, at: keys.count - 2) }
        return keys
    }

    var studioChoices: [(Int, String)] {
        var counts: [Int: Int] = [:]
        for v in (m.visitHistory ?? []).prefix(400) { if let s = v.studioRef { counts[s, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, m.studioName($0.key)) }
    }

    var body: some View {
        let suggestions = Goals.suggestions(visits: m.visitHistory ?? [], existing: m.goals.filter { $0.id != goalId }, mainCategory: { m.mainCategory(ofStudio: $0) })
        Form {
            Section("What counts") {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(chipKeys, id: \.self) { k in
                        GlassChip(selected: key == k, action: { key = k }) {
                            if ["any", "anyClass"].contains(k) { Text(k == "any" ? "Any visit" : "Any class") }
                            else { Label(chipTitle(k), systemImage: m.goalSymbol(k)).labelStyle(.titleAndIcon) }
                        }
                    }
                    Menu {
                        ForEach(m.sortedCategories) { c in Button(c.title ?? "") { key = String(c.id) } }
                    } label: {
                        Text("More…").bruceFont(15, weight: .semibold).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14).frame(height: 36).glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            Section {
                HStack {
                    Text("Times per month")
                    Spacer()
                    HStack(spacing: 0) {
                        Button { target = max(1, target - 1) } label: { Image(systemName: "minus").frame(width: 40, height: 34) }
                        Text("\(target)").bruceFont(17, weight: .bold).monospacedDigit().frame(minWidth: 34)
                            .contentTransition(.numericText()).animation(.snappy, value: target)
                        Button { target = min(62, target + 1) } label: { Image(systemName: "plus").frame(width: 40, height: 34) }
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.ink)
                    .background(Color(.tertiarySystemFill), in: .capsule)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Times per month").accessibilityValue("\(target)")
                    .accessibilityAdjustableAction { d in target = d == .increment ? min(62, target + 1) : max(1, target - 1) }
                }
                Picker("Only at", selection: $studioId) {
                    Text("Any studio").tag(Int?.none)
                    ForEach(studioChoices, id: \.0) { id, name in Text(name).tag(Int?.some(id)) }
                }
                .pickerStyle(.menu).tint(Theme.secondary)
                Toggle("Reminder when behind", isOn: $remind)
            } header: { Text("Target") } footer: {
                Text("Counts classes and drop-in visits you checked in to. Booked but not checked in does not count."
                     + (remind && !(AutoBookServer.booksForMe && AutoBookServer.isConfigured)
                        ? " Reminders need the auto-book server (Menu › Auto-book); without it there is no reminder." : ""))
            }
            if !suggestions.isEmpty && goalId == nil {
                Section("Suggested from your last 3 months") {
                    ForEach(suggestions) { s in
                        HStack(spacing: 12) {
                            Image(systemName: m.goalSymbol(s.key)).bruceFont(14, weight: .semibold).foregroundStyle(.black)
                                .frame(width: 30, height: 30)
                                .background(GoalStyle.color(GoalCategory.tone(s.key, categoryTitle: m.categoryTitle(forKey: s.key))), in: .rect(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(s.target) \(m.goalTitle(s.key).lowercased())")
                                Text("You averaged \(Int(s.average.rounded()))").bruceFont(14).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Button("Add") {
                                m.saveGoal(MonthlyGoal(category: s.key, title: m.goalTitle(s.key), target: s.target))
                                m.flash("Added \(m.goalTitle(s.key).lowercased())")
                            }
                            .buttonStyle(.glass).tint(Theme.ink)
                        }
                    }
                }
            }
            Section {
                LimeButton(title: goalId == nil ? "Add goal" : "Save goal") { save() }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                if goalId != nil {
                    Button("Delete goal", role: .destructive) { if let id = goalId { m.deleteGoal(id) }; close() }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .tint(Theme.lime)
        .sheetChrome(goalId == nil ? "New goal" : "Edit goal")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: { Image(systemName: "checkmark") }
                    .buttonStyle(.glassProminent).tint(Theme.lime).foregroundStyle(.black).accessibilityLabel("Save")
            }
        }
        .task { await m.fetchVisitHistory() }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let g = existing { key = g.category ?? "any"; target = g.target; studioId = g.studioId; remind = g.remind }
        }
        .onChange(of: key) { _, k in
            // A sensible default target per kind, until the user changes it.
            guard existing == nil else { return }
            if let s = suggestions.first(where: { ($0.key ?? "any") == k }) { target = s.target }
        }
    }

    func chipTitle(_ k: String) -> String {
        k == "gym" ? "Gym" : k == "newStudios" ? "New studios" : m.categoryTitle(forKey: k) ?? "Category"
    }

    func save() {
        var g = existing ?? MonthlyGoal(category: categoryKey, title: "", target: target)
        g.category = categoryKey
        g.title = m.goalTitle(categoryKey)
        g.target = target
        g.studioId = studioId
        g.studioName = studioId.map { m.studioName($0) }
        g.remind = remind
        m.saveGoal(g)
        close()
    }

    func close() { if isRoot { m.dismissSheets() } else { dismiss() } }
}
