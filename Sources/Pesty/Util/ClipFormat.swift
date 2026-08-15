import AppKit

/// Re-copying a clip in a different format.
///
/// Every format derives from one NSAttributedString, so the source is picked
/// once and each case is a small transform on it. Web apps put their best
/// fidelity in `public.html`; the RTF they also offer is a lossy WebKit
/// conversion that flattens lists and code blocks. So HTML wins when present.
///
/// Verified against real AppKit output by `scripts/format_probe.swift`.
@MainActor
enum ClipFormat: String, CaseIterable {
    /// Text with every attribute dropped.
    case plainText
    /// Keeps bold, italic and links. Drops the colors and the source font —
    /// this is what stops a dark-themed copy pasting a black block into Gmail.
    case cleanFormatting
    /// Markdown, for chat apps and anything that speaks it.
    case markdown

    var label: String {
        switch self {
        case .plainText:       return "Plain Text"
        case .cleanFormatting: return "Clean Formatting"
        case .markdown:        return "Markdown"
        }
    }

    /// Only text-shaped clips carry attributes worth converting.
    static func canConvert(_ item: ClipItem) -> Bool {
        switch item.type {
        case .text, .richText, .link: return item.text?.isEmpty == false
        case .image, .file, .color:   return false
        }
    }

    /// The converted clip keeps the original `id` on purpose: it is a transient
    /// copy that never enters the store, and `ClipboardStore.promote` looks the
    /// original up by id after a paste.
    static func convert(_ item: ClipItem, to format: ClipFormat) -> ClipItem {
        var out = item
        out.rtfData = nil
        out.htmlData = nil
        let source = attributed(for: item)

        switch format {
        case .plainText:
            out.type = .text
            out.text = source?.string ?? item.text

        case .cleanFormatting:
            guard let source else {
                // Nothing was styled to begin with, so plain text is already clean.
                out.type = .text
                return out
            }
            let clean = strippingStyles(source)
            out.type = .richText
            out.text = clean.string
            out.rtfData = clean.rtf(from: NSRange(location: 0, length: clean.length),
                                    documentAttributes: [:])

        case .markdown:
            out.type = .text
            out.text = source.map(markdown) ?? item.text
        }
        return out
    }

