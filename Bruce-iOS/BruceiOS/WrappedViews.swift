import Combine
import SwiftUI

// MARK: - Brüce Wrapped: the year so far as full-screen animated story cards (numbers from Wrapped.swift)
//
// Tap right/left to step, hold to pause, swipe down or X to close; each story card advances after ~6 s. Each card has
// its own bold gradient, numbers count up, month bars grow in and confetti falls on the big moments. The last card is
// the share card, exported as a 1080×1920 image with `ImageRenderer`. Reduce Motion: no confetti, no count-ups, no
// drifting backgrounds.

private enum W {
    static let neon = Color(hex: 0xDAFC55)
    static let pink = Color(hex: 0xFF3D8B)
    static let cyan = Color(hex: 0x3AE0FF)
    static let violet = Color(hex: 0xB18CFF)
    static let amber = Color(hex: 0xFFB800)
    static let personaInk = Color(hex: 0x1A0010)
    static let confetti: [Color] = [pink, neon, violet, .white, cyan, amber]
    /// Seconds per story card.
    static let duration: Double = 6

    /// The wide black display face of the app: Unbounded Black (`Theme.display`).
    static func display(_ size: CGFloat) -> Font { Theme.display(size, weight: .black) }
    /// A display size at which the longest word of `text` fits `width` on one line (wide black caps are up to ~0.95 em).
    static func fit(_ text: String, max: CGFloat, width: CGFloat) -> CGFloat {
        let longest = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(\.count).max() ?? 1
        return min(max, width / (CGFloat(longest) * 0.96))
    }
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: - Story player

struct WrappedView: View {
    @Environment(AppModel.self) var m
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stats: WrappedStats?
    @State private var index = 0
    @State private var elapsed: Double = 0
    @State private var holding = false
    @State private var pressStart: Date?
    @State private var dragY: CGFloat = 0
    private let ticker = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    private var cards: [WrappedStats.Card] { stats?.cards ?? [] }
    private var card: WrappedStats.Card? { cards.indices.contains(index) ? cards[index] : nil }
    /// Story cards in the progress bar (the share card has its own header).
    private var storyCount: Int { cards.filter { $0 != .share }.count }

    var body: some View {
        ZStack {
            Color.black
            if let stats, let card {
                WrappedCardView(card: card, stats: stats)
                    .id(index)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.06)),
                                                                      removal: .opacity.combined(with: .scale(scale: 0.97))))
            } else {
                WrappedLoading()
            }
            tapLayer
            chrome
        }
        .clipShape(RoundedRectangle(cornerRadius: dragY > 0 ? 40 : 0, style: .continuous))
        .offset(y: dragY)
        .scaleEffect(1 - min(dragY, 400) / 4000)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .task {
            let s = await m.loadWrapped()
            withAnimation(.easeOut(duration: 0.3)) {
                stats = s
                // Screenshots: BRUCE_SCREEN=wrappedshare starts at the share card, BRUCE_WRAPPED_CARD=<n> at card n.
                let start = AppModel.demo ? AppModel.setting("BRUCE_WRAPPED_CARD").flatMap(Int.init) ?? m.demoWrappedCard : 0
                if start > 0 { index = min(start, s.cards.count - 1) }
            }
        }
        .onReceive(ticker) { _ in tick() }
        .accessibilityAction(named: "Next card") { step(1) }
        .accessibilityAction(named: "Previous card") { step(-1) }
        .accessibilityAction(.escape) { close() }
    }

    /// Taps, hold-to-pause and swipe-down, below the buttons.
    private var tapLayer: some View {
        GeometryReader { geo in
            Color.clear.contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if pressStart == nil { pressStart = Date() }
                            holding = true
                            if g.translation.height > 0, abs(g.translation.height) > abs(g.translation.width) { dragY = g.translation.height }
                        }
                        .onEnded { g in
                            let held = Date().timeIntervalSince(pressStart ?? Date())
                            pressStart = nil
                            holding = false
                            if g.translation.height > 120 || g.predictedEndTranslation.height > 320 { close(); return }
                            withAnimation(.spring(duration: 0.3)) { dragY = 0 }
                            guard abs(g.translation.width) < 12, abs(g.translation.height) < 12, held < 0.35 else { return }
                            step(g.location.x < geo.size.width / 3 ? -1 : 1)
                        }
                )
        }
        .accessibilityHidden(true)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                if card == .share {
                    Text("WRAPPED").font(W.display(20)).foregroundStyle(.white)
                    Spacer()
                } else if storyCount > 0 {
                    progressBar.padding(.trailing, 4)
                } else {
                    Spacer()
                }
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(.white.opacity(0.18)))
                }
                .accessibilityLabel("Close Wrapped")
            }
            .padding(.horizontal, card == .share ? 22 : 14)
            .padding(.top, 62)
            Spacer()
            if card == .share, let stats {
                WrappedShareButtons(stats: stats).padding(.bottom, 40)
            } else if index == 0, stats != nil {
                HStack {
                    Text("‹ tap to go back").opacity(0)
                    Spacer()
                    Text("tap for next ›")
                }
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 22).padding(.bottom, 34)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<storyCount, id: \.self) { i in
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: geo.size.width * fill(i))
                        }
                }
                .frame(height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Card \(index + 1) of \(storyCount)")
    }

    private func fill(_ i: Int) -> CGFloat {
        i < index ? 1 : i > index ? 0 : CGFloat(min(1, elapsed / W.duration))
    }

    private func tick() {
        guard stats != nil, card != .share, !holding, !UIAccessibility.isVoiceOverRunning else { return }
        elapsed += 1.0 / 30
        if elapsed >= W.duration { step(1) }
    }

    private func step(_ d: Int) {
        let next = index + d
        guard cards.indices.contains(next) else {
            if d < 0 { elapsed = 0 }
            return
        }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.35)) { index = next }
        elapsed = 0
    }

    private func close() {
        m.wrappedOpen = false
        dismiss()
    }
}

