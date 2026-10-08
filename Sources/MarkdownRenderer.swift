import AppKit

struct OutlineEntry {
    let level: Int
    let title: String
    let slug: String
    let location: Int        // character index in the rendered text
}

/// Markdown → NSAttributedString, natively. Foundation parses (cmark-gfm underneath); this styles.
/// Uses TextKit 1 text blocks for code backgrounds, quote bars, heading rules and real tables.
final class MarkdownRenderer {
    var zoom: CGFloat = 1
    var baseURL: URL?

    // MARK: palette (adapts to light/dark at draw time)
    static func dyn(_ l: NSColor, _ d: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? d : l }
    }
    static let codeBG   = dyn(NSColor(srgbRed: 0.957, green: 0.957, blue: 0.965, alpha: 1), NSColor(srgbRed: 0.153, green: 0.153, blue: 0.169, alpha: 1))
    static let codeEdge = dyn(NSColor(srgbRed: 0.937, green: 0.937, blue: 0.949, alpha: 1), NSColor(srgbRed: 0.17, green: 0.17, blue: 0.19, alpha: 1))
    static let theadBG  = dyn(NSColor(srgbRed: 0.98, green: 0.98, blue: 0.984, alpha: 1), NSColor(srgbRed: 0.145, green: 0.145, blue: 0.16, alpha: 1))
    static let rule     = dyn(NSColor(srgbRed: 0.902, green: 0.902, blue: 0.918, alpha: 1), NSColor(srgbRed: 0.2, green: 0.2, blue: 0.22, alpha: 1))
    static let quoteBar = dyn(NSColor(srgbRed: 0.85, green: 0.85, blue: 0.87, alpha: 1), NSColor(srgbRed: 0.27, green: 0.27, blue: 0.3, alpha: 1))
    static let accent   = NSColor.controlAccentColor

    // MARK: fonts
    private var body: NSFont { .systemFont(ofSize: 15 * zoom) }
    private var mono: NSFont { .monospacedSystemFont(ofSize: 13 * zoom, weight: .regular) }
    private func heading(_ l: Int) -> NSFont {
        let sizes: [CGFloat] = [28, 22, 18, 16, 14.5, 14]
        return .systemFont(ofSize: sizes[max(0, min(l, 6) - 1)] * zoom, weight: l == 1 ? .bold : .semibold)
    }

    // MARK: state
    private var out = NSMutableAttributedString()
    private var outline: [OutlineEntry] = []
    private var slugCounts: [String: Int] = [:]
    private var seenListItems = Set<Int>()
    private var table: TableBuffer?

    private struct Block {
        enum Kind { case paragraph, header(Int), code(String?), rule, cell(table: Int, row: Int, isHeader: Bool, col: Int, columns: Int) }
        let id: Int
        let kind: Kind
        let comps: [PresentationIntent.IntentType]
        let buffer = NSMutableAttributedString()
    }
    private var block: Block?

    private final class TableBuffer {
        let id: Int, columns: Int
        var rows: [Int: [Int: NSMutableAttributedString]] = [:]   // rowKey → col → text  (header row key = -1)
        init(id: Int, columns: Int) { self.id = id; self.columns = columns }
    }

    // MARK: render

    func render(_ markdown: String) -> (NSAttributedString, [OutlineEntry]) {
        out = NSMutableAttributedString(); outline = []; slugCounts = [:]; seenListItems = []; table = nil; block = nil
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .full
        opts.allowsExtendedAttributes = true
        opts.failurePolicy = .returnPartiallyParsedIfPossible
        guard let parsed = try? AttributedString(markdown: markdown, options: opts) else {
            return (NSAttributedString(string: markdown, attributes: [.font: mono, .foregroundColor: NSColor.labelColor]), [])
        }
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let comps = run.presentationIntent?.components ?? []
            let (kind, id) = blockKind(comps)
            if block?.id != id {
                flushBlock()
                if case .cell = kind {} else { flushTable() }
                block = Block(id: id, kind: kind, comps: comps)
            }
            append(text, run: run)
        }
        flushBlock(); flushTable()
        return (out, outline)
    }

    private func blockKind(_ comps: [PresentationIntent.IntentType]) -> (Block.Kind, Int) {
        var tableID = 0, columns = 1, rowKey = 0, isHeader = false
        for c in comps {
            switch c.kind {
            case .table(let cols): tableID = c.identity; columns = cols.count
            case .tableHeaderRow: isHeader = true; rowKey = -1
            case .tableRow(let i): rowKey = i
            default: break
            }
        }
        for c in comps {
            switch c.kind {
            case .paragraph: return (.paragraph, c.identity)
            case .header(let l): return (.header(l), c.identity)
            case .codeBlock(let lang): return (.code(lang), c.identity)
            case .thematicBreak: return (.rule, c.identity)
            case .tableCell(let col): return (.cell(table: tableID, row: rowKey, isHeader: isHeader, col: col, columns: columns), c.identity)
            default: continue
            }
        }
        return (.paragraph, comps.first?.identity ?? -1)
    }

    // MARK: inline

    private func append(_ raw: String, run: AttributedString.Runs.Run) {
        guard let b = block else { return }
        let inline = run.inlinePresentationIntent ?? []
        var text = raw
        if inline.contains(.softBreak) { text = " " }
        else if inline.contains(.lineBreak) { text = "\u{2028}" }

        if let img = run.imageURL {
            b.buffer.append(imageAttachment(img, alt: raw)); return
        }

        var font: NSFont
        var color = NSColor.labelColor
        switch b.kind {
        case .header(let l): font = heading(l)
        case .code: font = mono
        case .cell(_, _, let isHeader, _, _): font = isHeader ? .systemFont(ofSize: 14 * zoom, weight: .semibold) : .systemFont(ofSize: 14 * zoom)
        default: font = body
        }
        if b.comps.contains(where: { if case .blockQuote = $0.kind { return true }; return false }) { color = .secondaryLabelColor }

        var attrs: [NSAttributedString.Key: Any] = [:]
        if inline.contains(.code), case .code = b.kind {} else if inline.contains(.code) {
            font = .monospacedSystemFont(ofSize: font.pointSize * 0.88, weight: .regular)
            attrs[.backgroundColor] = Self.codeBG
        }
        if inline.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if inline.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        if inline.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue; color = .secondaryLabelColor }
        if let link = run.link { attrs[.link] = link; color = Self.accent }
        attrs[.font] = font
        attrs[.foregroundColor] = color
        b.buffer.append(NSAttributedString(string: text, attributes: attrs))
    }

    private func imageAttachment(_ url: URL, alt: String) -> NSAttributedString {
        var fileURL = url
        if url.scheme == nil || url.isFileURL {
            let rel = url.isFileURL ? url.path : (url.path.removingPercentEncoding ?? url.path)
            fileURL = rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : (baseURL ?? URL(fileURLWithPath: "/")).appendingPathComponent(rel)
        }
        guard fileURL.isFileURL, let img = NSImage(contentsOf: fileURL), img.size.width > 0 else {
            return NSAttributedString(string: alt.isEmpty ? "[image]" : alt, attributes: [.font: body, .foregroundColor: NSColor.tertiaryLabelColor])
        }
        let maxW: CGFloat = 720 * zoom
        let scale = min(1, maxW / img.size.width)
        let a = NSTextAttachment()
        a.image = img
        a.bounds = CGRect(x: 0, y: 0, width: img.size.width * scale, height: img.size.height * scale)
        return NSAttributedString(attachment: a)
    }

    // MARK: blocks

    private func flushBlock() {
        guard let b = block else { return }
        block = nil
        if case .cell(let t, let row, _, let col, let columns) = b.kind {
            if table == nil || table!.id != t { flushTable(); table = TableBuffer(id: t, columns: columns) }
            table!.rows[row, default: [:]][col] = b.buffer
            return
        }
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 4 * zoom
        ps.paragraphSpacing = 10 * zoom
        var indent: CGFloat = 0
        var prefix: NSAttributedString?
        var extra: [NSAttributedString.Key: Any] = [:]
        var quoteIndent: CGFloat = 0

        // containers: quotes and lists, outermost → innermost by identity
        let containers = b.comps.filter {
            switch $0.kind { case .blockQuote, .orderedList, .unorderedList, .listItem: return true; default: return false }
        }.sorted { $0.identity < $1.identity }
        var listDepth = 0
        var innerList: PresentationIntent.IntentType?
        var innerItem: PresentationIntent.IntentType?
        for c in containers {
            switch c.kind {
            case .blockQuote:
                extra[.mdvQuote] = "\(c.identity):\(quoteIndent + 1)"
                quoteIndent += 18 * zoom
            case .orderedList, .unorderedList: listDepth += 1; innerList = c
            case .listItem: innerItem = c
            default: break
            }
        }
        if let item = innerItem, let list = innerList {
            indent = quoteIndent + CGFloat(listDepth - 1) * 24 * zoom
            let first = !seenListItems.contains(item.identity)
            seenListItems.insert(item.identity)
            if first {
                if case .listItem(let ordinal) = item.kind, case .orderedList = list.kind {
                    prefix = NSAttributedString(string: "\(ordinal).\t", attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor])
                } else if let box = taskCheckbox(stripping: b.buffer) {
                    prefix = box
                } else {
                    prefix = NSAttributedString(string: "•\t", attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor])
                }
            }
            ps.firstLineHeadIndent = indent
            ps.headIndent = indent + 24 * zoom
            ps.tabStops = [NSTextTab(textAlignment: .left, location: indent + 24 * zoom)]
            ps.paragraphSpacing = 4 * zoom
            if prefix == nil { ps.firstLineHeadIndent = ps.headIndent }
        } else if quoteIndent > 0 {
            ps.firstLineHeadIndent = quoteIndent
            ps.headIndent = quoteIndent
        }

        let start = out.length
        switch b.kind {
        case .header(let l):
            ps.paragraphSpacingBefore = [10, 26, 20, 16, 14, 14][max(0, min(l, 6) - 1)] * zoom
            ps.paragraphSpacing = (l <= 2 ? 12 : 8) * zoom
            ps.lineSpacing = 2 * zoom
            if l <= 2 { extra[.mdvRule] = start; ps.paragraphSpacing = 18 * zoom }
            let title = b.buffer.string.trimmingCharacters(in: .whitespacesAndNewlines)
            outline.append(OutlineEntry(level: l, title: title, slug: uniqueSlug(title), location: start))
        case .code(let lang):
            extra[.mdvCode] = b.id
            ps.headIndent = indent + 14 * zoom
            ps.firstLineHeadIndent = indent + 14 * zoom
            ps.tailIndent = -14 * zoom
            ps.lineSpacing = 2.5 * zoom
            ps.paragraphSpacing = 0
            ps.paragraphSpacingBefore = 0
            out.append(spacer(12))
            while b.buffer.string.hasSuffix("\n") { b.buffer.deleteCharacters(in: NSRange(location: b.buffer.length - 1, length: 1)) }
            Highlighter.highlight(b.buffer, language: lang)
        case .rule:
            extra[.mdvHR] = start
            b.buffer.setAttributedString(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 1)]))
            ps.minimumLineHeight = 28 * zoom; ps.maximumLineHeight = 28 * zoom; ps.paragraphSpacing = 0
        default: break
        }

        let para = NSMutableAttributedString()
        if let p = prefix { para.append(p) }
        para.append(b.buffer)
        para.append(NSAttributedString(string: "\n", attributes: [.font: b.buffer.length > 0 ? (b.buffer.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? body) : body]))
        para.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: para.length))
        for (k, v) in extra { para.addAttribute(k, value: v, range: NSRange(location: 0, length: para.length)) }
        out.append(para)
        if case .code = b.kind { out.append(spacer(12)) }
    }

    private func spacer(_ h: CGFloat) -> NSAttributedString {
        let ps = NSMutableParagraphStyle(); ps.maximumLineHeight = h * zoom; ps.minimumLineHeight = h * zoom; ps.paragraphSpacing = 0
        return NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: ps])
    }

    /// "[ ] text" / "[x] text" at the start of a list item → checkbox glyph, marker removed.
    private func taskCheckbox(stripping buf: NSMutableAttributedString) -> NSAttributedString? {
        let s = buf.string
        let checked: Bool
        if s.hasPrefix("[ ] ") { checked = false } else if s.lowercased().hasPrefix("[x] ") { checked = true } else { return nil }
        buf.deleteCharacters(in: NSRange(location: 0, length: 4))
        let name = checked ? "checkmark.square.fill" : "square"
        let palette: [NSColor] = checked ? [.white, Self.accent] : [.secondaryLabelColor]
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14 * zoom, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: palette)) else { return nil }
        let a = NSTextAttachment(); a.image = img
        a.bounds = CGRect(x: 0, y: -2.5 * zoom, width: 15 * zoom, height: 15 * zoom)
        let r = NSMutableAttributedString(attachment: a)
        r.append(NSAttributedString(string: "\t", attributes: [.font: body]))
        return r
    }

    private func uniqueSlug(_ title: String) -> String {
        var s = title.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }
            .replacingOccurrences(of: " ", with: "-")
        if s.isEmpty { s = "section" }
        let n = slugCounts[s, default: 0]; slugCounts[s] = n + 1
        return n == 0 ? s : "\(s)-\(n)"
    }

    // MARK: tables

    private func flushTable() {
        guard let t = table else { return }
        table = nil
        let nsTable = NSTextTable()
        nsTable.numberOfColumns = t.columns
        nsTable.collapsesBorders = true
        nsTable.hidesEmptyCells = false
        let rowKeys = t.rows.keys.sorted()      // header (-1) first
        for (r, key) in rowKeys.enumerated() {
            let isHeader = key == -1
            for c in 0..<t.columns {
                let cell = NSTextTableBlock(table: nsTable, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                cell.setWidth(1, type: .absoluteValueType, for: .border)
                cell.setBorderColor(Self.rule)
                cell.setWidth(7 * zoom, type: .absoluteValueType, for: .padding)
                cell.setWidth(11 * zoom, type: .absoluteValueType, for: .padding, edge: .minX)
                cell.setWidth(11 * zoom, type: .absoluteValueType, for: .padding, edge: .maxX)
                if isHeader { cell.backgroundColor = Self.theadBG }
                let ps = NSMutableParagraphStyle(); ps.textBlocks = [cell]; ps.lineSpacing = 2 * zoom
                let content = NSMutableAttributedString()
                if let txt = t.rows[key]?[c] { content.append(txt) }
                content.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 14 * zoom)]))
                content.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: content.length))
                out.append(content)
            }
        }
        out.append(spacer(12))
    }
}
