import Foundation
import SwiftUI

// MARK: - Statistics: visits per month and the visit history (iOS and macOS)

extension BruceAPI {
    /// One past booking for the Statistics list. Decoded leniently on its own (not `Booking`): drop-in check-ins
    /// have no class [c8:404], and opening-hour bookings carry a class with `title:null` and `opening:true` [c3:101].
    struct Visit: Decodable, Identifiable, Hashable {
        let id: Int
        let studioId: Int?
        let checkedInAt: String?
        var deleted: Bool? = nil
        var visitClass: VisitClass? = nil
        enum CodingKeys: String, CodingKey {
            case id, deleted
            case studioId = "studio_id", checkedInAt = "checked_in_at", visitClass = "class"
        }

        struct VisitClass: Decodable, Hashable {
            var title: String? = nil
            var opening: Bool? = nil
            var startTime: String? = nil
            var endTime: String? = nil
            var instructor: String? = nil
            var studio: StudioLite? = nil
            enum CodingKeys: String, CodingKey {
                case title, opening, instructor, studio
                case startTime = "start_time", endTime = "end_time"
            }
        }

        var checkedIn: Date? { checkedInAt.flatMap(BruceDate.parse) }
        var classStart: Date? { visitClass?.startTime.flatMap(BruceDate.parse) }
        var classEnd: Date? { visitClass?.endTime.flatMap(BruceDate.parse) }
        /// A gym visit: a drop-in check-in (no class) or an opening-hour slot. The original shows "Solo training".
        var isSolo: Bool { visitClass == nil || visitClass?.opening == true || visitClass?.title == nil }
        /// The original lists solo visits at the check-in time and classes at their start time.
        var date: Date? { isSolo ? (checkedIn ?? classStart) : (classStart ?? checkedIn) }
        /// "Hyrox", or "Solo training 05:00 - 22:00" when the opening slot's hours are known.
        var title: String {
            guard isSolo else { return visitClass?.title ?? "" }
            guard visitClass?.opening == true, let s = classStart, let e = classEnd else { return "Solo training" }
            return "Solo training \(BruceDate.time(s)) - \(BruceDate.time(e))"
        }
        var durationMinutes: Int? {
            guard !isSolo, let s = classStart, let e = classEnd else { return nil }
            return Int(e.timeIntervalSince(s) / 60)
        }
        /// Same `**` stripping as `BruceClass.instructor`.
        var instructor: String? {
            let s = visitClass?.instructor?.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return s?.isEmpty == false ? s : nil
        }
    }