/// While the year loads: the intro gradient and a spinner.
private struct WrappedLoading: View {
    var body: some View {
        ZStack {
            WrappedBackground(card: .intro)
            VStack(spacing: 16) {
                ProgressView().tint(.white).controlSize(.large)
                Text("Wrapping up your year…").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Cards

private struct WrappedCardView: View {
    let card: WrappedStats.Card
    let stats: WrappedStats

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - 48
            ZStack(alignment: .topLeading) {
                WrappedBackground(card: card)
                decorations(geo.size)
                VStack(alignment: .leading, spacing: 0) {
                    content(width: width)
                }
                .padding(.top, 112).padding(.horizontal, 24)
                .frame(width: geo.size.width, alignment: .leading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .foregroundStyle(card == .persona ? W.personaInk : card == .top ? .black : .white)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func decorations(_ size: CGSize) -> some View {
        switch card {
        case .intro:
            Blob(color: W.amber, size: 180).position(x: size.width + 50 - 90, y: 420 + 90)
            Blob(color: W.cyan, size: 120, delay: 2).position(x: -40 + 60, y: 250 + 60)
            Confetti()
        case .place:
            Blob(color: W.cyan, size: 220).position(x: size.width + 80 - 110, y: 120 + 110)
        case .streak:
            Confetti()
        case .top:
            Ripple(delay: 0).position(x: size.width / 2, y: 230 + 120)
            Ripple(delay: 1.2).position(x: size.width / 2, y: 230 + 120)
            Confetti()
        case .share:
            Confetti()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        switch card {
        case .intro: IntroCard(stats: stats, width: width)
        case .visits: VisitsCard(stats: stats)
        case .persona: PersonaCard(stats: stats, width: width)
        case .place: PlaceCard(stats: stats, width: width)
        case .streak: StreakCard(stats: stats)
        case .race: RaceChapterCard(stats: stats, width: width)
        case .top: TopCard(stats: stats)
        case .share:
            WrappedShareCard(stats: stats, animated: true).padding(.horizontal, -2).padding(.top, -6)
        }
    }
}

/// The race chapter (Races.swift): each race of the year with its day and the result the member typed.
private struct RaceChapterCard: View {
    let stats: WrappedStats
    let width: CGFloat
    var body: some View {
        let races = stats.races
        let one = races.count == 1
        Kicker(text: one ? "Race day" : "Your races").pop(0.05)
        if one, let r = races.first {
            let name = r.name.uppercased()
            Text(name).font(W.display(W.fit(name, max: 40, width: width))).lineSpacing(-3).padding(.top, 16).pop(0.2)
            if let t = r.timeText {
                Text(t).font(W.display(72)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).padding(.top, 10).pop(0.4)
            } else {
                Text("\(r.dayText) · \(r.kind)").font(.system(size: 17, weight: .bold)).opacity(0.85).padding(.top, 10).pop(0.4)
            }
            if let p = r.placeText { Text(p).font(.system(size: 17, weight: .bold)).opacity(0.85).padding(.top, 6).pop(0.5) }
        } else {
            Text("\(races.count) RACES").font(W.display(44)).padding(.top, 16).pop(0.2)
            VStack(spacing: 8) {
                ForEach(races.prefix(5), id: \.key) { r in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                            Text(r.placeText ?? r.kind).font(.system(size: 12, weight: .semibold)).opacity(0.8).lineLimit(1)
                        }
                        Spacer()
                        Text(r.timeText ?? r.dayText).font(W.display(22)).monospacedDigit()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.16)))
                }
                if races.count > 5 { Text("+\(races.count - 5) more").font(.system(size: 13, weight: .bold)).opacity(0.8) }
            }
            .padding(.top, 18).pop(0.6)
        }
        Text(races.contains { $0.timeText != nil } ? "Typed by you, from the organiser's results." : "Add your results on the race pages to see your times here.")
            .font(.system(size: 14, weight: .medium)).opacity(0.85).padding(.top, 16).pop(0.9)
    }
}

private struct Kicker: View {
    let text: String
    var color: Color? = nil
    var body: some View {
        Text(text.uppercased()).font(.system(size: 13, weight: .heavy)).tracking(1.8)
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
            .opacity(color == nil ? 0.75 : 1)
    }
}

private struct IntroCard: View {
    let stats: WrappedStats
    let width: CGFloat
    var body: some View {
        let name = stats.firstName.map { "\($0.uppercased()),\n" } ?? ""
        let big = stats.visits > 0 ? "\(name)YOU\nSHOWED\nUP." : "YOUR\nYEAR\nSTARTS\nNOW."
        Kicker(text: "Your \(String(stats.year)) in Brüce").pop(0.1)
        Text(big).font(W.display(W.fit(big, max: 54, width: width))).lineSpacing(-4).padding(.top, 22).pop(0.35)
        Text(stats.visits > 0 ? "January 1 to today. Every class, every drop-in, every early alarm. Ready?"
                              : "No visits yet this year. Book a class and come back for your story.")
            .font(.system(size: 17, weight: .medium)).lineSpacing(5).opacity(0.9).padding(.top, 22).pop(0.7)
    }
}

private struct VisitsCard: View {
    let stats: WrappedStats
    var body: some View {
        Kicker(text: "So far this year", color: W.neon).pop(0.05)
        CountUp(value: stats.visits, delay: 0.3)
            .font(W.display(stats.visits >= 1000 ? 84 : 104)).foregroundStyle(W.neon)
            .shadow(color: W.neon.opacity(0.45), radius: 20).padding(.top, 10)
        Text(stats.visits == 1 ? "VISIT" : "VISITS").font(W.display(34)).pop(0.2)
        Text(copy).font(.system(size: 17, weight: .medium)).lineSpacing(5).opacity(0.85).padding(.top, 12).pop(0.5)
        MonthBars(stats: stats).padding(.top, 18)
        if let b = stats.bestMonth {
            Text("\(Text(Wrapped.monthNames[b]).bold().foregroundColor(W.neon)) was your month: \(stats.months[b]) visit\(stats.months[b] == 1 ? "" : "s").")
                .font(.system(size: 15, weight: .medium)).padding(.top, 12).pop(1.4)
        }
    }
    private var copy: String {
        var lines = ["\(stats.classes) class\(stats.classes == 1 ? "" : "es") + \(stats.dropins) gym drop-in\(stats.dropins == 1 ? "" : "s")."]
        var second = "\(stats.hours) hour\(stats.hours == 1 ? "" : "s")."
        if let e = stats.every, stats.visits > 1 {
            second += e <= 1 ? " More than one visit a day." : " One visit every \(e == e.rounded() ? String(Int(e)) : String(format: "%.1f", e)) days."
        }
        lines.append(second)
        return lines.joined(separator: "\n")
    }
}

/// Twelve month bars that grow in one after the other; the best month glows, future months are dashed.
private struct MonthBars: View {
    let stats: WrappedStats
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    var body: some View {
        let top = max(stats.months.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<12, id: \.self) { i in
                VStack(spacing: 5) {
                    Spacer(minLength: 0)
                    if i > stats.monthNow {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .frame(height: 40)
                    } else {
                        let best = i == stats.bestMonth
                        RoundedRectangle(cornerRadius: 5)
                            .fill(best ? W.neon : .white.opacity(0.25))
                            .shadow(color: best ? W.neon.opacity(0.7) : .clear, radius: 9)
                            .frame(height: max(3, 96 * CGFloat(stats.months[i]) / CGFloat(top)))
                            .scaleEffect(x: 1, y: grown ? 1 : 0, anchor: .bottom)
                            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55).delay(0.5 + Double(i) * 0.07), value: grown)
                    }
                    Text(String(Wrapped.monthNames[i].prefix(1))).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 120)
        .onAppear { grown = true }
        .accessibilityElement()
        .accessibilityLabel((0...stats.monthNow).map { "\(Wrapped.monthNames[$0]) \(stats.months[$0])" }.joined(separator: ", "))
    }
}

private struct PersonaCard: View {
    let stats: WrappedStats
    let width: CGFloat
    var body: some View {
        let title = stats.persona.title.uppercased().replacingOccurrences(of: " ", with: "\n")
        Kicker(text: "Your class personality").pop(0.05)
        PersonaArt(persona: stats.persona).frame(maxWidth: .infinity).pop(0.2)
        Text(title).font(W.display(W.fit(title, max: 50, width: width))).lineSpacing(-4).padding(.top, 10).pop(0.45)
        Text(stats.persona.blurb).font(.system(size: 17, weight: .medium)).lineSpacing(5).padding(.top, 14).pop(0.75)
        if let t = stats.topHourLabel {
            Label("Top time of day: \(t)", systemImage: "clock")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: 0xFFF3B0))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(W.personaInk))
                .padding(.top, 16).pop(1)
        }
    }
}

