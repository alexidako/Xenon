import Foundation

struct ElementCount: Identifiable {
    let element: Element
    var count: Int
    var id: Int { element.z }
    var mass: Double { (element.mass ?? 0) * Double(count) }
}

enum AliasStore {
    static let builtIn = ["Et": "C2H5", "Me": "CH3", "Ph": "C6H5"]
    private static let key = "userAliases"

    static var user: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static var all: [String: String] { builtIn.merging(user) { _, u in u } }
}

/// Parses chemical formulas such as `Ca(OH)2`, `Al2(SO4)3` or `EtOH` (with aliases).
struct FormulaParser {
    private let chars: [Character]
    private var i = 0
    private var counts: [(Element, Int)] = []
    private static let bySymbol = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0) })

    /// Returns nil for invalid input.
    static func parse(_ formula: String) -> [ElementCount]? {
        var expanded = expand(formula.replacingOccurrences(of: "#", with: "").filter { !$0.isWhitespace })
        expanded = expanded.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
        guard !expanded.isEmpty else { return nil }
        var p = FormulaParser(chars: Array(expanded))
        guard let list = p.submolecule(), p.i == p.chars.count, !list.isEmpty else { return nil }
        var merged: [ElementCount] = []
        for (e, n) in list {
            if let idx = merged.firstIndex(where: { $0.element == e }) { merged[idx].count += n }
            else { merged.append(ElementCount(element: e, count: n)) }
        }
        return merged
    }

    /// Replaces alias symbols that are not real element symbols with their expansion.
    private static func expand(_ s: String) -> String {
        let cs = Array(s); var out = ""; var i = 0
        while i < cs.count {
            if cs[i].isUppercase {
                var tok = String(cs[i]); i += 1
                if i < cs.count, cs[i].isLowercase { tok.append(cs[i]); i += 1 }
                if bySymbol[tok] != nil { out += tok }
                else if let exp = AliasStore.all[tok] { out += "(" + exp + ")" }
                else { out += tok }
            } else { out.append(cs[i]); i += 1 }
        }
        return out
    }

    private init(chars: [Character]) { self.chars = chars }

    private mutating func submolecule() -> [(Element, Int)]? {
        var result: [(Element, Int)] = []
        while let t = term() { result += t }
        return result
    }

    private mutating func term() -> [(Element, Int)]? {
        guard i < chars.count else { return nil }
        var group: [(Element, Int)]
        if chars[i].isUppercase {
            var sym = String(chars[i]); i += 1
            if i < chars.count, chars[i].isLowercase { sym.append(chars[i]); i += 1 }
            guard let e = Self.bySymbol[sym] else { i = chars.count + 1; return nil }  // poison: unknown symbol
            group = [(e, 1)]
        } else if chars[i] == "(" {
            i += 1
            guard let inner = submolecule(), i < chars.count, chars[i] == ")" else { i = chars.count + 1; return nil }
            i += 1
            group = inner
        } else { return nil }
        var digits = ""
        while i < chars.count, chars[i].isNumber { digits.append(chars[i]); i += 1 }
        if !digits.isEmpty {
            guard let n = Int(digits), n > 0, n <= 100_000 else { i = chars.count + 1; return nil }     // "O0" is not a formula
            group = group.map { ($0.0, $0.1 * n) }
        }
        return group
    }
}
