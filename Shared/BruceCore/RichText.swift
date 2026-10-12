import SwiftUI
#if canImport(Translation)
import Translation
#endif

// Rich descriptions shared by both apps: Markdown blocks (studio and class descriptions use Markdown such as
// "**Bra att veta**" and "* item" lists), active alerts, and on-device translation.

// MARK: - Markdown

/// One block of a Markdown description. Inline styling (bold, italic, links, code) stays in `text`.
struct MarkdownBlock: Hashable, Identifiable {
    enum Kind: Hashable {
        case paragraph
        case heading(Int)
        case bullet(depth: Int)
        case numbered(Int, depth: Int)
        case quote
        case code
    }
    let id: Int
    let kind: Kind
    let text: AttributedString
    var plain: String { String(text.characters) }
    /// Whole block bold (e.g. a "**Good to know**" line), kept when the text is replaced by a translation.
    var isBold: Bool {
        text.runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
    }

    /// Same block with plain replacement text (a translation); whole-block bold is kept.
    func replacingText(_ s: String) -> MarkdownBlock {
        var t = AttributedString(s)
        if isBold { t.inlinePresentationIntent = .stronglyEmphasized }
        return MarkdownBlock(id: id, kind: kind, text: t)
    }
}

enum Markdown {
    nonisolated(unsafe) private static var cache: [String: [MarkdownBlock]] = [:]
    private static let lock = NSLock()

    /// Parses Markdown into blocks (memoised; descriptions are re-rendered often). Falls back to one plain
    /// paragraph per blank-line separated chunk if the text is not valid Markdown.
    static func blocks(_ source: String) -> [MarkdownBlock] {
        lock.lock(); defer { lock.unlock() }
        if let b = cache[source] { return b }
        let b = parse(source)
        if cache.count > 200 { cache.removeAll(keepingCapacity: true) }
        cache[source] = b
        return b
    }

    private static func parse(_ source: String) -> [MarkdownBlock] {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let attr = try? AttributedString(markdown: hardBreaks(trimmed),
                                               options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible))
        else {
            return trimmed.components(separatedBy: "\n\n").enumerated().map { MarkdownBlock(id: $0.offset, kind: .paragraph, text: AttributedString($0.element)) }
        }
        var out: [MarkdownBlock] = []
        for (intent, range) in attr.runs[\.presentationIntent] {
            var text = AttributedString(attr[range])
            text.presentationIntent = nil
            guard !text.characters.isEmpty else { continue }
            out.append(MarkdownBlock(id: out.count, kind: kind(intent), text: text))
        }
        return out
    }

    /// Keeps single line breaks (Markdown would join them into one line): a non-blank line followed by a
    /// non-blank line gets a trailing hard break. Studio texts often list hours or rules on separate lines.
    static func hardBreaks(_ s: String) -> String {
        let lines = s.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out: [String] = []
        for (i, l) in lines.enumerated() {
            let blank = l.trimmingCharacters(in: .whitespaces).isEmpty
            let nextBlank = i + 1 >= lines.count || lines[i + 1].trimmingCharacters(in: .whitespaces).isEmpty
            out.append(!blank && !nextBlank && !l.hasSuffix("  ") ? l + "  " : l)
        }
        return out.joined(separator: "\n")
    }

    private static func kind(_ intent: PresentationIntent?) -> MarkdownBlock.Kind {
        guard let comps = intent?.components else { return .paragraph }
        // Components run from the innermost block outwards.
        let depth = comps.filter { if case .listItem = $0.kind { return true } else { return false } }.count
        for c in comps {
            switch c.kind {
            case .header(let level): return .heading(level)
            case .codeBlock: return .code
            case .blockQuote: return .quote
            case .listItem(let ordinal):
                // The nearest enclosing list decides between bullets and numbers.
                let list = comps.first { c in
                    switch c.kind { case .orderedList, .unorderedList: return true; default: return false }
                }
                if case .orderedList = list?.kind { return .numbered(ordinal, depth: max(depth - 1, 0)) }
                return .bullet(depth: max(depth - 1, 0))
            default: continue
            }
        }
        return .paragraph
    }
}

/// Renders Markdown blocks: paragraphs, headings, bullet and numbered lists (nested), quotes and code.
struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    var size: CGFloat = 16
    var weight: Font.Weight = .regular
    var lineSpacing: CGFloat = 5
    var spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(blocks) { b in row(b) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder func row(_ b: MarkdownBlock) -> some View {
        switch b.kind {
        case .paragraph:
            text(b)
        case .heading(let level):
            Text(b.text).font(.system(size: size + max(0, CGFloat(4 - level)) * 2, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let depth):
            item("•", depth: depth, b)
        case .numbered(let n, let depth):
            item("\(n).", depth: depth, b)
        case .quote:
            text(b).padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(.secondary.opacity(0.5)).frame(width: 3) }
        case .code:
            Text(b.text).font(.system(size: size - 2, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
        }
    }

    func text(_ b: MarkdownBlock) -> some View {
        Text(b.text).font(.system(size: size, weight: weight)).lineSpacing(lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }

    func item(_ marker: String, depth: Int, _ b: MarkdownBlock) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).font(.system(size: size, weight: .semibold)).frame(minWidth: 12, alignment: .leading)
            text(b)
        }
        .padding(.leading, CGFloat(depth) * 18)
    }
}