    /// The user's checked-in visits, newest first. The official app's Statistics list call is not captured, so this
    /// pages `GET /v52/booking` without a time window (the shape of [c7:64] / [c8:404] plus `include_class_studio`)
    /// by `next_cursor` and keeps bookings with `checked_in_at`.
    static func fetchVisits(token: String, userId: Int, maxPages: Int = 20) async throws -> [Visit] {
        struct R: Decodable { let bookings: [Visit]; let metadata: Metadata? }
        var all: [Int: Visit] = [:]
        var cursor: String?
        for _ in 0..<maxPages {
            var q: [(String, String)] = [
                ("user_id", String(userId)), ("limit", "30"), ("deleted", "false"),
                ("include_class", "true"), ("include_class_studio", "true"), ("locale", "en"),
            ]
            if let cursor { q.append(("next_cursor", cursor)) }
            let r = try decode(R.self, try await send(makeRequest("GET", "v52/booking", query: q, token: token)))
            let before = all.count
            for v in r.bookings { all[v.id] = v }
            guard let next = r.metadata?.pagination?.nextCursor, !next.isEmpty,
                  !r.bookings.isEmpty, all.count > before else { break }
            cursor = next
        }
        return all.values
            .filter { $0.checkedInAt != nil && $0.deleted != true }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

struct MonthCount: Identifiable, Hashable {
    /// First day of the month, Stockholm time.
    let month: Date
    let count: Int
    var id: Date { month }
}

extension AppModel {
    /// Visits per month from `GET /v52/booking/aggregate`, oldest first, ending with the current month. Months
    /// without visits are included (as 0), and at least the last six months are shown.
    var monthlyVisits: [MonthCount] {
        let cal = BruceDate.calendar
        var counts: [Date: Int] = [:]
        for a in aggregate {
            guard let d = BruceDate.parseDay(String(a.day)), let m = cal.dateInterval(of: .month, for: d)?.start else { continue }
            counts[m, default: 0] += a.count
        }
        guard let now = cal.dateInterval(of: .month, for: Date())?.start,
              let sixAgo = cal.date(byAdding: .month, value: -5, to: now) else { return [] }
        var m = min(counts.keys.min() ?? sixAgo, sixAgo)
        var out: [MonthCount] = []
        while m <= now {
            out.append(MonthCount(month: m, count: counts[m] ?? 0))
            guard let next = cal.date(byAdding: .month, value: 1, to: m) else { break }
            m = next
        }
        return out
    }

    func studioName(for v: BruceAPI.Visit) -> String {
        v.visitClass?.studio?.name ?? v.studioId.flatMap { studio($0)?.name } ?? ""
    }
    /// "Östermalm | Sina Ramezani", as under each row of the original.
    func visitMeta(_ v: BruceAPI.Visit) -> String {
        let area = v.visitClass?.studio?.vicinity ?? v.studioId.flatMap { studio($0)?.vicinity }
        return [area, v.instructor].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " | ")
    }

    /// Visit history for the Statistics screen (not kept on the model: only that screen uses it).
    func fetchVisitHistory() async -> [BruceAPI.Visit] {
        if AppModel.demo { return Self.demoVisits }
        guard !token.isEmpty, let uid = userId else { return [] }
        return (try? await BruceAPI.fetchVisits(token: token, userId: uid)) ?? []
    }

    static var demoVisits: [BruceAPI.Visit] {
        let cal = BruceDate.calendar
        let iso = ISO8601DateFormatter()
        func at(_ day: Int, _ h: Int, _ min: Int) -> String {
            iso.string(from: cal.date(bySettingHour: h, minute: min, second: 0, of: cal.date(byAdding: .day, value: -day, to: Date())!)!)
        }
        let json = """
        [{"id":1,"studio_id":1112,"checked_in_at":"\(at(0, 11, 28))"},
         {"id":2,"studio_id":12388,"checked_in_at":"\(at(0, 16, 34))","class":{"title":"Hyrox","start_time":"\(at(0, 16, 50))","end_time":"\(at(0, 17, 50))",
          "instructor":"Sina Ramezani","studio":{"id":12388,"name":"STC Sturegatan Park","vicinity":"Östermalm"}}},
         {"id":3,"studio_id":1724,"checked_in_at":"\(at(1, 14, 37))","class":{"opening":true,"start_time":"\(at(1, 5, 0))","end_time":"\(at(1, 23, 0))",
          "studio":{"id":1724,"name":"STC Rosenlundsparken","vicinity":"Södermalm"}}},
         {"id":4,"studio_id":1489,"checked_in_at":"\(at(2, 7, 51))"}]
        """
        return ((try? JSONDecoder().decode([BruceAPI.Visit].self, from: Data(json.utf8))) ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

/// The original's monthly bar chart: the count above each bar, the month below, the selected month in full white
/// (primary), the others grey. Scrolls sideways and starts at the current month.
struct VisitBarChart: View {
    let months: [MonthCount]
    @Binding var selection: Date
    var barWidth: CGFloat = 46
    var height: CGFloat = 170

    var body: some View {
        let top = max(months.map(\.count).max() ?? 0, 1)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(months) { mc in
                        let sel = mc.month == selection
                        Button { selection = mc.month } label: {
                            VStack(spacing: 8) {
                                Text("\(mc.count)").font(.system(size: 15)).monospacedDigit()
                                    .foregroundStyle(sel ? .primary : .secondary)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(sel ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                                    .frame(width: barWidth, height: max(2, height * CGFloat(mc.count) / CGFloat(top)))
                                Text(BruceDate.format(mc.month, "MMM"))
                                    .font(.system(size: 15, weight: sel ? .bold : .regular))
                                    .foregroundStyle(sel ? .primary : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(mc.month)
                        .accessibilityLabel("\(BruceDate.format(mc.month, "MMMM yyyy")): \(mc.count) visit\(mc.count == 1 ? "" : "s")")
                        .accessibilityAddTraits(sel ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: height + 64, alignment: .bottom)
            }
            .onAppear { scrollToEnd(proxy) }
            .onChange(of: months.count) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = months.last?.month { proxy.scrollTo(last, anchor: .trailing) }
    }
}
