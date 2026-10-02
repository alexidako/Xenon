import Foundation

/// Plain-language element search: "liquid at room temperature", "halogens discovered before 1850",
/// "melting point above 3000 K", "heaviest noble gas", "group 17", "period 3 metals" ...
/// Rule-based (no network, no AI): it recognises a fixed set of phrases and combines them with AND.
enum ElementQuery {
    struct Result {
        var matches: [Element]
        var description: String
        var unsupported: Bool = false
    }

    // MARK: properties

    enum Prop: CaseIterable {
        case affinity, ionization, covalent, vdw, melting, boiling, electronegativity, mass

        var pattern: String {
            switch self {
            case .affinity: return "electron affinity"
            case .ionization: return "(?:first )?(?:ionis|ioniz)ation(?: energy)?"
            case .covalent: return "covalent radius"
            case .vdw: return "(?:van der waals|vdw|atomic) radius|radii|radius|size"
            case .melting: return "melting (?:point|temperature)|melting"
            case .boiling: return "boiling (?:point|temperature)|boiling"
            case .electronegativity: return "electronegativity|electronegative"
            case .mass: return "(?:atomic )?(?:mass|weight)"
            }
        }
        var label: String {
            switch self {
            case .affinity: return "electron affinity"
            case .ionization: return "ionization energy"
            case .covalent: return "covalent radius"
            case .vdw: return "radius"
            case .melting: return "melting point"
            case .boiling: return "boiling point"
            case .electronegativity: return "electronegativity"
            case .mass: return "atomic mass"
            }
        }
        var unit: String {
            switch self {
            case .affinity, .ionization: return "eV"
            case .covalent, .vdw: return "Å"
            case .melting, .boiling: return "K"
            case .mass: return "u"
            case .electronegativity: return ""
            }
        }
        var isTemperature: Bool { self == .melting || self == .boiling }
        func value(_ e: Element) -> Double? {
            switch self {
            case .affinity: return e.electronAffinity
            case .ionization: return e.ionization
            case .covalent: return e.radiusCovalent
            case .vdw: return e.radiusVDW
            case .melting: return e.meltingPoint
            case .boiling: return e.boilingPoint
            case .electronegativity: return e.electronegativity
            case .mass: return e.mass
            }
        }
    }

    // MARK: text scanner