// MARK: - Alerts

enum Alerts {
    /// Active studio alerts, by `order`.
    static func active(_ alerts: [BruceAPI.StudioAlert]?, now: Date = Date()) -> [String] {
        (alerts ?? []).filter { $0.isActive(at: now) }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
            .compactMap { $0.message?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Class page: the class's own `alert` (as in the official app); without one, the studio's active alerts.
    static func forClass(_ c: BruceAPI.BruceClass, studio: BruceAPI.Studio?) -> [String] {
        if let a = c.alert?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty { return [a] }
        return active(c.studio?.alerts ?? studio?.alerts)
    }
}

// MARK: - On-device translation

/// Translation with Apple's Translation framework. Translations run on the device with Apple's language models
/// (downloaded by the system on first use); no text is sent to Google or any other online translation service.
enum OnDeviceTranslation {
    static var isAvailable: Bool {
        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, *) { return true }
        #endif
        return false
    }
}

extension View {
    /// Translates `texts` into the device language each time `request` changes to a new non-zero value.
    /// `result` receives the translations in the same order, or nil if translation failed or was cancelled.
    @ViewBuilder
    func onDeviceTranslation(_ texts: [String], request: Int, result: @escaping ([String]?) -> Void) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, *) {
            modifier(TranslationRunner(texts: texts, request: request, result: result))
        } else { self }
        #else
        self
        #endif
    }
}

#if canImport(Translation)
@available(iOS 18.0, macOS 15.0, *)
private struct TranslationRunner: ViewModifier {
    let texts: [String]
    let request: Int
    let result: ([String]?) -> Void
    @State private var config: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(config) { session in
                // Source language detected per text (descriptions can mix languages), target = the user's
                // preferred language. A text that cannot be translated (e.g. already in that language) stays as is.
                var out = texts
                var translatedAny = false
                for (i, t) in texts.enumerated() where !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        out[i] = try await session.translate(t).targetText
                        translatedAny = true
                    } catch {
                        if Task.isCancelled { break }
                    }
                }
                result(translatedAny ? out : nil)
            }
            .onChange(of: request) { _, new in
                guard new > 0 else { return }
                if config == nil { config = TranslationSession.Configuration() } else { config?.invalidate() }
            }
    }
}
#endif

// MARK: - Description with alerts and a Translate button

/// A Markdown description followed by alerts in red (as in the official app), with an on-device
/// "Translate" toggle that translates both. Styling is passed in by each app.
struct RichDescription: View {
    let description: String?
    var alerts: [String] = []
    var size: CGFloat = 16
    var weight: Font.Weight = .regular
    var lineSpacing: CGFloat = 5
    var alertColor: Color = .red
    var buttonColor: Color = .secondary

    @State private var translated: [String]?
    @State private var showTranslation = false
    @State private var translating = false
    @State private var failed = false
    @State private var request = 0

    var blocks: [MarkdownBlock] { Markdown.blocks(description ?? "") }
    var sources: [String] { blocks.map(\.plain) + alerts }
    var isEmpty: Bool { blocks.isEmpty && alerts.isEmpty }

    var shownBlocks: [MarkdownBlock] {
        guard showTranslation, let t = translated, t.count == sources.count else { return blocks }
        return blocks.enumerated().map { $0.element.replacingText(t[$0.offset]) }
    }
    var shownAlerts: [String] {
        guard showTranslation, let t = translated, t.count == sources.count else { return alerts }
        return Array(t.suffix(alerts.count))
    }

    var body: some View {
        if !isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                if !blocks.isEmpty {
                    MarkdownBlocksView(blocks: shownBlocks, size: size, weight: weight, lineSpacing: lineSpacing)
                }
                ForEach(Array(shownAlerts.enumerated()), id: \.offset) { _, a in
                    Text(a).font(.system(size: size, weight: weight)).foregroundStyle(alertColor)
                        .lineSpacing(lineSpacing).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if OnDeviceTranslation.isAvailable { translateRow }
            }
            .onDeviceTranslation(sources, request: request) { r in
                translating = false
                if let r { translated = r; showTranslation = true; failed = false } else { failed = true }
            }
            .onChange(of: sources) { _, _ in translated = nil; showTranslation = false; failed = false }
        }
    }

    var translateRow: some View {
        HStack(spacing: 8) {
            if failed {
                Text("Translation not available").font(.system(size: size - 3)).foregroundStyle(buttonColor)
            } else if showTranslation {
                Text("Translated on this device").font(.system(size: size - 3)).foregroundStyle(buttonColor)
            }
            Spacer(minLength: 0)
            Button {
                if translated != nil { showTranslation.toggle() } else if !translating { translating = true; failed = false; request += 1 }
            } label: {
                HStack(spacing: 6) {
                    if translating { ProgressView().controlSize(.small) } else { Image(systemName: "translate") }
                    Text(showTranslation ? "Show original" : translating ? "Translating…" : "Translate")
                }
                .font(.system(size: size - 2, weight: .medium)).foregroundStyle(buttonColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Translates the description on this device")
        }
    }
}
