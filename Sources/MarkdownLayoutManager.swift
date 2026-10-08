import AppKit

extension NSAttributedString.Key {
    static let mdvCode  = NSAttributedString.Key("mdv.code")    // value: block id (Int)
    static let mdvQuote = NSAttributedString.Key("mdv.quote")   // value: "id:barX"
    static let mdvRule  = NSAttributedString.Key("mdv.rule")    // heading underline
    static let mdvHR    = NSAttributedString.Key("mdv.hr")      // horizontal rule
}

/// Draws the decorations TextKit's text blocks can't be trusted with: code block cards,
/// blockquote bars, heading rules and horizontal rules. Tables still use NSTextTableBlock.
final class MarkdownLayoutManager: NSLayoutManager {
    var zoom: CGFloat = 1

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let ts = textStorage, let tc = textContainers.first, ts.length > 0 else { return }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let width = tc.size.width
        let all = NSRange(location: 0, length: ts.length)

        func fullRun(_ key: NSAttributedString.Key, at loc: Int) -> NSRange {
            var r = NSRange(location: 0, length: 0)
            _ = ts.attribute(key, at: loc, longestEffectiveRange: &r, in: all)
            return r
        }
        func span(_ r: NSRange) -> NSRect {
            let g = glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            guard g.length > 0 else { return .zero }
            let first = lineFragmentUsedRect(forGlyphAt: g.location, effectiveRange: nil)
            let last = lineFragmentUsedRect(forGlyphAt: max(g.location, NSMaxRange(g) - 1), effectiveRange: nil)
            return NSRect(x: origin.x, y: first.minY + origin.y, width: width, height: last.maxY - first.minY)
        }

        // code blocks
        ts.enumerateAttribute(.mdvCode, in: visible, options: []) { v, r, _ in
            guard v != nil else { return }
            let rect = span(fullRun(.mdvCode, at: r.location)).insetBy(dx: 0, dy: -8 * zoom)
            let p = NSBezierPath(roundedRect: rect, xRadius: 8 * zoom, yRadius: 8 * zoom)
            MarkdownRenderer.codeBG.setFill(); p.fill()
            MarkdownRenderer.codeEdge.setStroke(); p.lineWidth = 1; p.stroke()
        }
        // blockquote bars
        ts.enumerateAttribute(.mdvQuote, in: visible, options: []) { v, r, _ in
            guard let s = v as? String, let colon = s.firstIndex(of: ":"), let barX = Double(s[s.index(after: colon)...]) else { return }
            let rect = span(fullRun(.mdvQuote, at: r.location))
            let bar = NSRect(x: origin.x + CGFloat(barX), y: rect.minY, width: 3, height: rect.height)
            MarkdownRenderer.quoteBar.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }
        // heading rules
        ts.enumerateAttribute(.mdvRule, in: visible, options: []) { v, r, _ in
            guard v != nil else { return }
            let rect = span(fullRun(.mdvRule, at: r.location))
            let y = rect.maxY + 6 * zoom
            MarkdownRenderer.rule.setFill()
            NSRect(x: origin.x, y: y, width: width, height: 1).fill()
        }
        // horizontal rules
        ts.enumerateAttribute(.mdvHR, in: visible, options: []) { v, r, _ in
            guard v != nil else { return }
            let rect = span(fullRun(.mdvHR, at: r.location))
            MarkdownRenderer.rule.setFill()
            NSRect(x: origin.x, y: rect.midY, width: width, height: 1).fill()
        }
    }
}