/// The persona's emblem: a rising sun with turning rays for the Early Bird, the persona's symbol in a glowing disc
/// for the others.
private struct PersonaArt: View {
    let persona: WrappedPersona
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = size.width / 2
                for k in 0..<12 {
                    let a0 = Angle.degrees(Double(k) * 30), a1 = Angle.degrees(Double(k) * 30 + 6)
                    var p = Path()
                    p.addArc(center: c, radius: r * 0.99, startAngle: a0, endAngle: a1, clockwise: false)
                    p.addArc(center: c, radius: r * 0.75, startAngle: a1, endAngle: a0, clockwise: true)
                    p.closeSubpath()
                    ctx.fill(p, with: .color(.white.opacity(0.75)))
                }
            }
            .rotationEffect(.degrees(on && !reduceMotion ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 9).repeatForever(autoreverses: false), value: on)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFF7C2), Color(hex: 0xFFD400), Color(hex: 0xFF9500)], center: .center, startRadius: 0, endRadius: 50))
                .frame(width: 90, height: 90)
                .shadow(color: Color(hex: 0xFFD400), radius: 30)
                .overlay {
                    if persona.kind != .earlyBird {
                        Image(systemName: persona.symbol).font(.system(size: 38, weight: .bold)).foregroundStyle(W.personaInk)
                    }
                }
                .scaleEffect(reduceMotion ? 1 : (on ? 1.06 : 0.94))
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: on)
        }
        .frame(width: 150, height: 150)
        .padding(.top, 6)
        .onAppear { on = true }
        .accessibilityHidden(true)
    }
}

