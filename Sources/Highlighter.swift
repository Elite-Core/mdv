import AppKit

/// Small native syntax colorer for code blocks: comments, strings, numbers, keywords.
enum Highlighter {
    static let keyword = MarkdownRenderer.dyn(NSColor(srgbRed: 0.81, green: 0.13, blue: 0.18, alpha: 1), NSColor(srgbRed: 1.0, green: 0.48, blue: 0.45, alpha: 1))
    static let string  = MarkdownRenderer.dyn(NSColor(srgbRed: 0.04, green: 0.19, blue: 0.41, alpha: 1), NSColor(srgbRed: 0.65, green: 0.84, blue: 1.0, alpha: 1))
    static let comment = MarkdownRenderer.dyn(NSColor(srgbRed: 0.43, green: 0.47, blue: 0.51, alpha: 1), NSColor(srgbRed: 0.55, green: 0.58, blue: 0.62, alpha: 1))
    static let number  = MarkdownRenderer.dyn(NSColor(srgbRed: 0.02, green: 0.31, blue: 0.68, alpha: 1), NSColor(srgbRed: 0.47, green: 0.75, blue: 1.0, alpha: 1))

    static let keywords: Set<String> = [
        "if","else","for","while","do","switch","case","default","break","continue","return","function","func","def","fn",
        "class","struct","enum","protocol","interface","extension","import","export","from","as","package","module","require",
        "let","var","const","val","static","final","public","private","internal","protected","override","async","await",
        "try","catch","finally","throw","throws","throws","new","delete","this","self","super","in","of","is","not","and","or",
        "true","false","null","nil","none","None","True","False","undefined","void","int","string","bool","typeof","instanceof",
        "guard","defer","where","yield","with","lambda","pass","raise","except","elif","print","echo","exit","then","fi","done",
        "select","insert","update","delete","from","where","join","left","right","inner","on","group","by","order","limit","create","table","alter","drop","into","values","set","begin","commit","rollback","and","or","as","distinct",
        "type","any","never","unknown","readonly","declare","namespace","abstract","implements","extends","go","chan","map","range","match","impl","pub","mut","use","mod","crate","trait",
    ]

    static func highlight(_ s: NSMutableAttributedString, language: String?) {
        let lang = (language ?? "").lowercased()
        let hashComment: Set<String> = ["py","python","sh","bash","zsh","shell","yaml","yml","toml","ruby","rb","dockerfile","makefile","perl","r"]
        let dashComment: Set<String> = ["sql","psql","lua","haskell"]
        var commentPat = #"//[^\n]*|/\*[\s\S]*?\*/"#
        if hashComment.contains(lang) { commentPat = #"#[^\n]*"# }
        else if dashComment.contains(lang) { commentPat = #"--[^\n]*"# }
        else if lang.isEmpty { commentPat = #"//[^\n]*|/\*[\s\S]*?\*/|(?m:^\s*#[^\n]*)"# }
        let pattern = "(\(commentPat))|(\"(?:\\\\.|[^\"\\\\\\n])*\"|'(?:\\\\.|[^'\\\\\\n])*'|`(?:\\\\.|[^`\\\\])*`)|\\b(\\d+(?:\\.\\d+)?)\\b|\\b([A-Za-z_][A-Za-z0-9_]*)\\b"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let text = s.string as NSString
        re.enumerateMatches(in: s.string, range: NSRange(location: 0, length: text.length)) { m, _, _ in
            guard let m else { return }
            if m.range(at: 1).location != NSNotFound { s.addAttribute(.foregroundColor, value: comment, range: m.range(at: 1)) }
            else if m.range(at: 2).location != NSNotFound { s.addAttribute(.foregroundColor, value: string, range: m.range(at: 2)) }
            else if m.range(at: 3).location != NSNotFound { s.addAttribute(.foregroundColor, value: number, range: m.range(at: 3)) }
            else if m.range(at: 4).location != NSNotFound, keywords.contains(text.substring(with: m.range(at: 4))) {
                s.addAttribute(.foregroundColor, value: keyword, range: m.range(at: 4))
            }
        }
    }
}
