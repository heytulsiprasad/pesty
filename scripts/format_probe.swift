// Check: does ClipFormat produce what the menu claims it does?
//
// Compiles the real conversion code — nothing here is a reimplementation — and
// asserts against live AppKit output. Run it after touching ClipFormat.swift,
// the RTF and HTML writers move between macOS releases:
//
//     swiftc Sources/Pesty/Models/ClipType.swift \
//               Sources/Pesty/Models/ClipItem.swift \
//               Sources/Pesty/Util/ClipFormat.swift \
//               scripts/format_probe.swift -o /tmp/format_probe && /tmp/format_probe
import AppKit

@main
enum FormatProbe {

    // A font the receiving app did not choose, at a size it did not choose.
    static let body = NSFont(name: "Georgia", size: 19)!
    static let bodyBold = NSFont(name: "Georgia-Bold", size: 19)!
    static let code = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// Stands in for a dark-themed web copy: a background, explicit colors, an
    /// inline code span, a bullet, and a fenced block — with the prose in a
    /// proportional font, the way real content arrives.
    static func sourceClip() -> ClipItem {
        let s = NSMutableAttributedString()

        func add(_ text: String,
                 _ font: NSFont = body,
                 color: NSColor = .white,
                 link: String? = nil,
                 list: Bool = false) {
            var a: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .backgroundColor: NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1),
            ]
            if let link { a[.link] = URL(string: link)! }
            if list {
                let p = NSMutableParagraphStyle()
                p.textLists = [NSTextList(markerFormat: .disc, options: 0)]
                a[.paragraphStyle] = p
            }
            s.append(NSAttributedString(string: text, attributes: a))
        }

        // Two adjacent bold runs differing only in color. Attributed ranges split
        // on the color change, but the markers must not.
        add("Encry", bodyBold)
        add("ption.", bodyBold, color: .red)
        add(" All data in transit uses ")
        add("TLS 1.3", code)
        add(". See ")
        add("the docs", link: "https://example.com/docs")
        add(".\n")
        add("Sign-ons and file uploads\n", list: true)
        add("aws s3 cp ./file s3://bucket\n", code)

        let full = NSRange(location: 0, length: s.length)
        return ClipItem(type: .richText,
                        text: s.string,
                        rtfData: s.rtf(from: full, documentAttributes: [:])!)
    }

    static func html(_ item: ClipItem) -> String {
        let a = NSAttributedString(rtf: item.rtfData!, documentAttributes: nil)!
        let data = try! a.data(from: NSRange(location: 0, length: a.length),
                               documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
        return String(data: data, encoding: .utf8)!
    }

    @MainActor
    static func main() {
        let item = sourceClip()

        // The bug being fixed: the source styling rides along into the paste.
        precondition(html(item).contains("background-color"), "fixture lost its background")

        // --- Clean Formatting ---------------------------------------------
        let clean = ClipFormat.convert(item, to: .cleanFormatting)
        let cleanHTML = html(clean)
        precondition(clean.type == .richText, "clean formatting must stay rich text")
        precondition(clean.htmlData == nil, "clean formatting must not carry the source HTML")
        precondition(!cleanHTML.contains("background-color"), "background survived:\n\(cleanHTML)")
        precondition(!cleanHTML.contains("Georgia"), "source font survived:\n\(cleanHTML)")
        precondition(!cleanHTML.contains("19.0px"), "source font size survived:\n\(cleanHTML)")
        precondition(cleanHTML.contains("<b>"), "bold was lost:\n\(cleanHTML)")
        precondition(cleanHTML.contains("example.com/docs"), "link was lost:\n\(cleanHTML)")
        precondition(clean.text == item.text, "clean formatting changed the characters")
        print("clean formatting: background gone, bold and link kept  ✓")

        // --- Markdown ------------------------------------------------------
        let md = ClipFormat.convert(item, to: .markdown)
        let text = md.text ?? ""
        print("--- markdown ---\n\(text)\n---------------")
        precondition(md.type == .text, "markdown must be plain text")
        precondition(md.rtfData == nil, "markdown must not carry RTF")

        // Adjacent runs that differ only in color must emit one pair of markers.
        precondition(text.contains("**Encryption.**"),
               "runs split by color were not merged: \(text)")
        precondition(!text.contains("**Encry**"), "markers fragmented: \(text)")
        // Prose is not code. Backticks belong only on the monospaced run.
        precondition(text.contains("`TLS 1.3`"), "inline code span missing: \(text)")
        precondition(!text.contains("`All data"), "prose was marked as code: \(text)")
        precondition(text.contains("[the docs](https://example.com/docs)"),
               "link markdown wrong: \(text)")
        // A wholly monospaced paragraph fences instead of turning into spans.
        precondition(text.contains("```\naws s3 cp ./file s3://bucket\n```"),
               "code block was not fenced: \(text)")
        print("markdown: merged runs, code span, fenced block, link  ✓")

        // --- Plain text -----------------------------------------------------
        let plain = ClipFormat.convert(item, to: .plainText)
        precondition(plain.type == .text, "plain text must be plain")
        precondition(plain.rtfData == nil && plain.htmlData == nil, "plain text kept attributes")
        precondition(plain.text == item.text, "plain text changed the characters")
        precondition(plain.id == item.id, "converting must keep the id so promote still works")
        print("plain text: attributes dropped, characters and id kept  ✓")

        // --- The HTML path ---------------------------------------------------
        // What a web app actually puts on the pasteboard. HTML must win over
        // RTF, because the RTF a browser offers has already flattened the list.
        let page = """
        <meta charset="utf-8"><div style="background-color: rgb(23,23,26); \
        color: rgb(250,250,250); font-family: Georgia; font-size: 19px"> \
        <p><b>Encryption.</b> All data uses <code>TLS 1.3</code>. \
        See <a href="https://example.com/docs">the docs</a>.</p> \
        <ul><li><b>Sign-ons</b> — successful and failed attempts</li>\
        <li>File uploads — who uploaded which file</li></ul></div>
        """
        let web = ClipItem(type: .richText,
                           text: "Encryption. All data uses TLS 1.3.",
                           rtfData: item.rtfData,
                           htmlData: Data(page.utf8))

        let webClean = ClipFormat.convert(web, to: .cleanFormatting)
        let webHTML = html(webClean)
        precondition(!webHTML.contains("background-color"), "background survived HTML:\n\(webHTML)")
        precondition(!webHTML.contains("Georgia"), "source font survived HTML:\n\(webHTML)")
        precondition(webHTML.contains("<b>"), "bold lost through HTML:\n\(webHTML)")
        precondition(webHTML.contains("example.com/docs"), "link lost through HTML:\n\(webHTML)")

        let webMD = ClipFormat.convert(web, to: .markdown).text ?? ""
        print("--- markdown from HTML ---\n\(webMD)\n--------------------------")
        precondition(webMD.contains("**Encryption.**"), "bold lost in HTML markdown: \(webMD)")
        precondition(webMD.contains("[the docs](https://example.com/docs)"),
               "link lost in HTML markdown: \(webMD)")
        precondition(webMD.contains("- File uploads — who uploaded which file"),
               "HTML list did not become a bullet: \(webMD)")
        // The marker rides inside the bold run when an <li> opens with <b>.
        // Stripping it must not take the opening "**" along.
        precondition(webMD.contains("- **Sign-ons** — successful and failed attempts"),
               "list marker stripping ate the bold marker: \(webMD)")
        precondition(!webMD.contains("•"), "raw list marker leaked into markdown: \(webMD)")
        // The RTF on the same clip has no list in it, so a bullet here proves
        // the HTML branch ran rather than the RTF fallback.
        print("html path: preferred over RTF, styling dropped, list kept  ✓")

        // --- Menu gating ----------------------------------------------------
        precondition(!ClipFormat.canConvert(ClipItem(type: .image, imageFileName: "x.png")))
        precondition(!ClipFormat.canConvert(ClipItem(type: .text, text: "")))
        precondition(ClipFormat.canConvert(item))
        print("canConvert: text yes, image and empty no  ✓")

        print("\nALL CHECKS PASSED")
    }
}