private struct PlaceCard: View {
    let stats: WrappedStats
    let width: CGFloat
    var body: some View {
        if let s = stats.topStudio {
            let name = s.name.uppercased()
            Kicker(text: "Your second living room").pop(0.05)
            Text(name).font(W.display(W.fit(name, max: 40, width: width))).lineSpacing(-3).padding(.top, 16).pop(0.25)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                CountUp(value: s.count, delay: 0.3).font(W.display(80))
                Text(s.count == 1 ? "VISIT" : "VISITS").font(W.display(24))
            }
            .padding(.top, 14)
            HStack(spacing: 10) {
                if let c = stats.topClass { tile("\(c.count)×", "\(c.title), top class") }
                tile("\(stats.studios)", stats.studios == 1 ? "studio tried" : "studios tried")
            }
            .padding(.top, 20).pop(0.9)
        }
    }
    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(W.display(26)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 13, weight: .bold)).opacity(0.8).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.16)))
    }
}

private struct StreakCard: View {
    let stats: WrappedStats
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        VStack(spacing: 0) {
            if stats.streak.weeks >= 2 {
                Kicker(text: "Longest streak").pop(0.05)
                Image(systemName: "flame.fill").font(.system(size: 96)).foregroundStyle(Color(hex: 0xFFD400))
                    .shadow(color: Color(hex: 0xFF9500), radius: 18)
                    .scaleEffect(x: on ? 1.06 : 1, y: on ? 1.12 : 1, anchor: .bottom)
                    .rotationEffect(.degrees(on ? 2 : -2), anchor: .bottom)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: on)
                    .frame(height: 120).pop(0.15)
                Text("\(stats.streak.weeks) WEEKS").font(W.display(stats.streak.weeks >= 10 ? 50 : 58)).lineLimit(1).minimumScaleFactor(0.5).pop(0.35)
                HStack(spacing: 6) {
                    let n = stats.streak.weeks
                    ForEach(1...min(n, 8), id: \.self) { i in
                        Text(i == 8 && n > 8 ? "+\(n - 7)" : "\(i)")
                            .font(.system(size: 12, weight: .black)).foregroundStyle(Color(hex: 0xFF0066))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.95)))
                    }
                }
                .padding(.top, 14).padding(.bottom, 6).pop(0.55)
                Text("in a row, \(stats.streakRange)").font(.system(size: 14, weight: .bold)).opacity(0.85).pop(0.6)
            }
            if let f = stats.friend {
                HStack(spacing: -14) {
                    face(String(stats.firstName?.prefix(1) ?? "Y").uppercased(), W.neon, delay: 0)
                    face(f.initials, W.cyan, delay: 0.6)
                }
                .padding(.top, stats.streak.weeks >= 2 ? 18 : 40).padding(.bottom, 10).pop(1)
                Text("You and \(f.name) did \(Text("\(f.count)").font(W.display(22))) \(f.count == 1 ? "class" : "classes") together.")
                    .font(.system(size: 17, weight: .bold)).multilineTextAlignment(.center).pop(1.2)
                Text("Same time next year?").font(.system(size: 17, weight: .medium)).opacity(0.8).pop(1.2)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .onAppear { on = true }
    }
    private func face(_ text: String, _ color: Color, delay: Double) -> some View {
        Text(text).font(.system(size: 24, weight: .black)).foregroundStyle(.black)
            .frame(width: 64, height: 64)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .modifier(Bump(delay: delay))
    }
}