    private static func attributed(for item: ClipItem) -> NSAttributedString? {
        if let html = item.htmlData,
           let a = NSAttributedString(
               html: html,
               options: [.characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil) {
            return a
        }
        if let rtf = item.rtfData {
            return NSAttributedString(rtf: rtf, documentAttributes: nil)
        }
        return nil
    }

    /// Drops presentation, keeps meaning. Colors and the source font family go;
    /// bold, italic and links stay. The receiving app then renders it in its own
    /// typeface, which is the whole point.
    private static func strippingStyles(_ a: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: a)
        let full = NSRange(location: 0, length: m.length)
        m.beginEditing()
        for key: NSAttributedString.Key in [.backgroundColor, .foregroundColor,
                                            .underlineColor, .strikethroughColor,
                                            .strokeColor, .shadow] {
            m.removeAttribute(key, range: full)
        }
        let size = NSFont.systemFontSize
        let base = NSFont.systemFont(ofSize: size)
        m.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var keep: NSFontDescriptor.SymbolicTraits = []
            if traits.contains(.bold) { keep.insert(.bold) }
            if traits.contains(.italic) { keep.insert(.italic) }
            let descriptor = keep.isEmpty
                ? base.fontDescriptor
                : base.fontDescriptor.withSymbolicTraits(keep)
            m.addAttribute(.font, value: NSFont(descriptor: descriptor, size: size) ?? base,
                           range: range)
        }
        m.endEditing()
        return m
    }

    /// The markup that survives a round trip into Markdown.
    private struct Style: Equatable {
        var bold = false
        var italic = false
        var mono = false
        var link: String?

        init(_ attrs: [NSAttributedString.Key: Any]) {
            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            bold = traits.contains(.bold)
            italic = traits.contains(.italic)
            mono = traits.contains(.monoSpace)
            if let url = attrs[.link] as? URL {
                link = url.absoluteString
            } else if let s = attrs[.link] as? String {
                link = s
            }
        }
    }

    /// AppKit parses Markdown but never writes it, so this walk is the floor.
    ///
    /// ponytail: handles bold, italic, code spans, fenced code, links and flat
    /// bullet lists — the shapes web copies actually use. Headings, nested lists
    /// and tables come out as plain paragraphs. Add them when a clip needs them.
    private static func markdown(_ a: NSAttributedString) -> String {
        let ns = a.string as NSString
        guard ns.length > 0 else { return "" }

        var lines: [(text: String, code: Bool)] = []
        var i = 0
        while i < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: i, length: 0))
            // A zero-length paragraph range would spin here forever.
            i = max(NSMaxRange(para), i + 1)

            // Ranges split on every attribute change, colors included, so one
            // styled phrase arrives in pieces. Merging equal neighbours first
            // stops the output reading `**a** **b**` where `**a b**` is meant.
            var runs: [(text: String, style: Style)] = []
            a.enumerateAttributes(in: para, options: []) { attrs, range, _ in
                let text = ns.substring(with: range)
                let style = Style(attrs)
                if runs.last?.style == style {
                    runs[runs.count - 1].text += text
                } else {
                    runs.append((text, style))
                }
            }

            let isList = (a.attribute(.paragraphStyle, at: para.location,
                                      effectiveRange: nil) as? NSParagraphStyle)?
                            .textLists.isEmpty == false

            // AppKit materializes the list marker into the text as "\t•\t" — note
            // the *leading* tab — and merging puts it inside the first run, so an
            // <li> opening with <b> carries the bullet inside the bold run. Strip
            // it here, before any markup is applied: stripping afterwards eats the
            // opening "**" with it. Scan to the last tab, not the first, or the
            // bullet survives.
            //
            // ponytail: bounded scan, so a tab inside real content survives.
            // Numbered lists lose their number and become dashes.
            if isList, let first = runs.first?.text,
               let tab = first.prefix(8).lastIndex(of: "\t") {
                runs[0].text = String(first[first.index(after: tab)...])
                runs.removeAll { $0.text.isEmpty }
            }

            // A wholly monospaced paragraph is a code block, not a run of code
            // spans. Fencing it keeps indentation and avoids backtick soup.
            let isCode = !runs.isEmpty && runs.allSatisfy {
                $0.style.link == nil && ($0.style.mono || $0.text.allSatisfy(\.isWhitespace))
            }
            var text = isCode
                ? runs.map(\.text).joined().trimmingCharacters(in: .newlines)
                : runs.map { emit($0.text, $0.style) }.joined()
                      .trimmingCharacters(in: .whitespacesAndNewlines)

            if !isCode, isList, !text.isEmpty { text = "- " + text }
            lines.append((text, isCode && !text.isEmpty))
        }

        // HTML leaves runs of empty paragraphs behind; collapse them to one.
        var kept: [(text: String, code: Bool)] = []
        for line in lines where !(line.text.isEmpty && kept.last?.text.isEmpty != false) {
            kept.append(line)
        }
        while kept.last?.text.isEmpty == true { kept.removeLast() }

        var out: [String] = []
        var fenced = false
        for line in kept {
            if line.code != fenced { out.append("```"); fenced = line.code }
            out.append(line.text)
        }
        if fenced { out.append("```") }
        return out.joined(separator: "\n")
    }

    private static func emit(_ raw: String, _ style: Style) -> String {
        // The markers must hug the words. "** bold **" is not bold anywhere.
        let lead = String(raw.prefix { $0.isWhitespace })
        let trail = String(raw.reversed().prefix { $0.isWhitespace }.reversed())
        var t = String(raw.dropFirst(lead.count).dropLast(trail.count))
        guard !t.isEmpty else { return raw }

        if style.mono { t = "`\(t)`" }
        if style.bold { t = "**\(t)**" }
        if style.italic { t = "*\(t)*" }
        if let link = style.link { t = "[\(t)](\(link))" }
        return lead + t + trail
    }
}
