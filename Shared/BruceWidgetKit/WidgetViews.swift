import SwiftUI
import WidgetKit

// The widget faces (Bruce-iOS/BruceWidgets), kept here so the app can show them in demo mode too. Every surface
// says "Brüce (unofficial)"; nothing here checks anyone in: the Control and the Lock Screen button only open the app.

enum WidgetTheme {
    static let lime = Color(red: 0xCC / 255, green: 0xF0 / 255, blue: 0x3A / 255)
    static let teal = Color(red: 0.16, green: 0.69, blue: 0.60)
    static let orange = Color(red: 0.95, green: 0.6, blue: 0.1)
    static let red = Color(red: 1, green: 0.22, blue: 0.24)
    static let brand = "Brüce (unofficial)"
    static func tint(_ t: WidgetSnapshot.NextClass.Tone) -> Color {
        switch t { case .free: teal; case .warn: orange; case .bad: red; case .checkIn: lime; case .started: .secondary }
    }
}

/// Small "B" mark, drawn (no app icon assets in the extension).
struct WidgetMark: View {
    var size: CGFloat = 22
    var body: some View {
        Text("B").font(.system(size: size * 0.62, weight: .black, design: .rounded)).foregroundStyle(.black)
            .frame(width: size, height: size).background(WidgetTheme.lime, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Next class: systemSmall / systemMedium / accessoryRectangular / accessoryInline.
struct NextClassView: View {
    let snapshot: WidgetSnapshot
    let now: Date
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: home(medium: true)
        default: home(medium: false)
        }
    }

    static let day: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE HH:mm"; return f }()
    static let time: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"; return f }()
    static let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current; return c }()
    func when(_ c: WidgetSnapshot.NextClass) -> String {
        Self.cal.isDate(c.start, inSameDayAs: now) ? "Today \(Self.time.string(from: c.start))" : Self.day.string(from: c.start)
    }

    @ViewBuilder var inline: some View {
        if let c = snapshot.next, now < c.end { Text("\(c.title) · \(when(c))") }
        else if snapshot.loggedIn { Text("No class booked · Brüce") }
        else { Text("Log in to Brüce") }
    }

    var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let c = snapshot.next, now < c.end {
                Text(c.title).font(.headline).lineLimit(1)
                Text("\(when(c)) · \(c.studio)").font(.caption).lineLimit(1)
                Text(c.status(at: now).text).font(.caption2).lineLimit(1)
            } else {
                Text(snapshot.loggedIn ? "No class booked" : "Log in to Brüce").font(.headline)
                Text(WidgetTheme.brand).font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(snapshot.next.map { WidgetSnapshot.classURL($0.classId) } ?? WidgetSnapshot.checkInURL)
    }

    func home(medium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("NEXT CLASS").font(.system(size: 10, weight: .heavy).width(.expanded)).foregroundStyle(.secondary)
                Spacer()
                WidgetMark(size: 18)
            }
            if let c = snapshot.next, now < c.end {
                let s = c.status(at: now)
                Text(c.title).font(.system(size: medium ? 20 : 16, weight: .bold)).lineLimit(medium ? 1 : 2).minimumScaleFactor(0.8)
                Text("\(when(c)) · \(c.studio)").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(medium ? 1 : 2)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Image(systemName: s.tone == .free ? "clock" : s.tone == .checkIn ? "qrcode.viewfinder" : "exclamationmark.triangle.fill").font(.system(size: 10, weight: .semibold))
                    Text(medium ? s.text : s.text.replacingOccurrences(of: "Free cancel until", with: "Free until").replacingOccurrences(of: "Cancel now: ", with: ""))
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(WidgetTheme.tint(s.tone))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(WidgetTheme.tint(s.tone).opacity(0.14), in: Capsule())
            } else {
                Text(snapshot.loggedIn ? "No class booked" : "Log in to see your next class").font(.system(size: 16, weight: .bold))
                Spacer(minLength: 0)
                Text(snapshot.loggedIn ? "Open Brüce to book one." : WidgetTheme.brand).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if medium { Text(WidgetTheme.brand).font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(snapshot.next.map { WidgetSnapshot.classURL($0.classId) } ?? WidgetSnapshot.checkInURL)
    }
}

/// Visits this month: systemSmall ring and the accessoryCircular gauge.
struct VisitsLeftView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    var used: Int { snapshot.visitsUsed ?? 0 }
    var left: Int? { snapshot.visitsTotal.map { max(0, $0 - used) } }
    var fraction: Double { snapshot.visitsTotal.map { $0 > 0 ? Double(used) / Double($0) : 0 } ?? 0 }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: fraction) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(left.map(String.init) ?? "∞").font(.system(size: 15, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetURL(WidgetSnapshot.visitsURL)
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("VISITS LEFT · \(snapshot.month.prefix(3).uppercased())").font(.system(size: 10, weight: .heavy).width(.expanded)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    WidgetMark(size: 18)
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 7)
                        Circle().trim(from: 0, to: snapshot.visitsTotal == nil ? 1 : fraction).stroke(WidgetTheme.lime, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.loggedIn ? (left.map(String.init) ?? "∞") : "–").font(.system(size: 30, weight: .black).width(.expanded)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(snapshot.loggedIn ? (snapshot.visitsTotal.map { "of \($0) this month" } ?? "unlimited this month") : "Log in to Brüce").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text(WidgetTheme.brand).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(WidgetSnapshot.visitsURL)
        }
    }
}

/// Lock Screen button that opens the quick check-in sheet in the app (it never checks anyone in).
struct CheckInButtonView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "qrcode.viewfinder").font(.system(size: 22, weight: .semibold))
                Text("Check in").font(.system(size: 9, weight: .semibold))
            }
        }
        .widgetURL(WidgetSnapshot.checkInURL)
    }
}