private struct TopCard: View {
    let stats: WrappedStats
    var body: some View {
        let p = stats.percentiles
        Kicker(text: "You vs. Brüce").pop(0.05)
        if let v = p?.visits {
            HStack(alignment: .top, spacing: 0) {
                Text("TOP ").font(W.display(40)).padding(.top, 22).pop(0.15)
                CountUp(value: WrappedPercentiles.top(v), delay: 0.3).font(W.display(WrappedPercentiles.top(v) >= 10 ? 120 : 140))
                Text("%").font(W.display(56)).pop(0.3)
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.top, 30)
            Text("of Brüce users by visits this year.").font(.system(size: 17, weight: .bold)).padding(.top, 8).pop(0.5)
        }
        VStack(spacing: 8) {
            if let x = p?.minutes { chip("Minutes trained", x, 0.8) }
            if let x = p?.studios { chip("Studios tried", x, 0.95) }
            if let x = p?.streak, stats.streak.weeks > 0 { chip("Longest streak", x, 1.1) }
        }
        .padding(.top, 22)
        Text("Anonymous: compared with \(p?.cohort.map(String.init) ?? "other") Brüce users, only percentiles leave the server.")
            .font(.system(size: 12, weight: .semibold)).opacity(0.65).padding(.top, 12).pop(1.3)
    }
    private func chip(_ label: String, _ pct: Int, _ delay: Double) -> some View {
        HStack {
            Text(label).font(.system(size: 15, weight: .bold))
            Spacer()
            Text("Top \(WrappedPercentiles.top(pct))%").font(W.display(15))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.12)))
        .pop(delay)
    }
}

// MARK: - Share card

/// The share card: on screen it shimmers and its stats pop in; exported it is the still frame.
struct WrappedShareCard: View {
    let stats: WrappedStats
    var animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    private var moving: Bool { animated && !reduceMotion }

