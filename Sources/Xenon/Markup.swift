import Foundation

/// Kalzium's text data uses a tiny BBCode-style markup: [sub]..[/sub], [sup]..[/sup], [i]..[/i], [br].
/// Sub/superscripts become real Unicode characters (μₙ, 10⁻²⁷); anything without a Unicode form falls back
/// to a baseline shift.
enum Markup {
    private static let superscripts: [Character: Character] = {
        var m: [Character: Character] = [:]
        for (a, b) in zip("0123456789+-=()", "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾") { m[a] = b }
        for (a, b) in zip("abcdefghijklmnoprstuvwxyz", "ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻ") { m[a] = b }
        m["−"] = "⁻"
        return m
    }()
    private static let subscripts: [Character: Character] = {
        var m: [Character: Character] = [:]
        for (a, b) in zip("0123456789+-=()", "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎") { m[a] = b }
        for (a, b) in zip("aehijklmnoprstuvx", "ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ") { m[a] = b }
        m["−"] = "₋"
        return m
    }()

    private enum Style { case normal, sub, sup }

    static func attributed(_ raw: String) -> AttributedString {
        // Kalzium's data writes beta as the German "ß"; it means the Greek letter.
        let source = raw.replacingOccurrences(of: "ß", with: "β")
        var out = AttributedString()
        var italic = false
        var style = Style.normal

        func append(_ text: String) {
            guard !text.isEmpty else { return }
            switch style {
            case .normal:
                var a = AttributedString(text)
                if italic { a.inlinePresentationIntent = .emphasized }
                out += a
            case .sub, .sup:
                let table = style == .sub ? subscripts : superscripts
                for ch in text {
                    var a = AttributedString(String(table[ch] ?? ch))
                    if table[ch] == nil { a.baselineOffset = style == .sub ? -4 : 6 }   // no Unicode form: shift instead
                    if italic { a.inlinePresentationIntent = .emphasized }
                    out += a
                }
            }
        }

        let re = try! NSRegularExpression(pattern: "\\[(/?)(sub|sup|i|br)\\]", options: .caseInsensitive)
        let ns = source as NSString
        var last = 0
        for m in re.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            let closing = ns.substring(with: m.range(at: 1)) == "/"
            switch ns.substring(with: m.range(at: 2)).lowercased() {
            case "sub": style = closing ? .normal : .sub
            case "sup": style = closing ? .normal : .sup
            case "i": italic = !closing
            default: out += AttributedString("\n")           // [br]
            }
            last = m.range.location + m.range.length
        }
        append(ns.substring(from: last))
        return out
    }

    /// Chemical formula with real subscripts and charges: "Fe[2+]" → Fe²⁺, "3 H2O" → 3 H₂O, "CH3(CH2)3COOH" → CH₃(CH₂)₃COOH.
    static func formulaText(_ f: String) -> String {
        var out = "", prev: Character = " "
        var i = f.startIndex
        while i < f.endIndex {
            let c = f[i]
            if c == "[", let close = f[i...].firstIndex(of: "]") {
                let inner = f[f.index(after: i)..<close]
                if inner.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" }) && !inner.isEmpty {
                    out += String(inner.map { ch -> Character in
                        switch ch { case "+": return "⁺"; case "-": return "⁻"; default: return superscripts[ch] ?? ch }
                    })
                    i = f.index(after: close); prev = "]"; continue
                }
            }
            if c.isNumber, prev.isLetter || prev == ")" { out.append(subscripts[c] ?? c) } else { out.append(c) }
            prev = c.isNumber && (prev.isLetter || prev == ")") ? "a" : c      // digits after a subscript keep subscripting: C10H22
            i = f.index(after: i)
        }
        return out
    }

    /// Plain-text result, for tests and search.
    static func plain(_ source: String) -> String { String(attributed(source).characters) }
}

enum MarkupSelfTest {
    static func run() {
        let sample = "μ[sub]n[/sub]=(5.0507866 ± 0.0000017) 10[sup]-27[/sup] JT[sup]-1[/sup]"
        SelfTest.check(Markup.plain(sample) == "μₙ=(5.0507866 ± 0.0000017) 10⁻²⁷ JT⁻¹", "markup: magnetic moment formula", Markup.plain(sample))
        SelfTest.check(Markup.plain("ß[sup]+[/sup] decay[br]next") == "β⁺ decay\nnext", "markup: beta, superscript sign and line break", Markup.plain("ß[sup]+[/sup] decay[br]next"))
        SelfTest.check(Markup.plain("a[sup]58m[/sup]") == "a⁵⁸ᵐ", "markup: isomer superscript", Markup.plain("a[sup]58m[/sup]"))
        SelfTest.check(Markup.formulaText("CH3CH2OH + 3 O2 -> 3 H2O + 2 CO2") == "CH₃CH₂OH + 3 O₂ -> 3 H₂O + 2 CO₂", "markup: formulas get subscripts but coefficients do not", Markup.formulaText("CH3CH2OH + 3 O2 -> 3 H2O + 2 CO2"))
        SelfTest.check(Markup.formulaText("Fe[2+] + MnO4[-] + 8 H3O[+]") == "Fe²⁺ + MnO₄⁻ + 8 H₃O⁺" && Markup.formulaText("CH3(CH2)3COOH") == "CH₃(CH₂)₃COOH" && Markup.formulaText("C10H22") == "C₁₀H₂₂",
                       "markup: charges become superscripts; brackets and two-digit counts work", Markup.formulaText("Fe[2+] + MnO4[-] + 8 H3O[+]"))
        SelfTest.check(Markup.plain("m[sub]e[/sub] is [i]light[/i]") == "mₑ is light", "markup: italics keep their text", Markup.plain("m[sub]e[/sub] is [i]light[/i]"))
        let leftovers = (ReferenceStore.data?.glossary ?? []).filter { g in
            ["[sub", "[/sub", "[sup", "[/sup", "[i]", "[/i]", "[br]"].contains { Markup.plain(g.desc).contains($0) || Markup.plain(g.name).contains($0) }
        }.map(\.name)
        SelfTest.check(leftovers.isEmpty, "markup: no raw tags left in any glossary entry", "\(leftovers)")
        let tools = (ReferenceStore.data?.tools ?? []).filter { Markup.plain($0.desc).contains("[") && Markup.plain($0.desc).contains("]") }.map(\.name)
        SelfTest.check(tools.isEmpty, "markup: no square-bracket markup in lab equipment text", "\(tools)")
    }
}