    private struct Scan {
        var s: String
        mutating func take(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            let ns = s as NSString
            let groups = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
            s = ns.replacingCharacters(in: m.range, with: " ")
            return groups
        }
        func has(_ pattern: String) -> Bool {
            (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
    }

    private static let num = "(-?\\d+(?:\\.\\d+)?)"
    private static let unitPat = "(k|kelvin|°c|°|celsius|c|ev|u|å)?(?![a-z])"
    private static let above = "above|over|greater than|more than|higher than|larger than|bigger than|at least|exceeding|>=|>"
    private static let below = "below|under|less than|lower than|smaller than|at most|<=|<"

    private static let countries: [String: String] = [
        "germany": "de", "denmark": "dk", "spain": "es", "finland": "fi", "france": "fr", "italy": "it", "russia": "ru",
        "sweden": "se", "uk": "uk", "britain": "uk", "england": "uk", "united kingdom": "uk", "scotland": "uk",
        "us": "us", "usa": "us", "america": "us", "united states": "us", "japan": "jp",
    ]

    private static let unsupportedWords = ["density", "dense", "conductivity", "conductor", "price", "cost", "abundance in", "crust",
                                           "toxic", "magnetic", "color", "colour", "hardness", "heat capacity", "crystal structure"]

    private static func kelvin(_ value: Double, unit: String) -> Double {
        ["°c", "°", "celsius", "c"].contains(unit) ? value + 273.15 : value
    }

    // MARK: entry point

    /// Returns nil if the text does not look like a query (so the caller can fall back to a name search).
    static let stable: (Element) -> Bool = { e in
        (IsotopeStore.byElement[e.z] ?? []).contains { $0.halfLife == nil && $0.abundance != nil }
    }

    static func run(_ raw: String, isStable: ((Element) -> Bool)? = ElementQuery.stable) -> Result? {
        var t = Scan(s: " " + raw.lowercased().replacingOccurrences(of: "’", with: "'") + " ")
        var filters: [(String, (Element) -> Bool)] = []
        var sort: (prop: Prop, descending: Bool, count: Int)?
        var recognised = false

        // unsupported properties: say so instead of guessing
        if let w = unsupportedWords.first(where: { t.has("\\b" + $0) }) {
            let known = Prop.allCases.contains { t.has("\\b(?:" + $0.pattern + ")\\b") }
            if !known {
                return Result(matches: [], description: "This app has no “\(w)” data. Try mass, melting/boiling point, electronegativity, ionization energy, radius, family, block, period, group, state or discovery.", unsupported: true)
            }
        }

        // superlatives
        if let g = t.take("\\b(?:the )?(?:top (\\d+) )?(highest|largest|biggest|greatest|most|heaviest|lowest|smallest|least|lightest)\\b(?: (\\d+))?") {
            let adj = g[2]
            let desc = ["highest", "largest", "biggest", "greatest", "most", "heaviest"].contains(adj)
            let n = Int(g[1]) ?? Int(g[3]) ?? 3
            var prop: Prop?
            if adj == "heaviest" || adj == "lightest" { prop = .mass }
            for p in [Prop.affinity, .ionization, .covalent, .vdw, .melting, .boiling, .electronegativity, .mass] where prop == nil {
                if t.take("\\b(?:" + p.pattern + ")\\b") != nil { prop = p }
            }
            if prop == nil, ["largest", "smallest", "biggest"].contains(adj) { prop = .vdw; _ = t.take("\\b(?:atoms?|elements?)\\b") }
            if let prop { sort = (prop, desc, n); recognised = true }
        }

        // families (longest names first so "alkaline earth" wins over "alkali")
        let families: [(String, [Family], String)] = [
            ("alkaline[- ]earth(?: metals?)?", [.alkalineEarth], "alkaline earth metals"),
            ("alkali(?: metals?)?", [.alkali], "alkali metals"),
            ("transition(?: metals?)?", [.transition], "transition metals"),
            ("(?:post[- ]transition|other) metals?", [.otherMetal], "other metals"),
            ("metalloids?|semi-?metals?", [.metalloid], "metalloids"),
            ("non-?metals?", [.nonMetal], "nonmetals"),
            ("halogens?", [.halogen], "halogens"),
            ("noble gas(?:es)?", [.nobleGas], "noble gases"),
            ("lanthanides?|actinides?|rare[- ]earths?", [.rareEarth], "lanthanides & actinides"),
            ("metals?", [.alkali, .alkalineEarth, .transition, .otherMetal, .rareEarth], "metals"),
        ]
        for (pat, fams, label) in families {
            if t.take("\\b(?:" + pat + ")\\b") != nil {
                filters.append((label, { e in e.familyKind.map(fams.contains) ?? false })); recognised = true; break
            }
        }

        // states of matter
        if let g = t.take("\\b(solid|liquid|gas|gaseous)(?:e?s)?\\b(?: at (?:(?:room temp(?:erature)?)|(stp|standard (?:conditions|temperature))|" + num + " ?" + unitPat + "))?") {
            var T = 298.15
            if !g[2].isEmpty { T = 273.15 } else if !g[3].isEmpty {
                let v = Double(g[3]) ?? 298.15
                T = g[4] == "°f" ? (v - 32) * 5 / 9 + 273.15 : kelvin(v, unit: g[4])
            }
            let want: MatterState = g[1] == "solid" ? .solid : g[1] == "liquid" ? .liquid : .gas
            filters.append(("\(want == .gas ? "gases" : want.rawValue.lowercased() + "s") at \(formatNumber(T)) K", { $0.state(atKelvin: T) == want }))
            recognised = true
        }

        // numeric comparisons
        func addCompare(_ p: Prop, _ op: String, _ v: Double, _ unit: String) {
            let x = p.isTemperature ? kelvin(v, unit: unit) : v
            if (above.split(separator: "|").map(String.init)).contains(op) {
                filters.append(("\(p.label) > \(formatNumber(x)) \(p.unit)", { (p.value($0) ?? -.infinity) > x }))
            } else {
                filters.append(("\(p.label) < \(formatNumber(x)) \(p.unit)", { (p.value($0) ?? .infinity) < x }))
            }
            recognised = true
        }
        if let g = t.take("\\b(heavier|lighter) than " + num) {
            addCompare(.mass, g[1] == "heavier" ? ">" : "<", Double(g[2]) ?? 0, ""); 
        }
        for p in Prop.allCases {
            while let g = t.take("\\b(?:" + p.pattern + ")\\b(?: is| of| at)? ?(" + above + "|" + below + ") ?" + num + " ?" + unitPat) {
                addCompare(p, g[1], Double(g[2]) ?? 0, g[3])
            }
            if let g = t.take("\\b(?:" + p.pattern + ")\\b (?:is |of )?between " + num + " ?" + unitPat + " and " + num + " ?" + unitPat) {
                let lo = p.isTemperature ? kelvin(Double(g[1]) ?? 0, unit: g[2]) : Double(g[1]) ?? 0
                let hi = p.isTemperature ? kelvin(Double(g[3]) ?? 0, unit: g[4].isEmpty ? g[2] : g[4]) : Double(g[3]) ?? 0
                filters.append(("\(p.label) \(formatNumber(lo))–\(formatNumber(hi)) \(p.unit)", { e in
                    guard let v = p.value(e) else { return false }
                    return v >= min(lo, hi) && v <= max(lo, hi)
                }))
                recognised = true
            }
        }

        if let g = t.take("\\b([spdf])[- ]?block\\b") {
            filters.append(("\(g[1])-block", { $0.block == g[1] })); recognised = true
        }
        if let g = t.take("\\bperiod (\\d+)\\b") {
            let n = Int(g[1]) ?? 0
            filters.append(("period \(n)", { $0.period == n })); recognised = true
        }
        if let g = t.take("\\bgroup (\\d+)\\b") {
            let n = Int(g[1]) ?? 0
            filters.append(("group \(n)", { e in
                let p = e.gridPosition
                return p.row < 8 && p.col + 1 == n
            })); recognised = true
        }

        // discovery
        if let g = t.take("\\b(?:discovered|found|isolated|identified)? ?(before|prior to|after|since|until|by|in|during) (?:the year )?(\\d{3,4})\\b") {
            let y = Double(g[2]) ?? 0
            switch g[1] {
            case "before", "prior to": filters.append(("discovered before \(Int(y))", { ($0.discoveryYear ?? 99999) < y && ($0.discoveryYear ?? 0) > 0 }))
            case "after": filters.append(("discovered after \(Int(y))", { ($0.discoveryYear ?? 0) > y }))
            case "since": filters.append(("discovered since \(Int(y))", { ($0.discoveryYear ?? 0) >= y }))
            case "until", "by": filters.append(("discovered by \(Int(y))", { ($0.discoveryYear ?? 99999) <= y && ($0.discoveryYear ?? 0) > 0 }))
            default: filters.append(("discovered in \(Int(y))", { $0.discoveryYear == y }))
            }
            recognised = true
        }
        if t.take("\\b(?:known since antiquity|ancient|prehistoric)\\b") != nil {
            filters.append(("known since antiquity", { $0.discoveryYear == 0 || $0.discoveryCountry.contains("ancient") })); recognised = true
        }
        if let g = t.take("\\b(?:discovered|found|isolated) (?:in|by|from) ([a-z.' ]+?)(?= and | with | that | which |$| in )") {
            let who = g[1].trimmingCharacters(in: .whitespaces)
            if let code = countries[who] {
                filters.append(("discovered in \(who.capitalized)", { $0.discoveryCountry.contains(code) })); recognised = true
            } else if who.count >= 3 {
                filters.append(("discovered by \(who.capitalized)", { e in e.discoverers.contains { $0.lowercased().contains(who) } })); recognised = true
            }
        }

        // oxidation state
        if let g = t.take("\\boxidation (?:state|number) ([+-]?\\d+)\\b") {
            let n = Int(g[1].replacingOccurrences(of: "+", with: "")) ?? 0
            filters.append(("oxidation state \(n > 0 ? "+" : "")\(n)", { $0.oxidation.contains(n) })); recognised = true
        }

        // stability
        if let isStable {
            if t.take("\\b(?:radioactive|unstable)\\b") != nil { filters.append(("radioactive (no stable isotope)", { !isStable($0) })); recognised = true }
            else if t.take("\\b(?:stable|non-?radioactive)\\b") != nil { filters.append(("has a stable isotope", { isStable($0) })); recognised = true }
        }

        // name starts with
        if let g = t.take("\\b(?:starting|starts|beginning|begins) with (?:the letter )?([a-z])\\b") {
            filters.append(("name starts with \(g[1].uppercased())", { $0.name.lowercased().hasPrefix(g[1]) })); recognised = true
        }

        guard recognised else { return nil }

        var list = ElementStore.all.filter { e in filters.allSatisfy { $0.1(e) } }
        var parts = filters.map(\.0)
        if let s = sort {
            list = list.filter { s.prop.value($0) != nil }.sorted { a, b in
                let x = s.prop.value(a) ?? 0, y = s.prop.value(b) ?? 0
                if x == y { return a.z < b.z }
                return s.descending ? x > y : x < y
            }
            list = Array(list.prefix(s.count))
            parts.insert("\(s.descending ? "highest" : "lowest") \(s.prop.label) (top \(s.count))", at: 0)
        }
        return Result(matches: list, description: parts.joined(separator: " · "))
    }
}