    private func tile(_ t: (value: String, label: String), _ k: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.value).font(W.display(28)).lineLimit(1).minimumScaleFactor(0.5)
            Text(t.label).font(.system(size: 13, weight: .semibold)).opacity(0.7).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(moving && !on ? 0.4 : 1, anchor: .leading)
        .opacity(moving && !on ? 0 : 1)
        .animation(moving ? .spring(response: 0.45, dampingFraction: 0.5).delay(0.2 + Double(k) * 0.12) : nil, value: on)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("BRÜCE\n\(String(stats.year))").font(W.display(36)).lineSpacing(-4)
                Spacer()
                Image(systemName: "sparkle").font(.system(size: 34, weight: .bold))
                    .rotationEffect(.degrees(moving && on ? 360 : 0))
                    .animation(moving ? .linear(duration: 6).repeatForever(autoreverses: false) : nil, value: on)
            }
            Text([stats.firstName, "so far this year"].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 15, weight: .bold)).opacity(0.7).padding(.top, 6).padding(.bottom, 4)
            Label(stats.persona.title, systemImage: "sparkle")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(W.neon)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.black))
                .padding(.bottom, 16)
            let tiles = stats.shareTiles
            // A plain Grid, not a lazy one: ImageRenderer does not draw lazy containers.
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 16) {
                ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { row in
                    GridRow {
                        ForEach(row..<min(row + 2, tiles.count), id: \.self) { k in tile(tiles[k], k) }
                    }
                }
            }
            HStack {
                if let v = stats.percentiles?.visits { Text("Top \(WrappedPercentiles.top(v))% of Brüce users") }
                Spacer()
                if let t = stats.topHourLabel { Text("Top time \(t)") }
            }
            .font(.system(size: 13, weight: .heavy))
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.15)).frame(height: 2) }
            .padding(.top, 18)
        }
        .foregroundStyle(.black)
        .padding(22)
        .background {
            GeometryReader { geo in
                LinearGradient.css(135, [(W.neon, 0), (W.cyan, 0.55), (W.violet, 1)])
                    .frame(width: geo.size.width * 2, height: geo.size.height * 2)
                    .offset(x: moving && on ? -geo.size.width : 0, y: moving && on ? -geo.size.height : 0)
                    .animation(moving ? .easeInOut(duration: 5).repeatForever(autoreverses: true) : nil, value: on)
                if moving {
                    LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .white.opacity(0.55), location: 0.5), .init(color: .clear, location: 0.6)],
                                   startPoint: .leading, endPoint: .trailing)
                        .rotationEffect(.degrees(15))
                        .frame(width: geo.size.width * 1.8, height: geo.size.height * 1.8)
                        .offset(x: on ? geo.size.width * 0.5 : -geo.size.width * 1.3, y: -geo.size.height * 0.4)
                        .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: false), value: on)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 2))
        .shadow(color: W.neon.opacity(animated ? 0.25 : 0), radius: 30, y: 20)
        .onAppear { on = true }
        .accessibilityElement(children: .combine)
    }
}

/// The exported 1080×1920 image (360×640 points at 3×): the share card on the share screen's dark glow.
private struct WrappedShareImage: View {
    let stats: WrappedStats
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x1D2B0A), .black], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 520)
            VStack(spacing: 0) {
                Text("WRAPPED").font(W.display(20)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26).padding(.bottom, 22)
                WrappedShareCard(stats: stats, animated: false).padding(.horizontal, 22)
                Text("brüce").font(W.display(16)).foregroundStyle(W.neon).padding(.top, 28)
            }
        }
        .frame(width: 360, height: 640)
        .environment(\.colorScheme, .dark)
    }
}

private struct WrappedShareButtons: View {
    let stats: WrappedStats
    @Environment(AppModel.self) var m
    @State private var image: Image?
    @State private var uiImage: UIImage?
    /// Saving to Photos needs `NSPhotoLibraryAddUsageDescription`; without it the share sheet (which also offers
    /// "Save Image") is the only way out.
    private var canSave: Bool { Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") != nil }

    var body: some View {
        VStack(spacing: 10) {
            if let image {
                ShareLink(item: image, subject: Text("My Brüce \(String(stats.year))"),
                          message: Text("My \(String(stats.year)) in Brüce: \(stats.visits) visits."),
                          preview: SharePreview("My Brüce \(String(stats.year))", image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(WrappedPillStyle())
                if canSave, let uiImage {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                        m.flash("Saved to Photos")
                    } label: { Text("Save image").frame(maxWidth: .infinity) }
                    .buttonStyle(WrappedPillStyle(ghost: true))
                }
            } else {
                ProgressView().tint(.white).frame(height: 50)
            }
        }
        .padding(.horizontal, 16)
        .task(id: stats) { render() }
    }

    @MainActor private func render() {
        let r = ImageRenderer(content: WrappedShareImage(stats: stats))
        r.scale = 3
        r.proposedSize = ProposedViewSize(width: 360, height: 640)
        if let ui = r.uiImage {
            #if DEBUG
            // Demo screenshots: the exported image, to check it (Library/Caches/wrapped-share.png in the app container).
            if AppModel.demo, let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                try? ui.pngData()?.write(to: dir.appendingPathComponent("wrapped-share.png"))
            }
            #endif
            uiImage = ui
            image = Image(uiImage: ui)
        }
    }
}

private struct WrappedPillStyle: ButtonStyle {
    var ghost = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(ghost ? .white : .black)
            .frame(height: 50)
            .background(Capsule().fill(ghost ? AnyShapeStyle(.white.opacity(0.14)) : AnyShapeStyle(Theme.lime)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - Backgrounds and effects

extension LinearGradient {
    /// A CSS `linear-gradient(<deg>, ...)`: 0° points up, angles turn clockwise.
    fileprivate static func css(_ deg: Double, _ stops: [(Color, Double)]) -> LinearGradient {
        let r = deg * .pi / 180
        let dx = sin(r) / 2, dy = -cos(r) / 2
        return LinearGradient(stops: stops.map { Gradient.Stop(color: $0.0, location: $0.1) },
                              startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

/// Each card's gradient (the mockup's `.g-*` backgrounds); intro, persona, streak and top drift slowly.
private struct WrappedBackground: View {
    let card: WrappedStats.Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            let drifts = [.intro, .persona, .streak, .top].contains(card) && !reduceMotion
            layers(s)
                .frame(width: drifts ? s.width * 1.6 : s.width, height: drifts ? s.height * 1.6 : s.height)
                .offset(x: drifts && drift ? -s.width * 0.6 : 0, y: drifts && drift ? -s.height * 0.6 : 0)
                .animation(drifts ? .easeInOut(duration: 7).repeatForever(autoreverses: true) : nil, value: drift)
        }
        .clipped()
        .onAppear { drift = true }
    }

    @ViewBuilder
    private func layers(_ s: CGSize) -> some View {
        let far = hypot(s.width, s.height) * 1.6
        switch card {
        case .intro:
            ZStack {
                LinearGradient.css(160, [(Color(hex: 0x3B0CFF), 0), (Color(hex: 0xB10DC9), 0.6), (W.pink, 1)])
                glow(W.pink, at: UnitPoint(x: 0.2, y: 0.15), radius: far * 0.38)
                glow(W.amber, at: UnitPoint(x: 0.85, y: 0.7), radius: far * 0.3)
            }
        case .visits:
            ZStack {
                LinearGradient.css(180, [(Color(hex: 0x0B0B0B), 0), (Color(hex: 0x13240A), 1)])
                glow(W.neon.opacity(0.35), at: UnitPoint(x: 0.8, y: 0.1), radius: far * 0.45 / 1.6)
            }
        case .persona:
            ZStack {
                LinearGradient.css(170, [(Color(hex: 0xFF8A00), 0), (Color(hex: 0xFF3D6E), 0.65), (Color(hex: 0x8A1FFF), 1)])
                glow(Color(hex: 0xFFF3B0), at: UnitPoint(x: 0.5, y: 0.38), radius: far * 0.28)
            }
        case .place:
            LinearGradient.css(160, [(Color(hex: 0x00C2A8), 0), (Color(hex: 0x0066FF), 0.7), (Color(hex: 0x2A0D8F), 1)])
        case .race:
            ZStack {
                LinearGradient.css(160, [(Color(hex: 0x0C2A1E), 0), (Color(hex: 0x0D5C43), 0.6), (Color(hex: 0x1B8F6A), 1)])
                glow(W.neon.opacity(0.45), at: UnitPoint(x: 0.8, y: 0.2), radius: far * 0.3)
            }
        case .streak:
            ZStack {
                LinearGradient.css(170, [(Color(hex: 0xFF3D00), 0), (Color(hex: 0xFF0066), 0.7), (Color(hex: 0x6A00FF), 1)])
                glow(Color(hex: 0xFFD400), at: UnitPoint(x: 0.5, y: 0.3), radius: far * 0.35)
            }
        case .top:
            AngularGradient(colors: [W.neon, W.cyan, W.violet, W.neon], center: UnitPoint(x: 0.5, y: 0.4),
                            startAngle: .degrees(210 - 90), endAngle: .degrees(210 - 90 + 360))
        case .share:
            RadialGradient(colors: [Color(hex: 0x1D2B0A), .black], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: hypot(s.width, s.height) * 0.7)
        }
    }

    private func glow(_ c: Color, at p: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [c, c.opacity(0)], center: p, startRadius: 0, endRadius: radius)
    }
}

/// Falling, spinning confetti drawn with Canvas; nothing under Reduce Motion.
private struct Confetti: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Piece { let x, speed, phase, sway, spin: Double; let color: Color; let shape: Int }
    private static let pieces: [Piece] = {
        var seed: UInt64 = 7
        func r() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
        return (0..<44).map { i in
            Piece(x: r(), speed: 2.3 + r() * 0.9, phase: r() * 3, sway: 12 + r() * 14, spin: 220 + r() * 300,
                  color: W.confetti[i % W.confetti.count], shape: i % 3 == 0 ? 1 : i % 4 == 0 ? 2 : 0)
        }
    }()
    @State private var start = Date()

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSince(start)
                Canvas { ctx, size in
                    for p in Self.pieces {
                        let cycle = (t + p.phase).truncatingRemainder(dividingBy: p.speed) / p.speed
                        let y = -20 + cycle * (size.height + 40)
                        let x = p.x * size.width + sin(cycle * .pi * 2) * p.sway
                        var c = ctx
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .degrees(cycle * p.spin))
                        let rect: CGRect = switch p.shape {
                        case 1: CGRect(x: -5, y: -5, width: 10, height: 10)
                        case 2: CGRect(x: -2.5, y: -8, width: 5, height: 16)
                        default: CGRect(x: -4, y: -7, width: 8, height: 14)
                        }
                        let path = p.shape == 1 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2)
                        c.fill(path, with: .color(p.color))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A soft floating disc behind a card's content.
private struct Blob: View {
    let color: Color
    let size: CGFloat
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Circle().fill(color).frame(width: size, height: size).blur(radius: 2).opacity(0.55)
            .scaleEffect(on ? 1.15 : 1)
            .offset(x: on ? 18 : 0, y: on ? -26 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 6).repeatForever(autoreverses: true).delay(delay), value: on)
            .onAppear { on = true }
            .accessibilityHidden(true)
    }
}

/// A ring that ripples outwards (the percentile card).
private struct Ripple: View {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Circle().strokeBorder(.black.opacity(0.18), lineWidth: 3).frame(width: 240, height: 240)
            .scaleEffect(reduceMotion ? 1 : (on ? 1.5 : 0.5))
            .opacity(reduceMotion ? 1 : (on ? 0 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(delay), value: on)
            .onAppear { on = true }
            .accessibilityHidden(true)
    }
}

/// A number that counts up from 0 (static under Reduce Motion).
private struct CountUp: View {
    let value: Int
    var delay: Double = 0
    var duration: Double = 1.1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        if reduceMotion {
            Text("\(value)").monospacedDigit()
        } else {
            TimelineView(.animation(minimumInterval: nil, paused: Date().timeIntervalSince(start) > delay + duration + 0.1)) { tl in
                let p = min(1, max(0, (tl.date.timeIntervalSince(start) - delay) / duration))
                let eased = 1 - pow(1 - p, 3)
                Text("\(Int((Double(value) * eased).rounded()))").monospacedDigit()
            }
            .accessibilityLabel("\(value)")
        }
    }
}

/// Content that pops in after its card appears: rises, overshoots a little and settles. `delay` is seconds.
private struct Pop: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on || reduceMotion ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 24)
            .scaleEffect(on || reduceMotion ? 1 : 0.9, anchor: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(delay)) { on = true }
            }
    }
}

/// The avatars' gentle hop.
private struct Bump: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .offset(y: on ? -8 : 0)
            .rotationEffect(.degrees(on ? -6 : 0))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay), value: on)
            .onAppear { on = true }
    }
}

private extension View {
    func pop(_ delay: Double) -> some View { modifier(Pop(delay: delay)) }
}

// MARK: - Entry point (Statistics and menu banner)

/// "Brüce Wrapped" banner on the Statistics screen and in the menu; opens the story over the sheet it lives in.
struct WrappedBanner: View {
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles").font(.system(size: 26, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("BRÜCE WRAPPED \(String(BruceDate.calendar.component(.year, from: Date())))").font(W.display(16))
                    Text("Your year so far, as a story").font(.system(size: 14, weight: .semibold)).opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(
                LinearGradient.css(120, [(Color(hex: 0x3B0CFF), 0), (Color(hex: 0xB10DC9), 0.6), (W.pink, 1)]),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Brüce Wrapped: your year so far, as a story")
        .fullScreenCover(isPresented: $open) { WrappedView() }
    }
}
