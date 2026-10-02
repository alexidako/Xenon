import Foundation

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum QuizKind: String, CaseIterable, Identifiable, Codable {
    case symbolToName = "Symbol → name"
    case nameToSymbol = "Name → symbol"
    case numberToName = "Atomic number → name"
    case nameToNumber = "Name → atomic number"
    case findOnTable = "Find it on the table"
    case family = "Element families"
    case trend = "Periodic trends"
    case configuration = "Electron configurations"
    var id: String { rawValue }
}

struct QuizQuestion: Identifiable {
    let id = UUID()
    let kind: QuizKind
    let prompt: String
    let options: [String]       // empty for "find it on the table"
    let correct: Int            // index into options; ignored for findOnTable
    let z: Int                  // the element this question is mainly about
    let answerZ: Int            // atomic number of the right answer (== z except for trends)
    let explanation: String
}

/// Remembers which elements you miss, so practice can lean on them.
final class QuizStats {
    static let shared: QuizStats = {
        let d = VRT.isActive ? UserDefaults(suiteName: "xenon.vrt.quiz")! : UserDefaults.standard
        if VRT.isActive { d.removePersistentDomain(forName: "xenon.vrt.quiz") }
        return QuizStats(defaults: d)
    }()

    private let defaults: UserDefaults
    private let key = "quizStats.v1"
    struct Entry: Codable { var seen = 0; var missed = 0 }
    private(set) var entries: [Int: Entry]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([Int: Entry].self, from: data) { entries = decoded } else { entries = [:] }
    }

    func record(z: Int, correct: Bool) {
        var e = entries[z] ?? Entry()
        e.seen += 1; if !correct { e.missed += 1 }
        entries[z] = e
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }

    func reset() { entries = [:]; defaults.removeObject(forKey: key) }

    /// Sampling weight: 1 for unseen or perfect elements, up to 6 for ones you always miss.
    func weight(_ z: Int) -> Double {
        guard let e = entries[z], e.seen > 0 else { return 1 }
        return 1 + 5 * Double(e.missed) / Double(e.seen)
    }

    var weakSpots: [(z: Int, missed: Int, seen: Int)] {
        entries.filter { $0.value.missed > 0 }
            .map { (z: $0.key, missed: $0.value.missed, seen: $0.value.seen) }
            .sorted { ($0.missed, -$0.seen) > ($1.missed, -$1.seen) }
    }
}

struct QuizEngine {
    var pool: [Element]
    var kinds: [QuizKind]
    var stats: QuizStats
    var weighted: Bool

    init(upTo maxZ: Int, kinds: [QuizKind], stats: QuizStats = .shared, weighted: Bool = false) {
        self.pool = ElementStore.all.filter { $0.z <= maxZ }
        self.kinds = kinds.isEmpty ? [.symbolToName] : kinds
        self.stats = stats
        self.weighted = weighted
    }

    // MARK: sampling

    mutating func pick<T: RandomNumberGenerator>(using rng: inout T) -> Element {
        guard weighted else { return pool.randomElement(using: &rng)! }
        let weights = pool.map { stats.weight($0.z) }
        var r = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
        for (e, w) in zip(pool, weights) { r -= w; if r < 0 { return e } }
        return pool.last!
    }

    mutating func next<T: RandomNumberGenerator>(using rng: inout T, kind forced: QuizKind? = nil) -> QuizQuestion {
        for _ in 0..<40 {                    // some elements lack the data a kind needs; just try another
            let kind = forced ?? kinds.randomElement(using: &rng)!
            let e = pick(using: &rng)
            if let q = make(kind, for: e, using: &rng) { return q }
        }
        return make(.symbolToName, for: pool.first!, using: &rng)!
    }

    // MARK: generators

    private func shuffled<T: RandomNumberGenerator>(correct: String, distractors: [String], using rng: inout T) -> (options: [String], correct: Int) {
        var opts = Array(Set(distractors.filter { $0 != correct })).sorted().shuffled(using: &rng).prefix(3).map { $0 }
        opts.append(correct)
        opts.shuffle(using: &rng)
        return (opts, opts.firstIndex(of: correct)!)
    }

    private func others<T: RandomNumberGenerator>(than e: Element, using rng: inout T) -> [Element] {
        Array(pool.filter { $0.z != e.z }.shuffled(using: &rng).prefix(12))
    }

    func make<T: RandomNumberGenerator>(_ kind: QuizKind, for e: Element, using rng: inout T) -> QuizQuestion? {
        guard pool.count >= 4 else { return nil }
        let o = others(than: e, using: &rng)
        switch kind {
        case .symbolToName:
            let (opts, c) = shuffled(correct: e.name, distractors: o.map(\.name), using: &rng)
            return QuizQuestion(kind: kind, prompt: "Which element has the symbol \(e.symbol)?", options: opts, correct: c, z: e.z, answerZ: e.z,
                                explanation: "\(e.symbol) is \(e.name)\(e.nameOrigin.map { ". " + $0 } ?? "").")
        case .nameToSymbol:
            let (opts, c) = shuffled(correct: e.symbol, distractors: o.map(\.symbol), using: &rng)
            return QuizQuestion(kind: kind, prompt: "What is the symbol for \(e.name)?", options: opts, correct: c, z: e.z, answerZ: e.z,
                                explanation: "\(e.name) is \(e.symbol), atomic number \(e.z).")
        case .numberToName:
            let (opts, c) = shuffled(correct: e.name, distractors: o.map(\.name), using: &rng)
            return QuizQuestion(kind: kind, prompt: "Which element has atomic number \(e.z)?", options: opts, correct: c, z: e.z, answerZ: e.z,
                                explanation: "Atomic number \(e.z) is \(e.name) (\(e.symbol)).")
        case .nameToNumber:
            let valid = Set(pool.map(\.z))
            let near = (-4...4).filter { $0 != 0 }.map { e.z + $0 }.filter { valid.contains($0) }.map(String.init)
            let (opts, c) = shuffled(correct: String(e.z), distractors: near, using: &rng)
            return QuizQuestion(kind: kind, prompt: "What is the atomic number of \(e.name)?", options: opts, correct: c, z: e.z, answerZ: e.z,
                                explanation: "\(e.name) has \(e.z) protons, so its atomic number is \(e.z).")
        case .findOnTable:
            return QuizQuestion(kind: kind, prompt: "Click \(e.name) (\(e.symbol)) on the periodic table.", options: [], correct: 0, z: e.z, answerZ: e.z,
                                explanation: "\(e.name) is in \(e.iupacGroup.map { "group \($0)" } ?? "the f-block"), period \(e.period.map(String.init) ?? "—").")
        case .family:
            guard let fam = e.familyKind else { return nil }
            let others = Family.allCases.filter { $0 != fam }.map(\.label)
            let (opts, c) = shuffled(correct: fam.label, distractors: others, using: &rng)
            return QuizQuestion(kind: kind, prompt: "What kind of element is \(e.name)?", options: opts, correct: c, z: e.z, answerZ: e.z,
                                explanation: "\(e.name) is one of the \(fam.label.lowercased()).")
        case .trend:
            let props: [(String, (Element) -> Double?, String)] = [
                ("electronegativity", { $0.electronegativity }, ""), ("first ionization energy", { $0.ionization }, " eV"),
                ("covalent radius", { $0.radiusCovalent }, " Å"), ("atomic mass", { $0.mass }, " u"),
                ("melting point", { $0.meltingPoint }, " K"), ("boiling point", { $0.boilingPoint }, " K"),
            ]
            let (name, f, unit) = props.randomElement(using: &rng)!
            guard let a = f(e) else { return nil }
            let partners = o.filter { p in f(p).map { abs($0 - a) > 0.08 * max(abs($0), abs(a)) } ?? false }
            guard let p = partners.first, let b = f(p) else { return nil }
            let higher = a > b ? e : p
            let lowerFirst = Bool.random(using: &rng)
            let ask = lowerFirst ? "lower" : "higher"
            let answer = lowerFirst ? (a > b ? p : e) : higher
            let opts = [e.name, p.name].shuffled(using: &rng)
            return QuizQuestion(kind: kind, prompt: "Which has the \(ask) \(name): \(opts[0]) or \(opts[1])?", options: opts,
                                correct: opts.firstIndex(of: answer.name)!, z: e.z, answerZ: answer.z,
                                explanation: "\(e.name) \(formatNumber(a))\(unit), \(p.name) \(formatNumber(b))\(unit), so \(answer.name) has the \(ask) \(name).")
        case .configuration:
            guard let cfg = e.configuration else { return nil }
            let shown = QuizEngine.pretty(cfg)
            let sameConfig = pool.filter { $0.configuration == cfg && $0.z != e.z }
            guard sameConfig.isEmpty else { return nil }
            let (opts, c) = shuffled(correct: e.name, distractors: o.map(\.name), using: &rng)
            return QuizQuestion(kind: kind, prompt: "Which element has the electron configuration \(shown)?", options: opts, correct: c, z: e.z, answerZ: e.z,
                                explanation: "\(e.name) (\(e.symbol)) is \(shown).")
        }
    }

    /// "[He] 2s2 2p4" → "[He] 2s² 2p⁴"
    static func pretty(_ cfg: String) -> String {
        cfg.split(separator: " ").map { token -> String in
            guard !token.hasPrefix("["), let letterIdx = token.firstIndex(where: { "spdf".contains($0) }) else { return String(token) }
            let head = token[...letterIdx], tail = token[token.index(after: letterIdx)...]
            return String(head) + (Int(tail).map(Subshells.superscript) ?? String(tail))
        }.joined(separator: " ")
    }
}

@MainActor enum QuizSelfTest {
    static func run() {
        let suite = UserDefaults(suiteName: "xenon.test.quiz")!
        suite.removePersistentDomain(forName: "xenon.test.quiz")
        let stats = QuizStats(defaults: suite)
        let byZ = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.z, $0) })

        var problems: [String] = []
        var perKind: [QuizKind: Int] = [:]
        for kind in QuizKind.allCases {
            var engine = QuizEngine(upTo: 54, kinds: [kind], stats: stats)
            for seed in 0..<80 {
                var rng = SeededRNG(seed: UInt64(seed))
                guard let q = engine.make(kind, for: engine.pick(using: &rng), using: &rng) else { continue }
                perKind[kind, default: 0] += 1
                let e = byZ[q.z]!
                if q.explanation.isEmpty { problems.append("\(kind): empty explanation") }
                if kind == .findOnTable { if !q.options.isEmpty { problems.append("find: has options") }; continue }
                if q.options.count < 2 || Set(q.options).count != q.options.count { problems.append("\(kind): options \(q.options)") }
                if q.correct >= q.options.count { problems.append("\(kind): bad index"); continue }
                let right = q.options[q.correct]
                switch kind {
                case .symbolToName, .numberToName: if right != e.name { problems.append("\(kind): \(right) ≠ \(e.name)") }
                case .nameToSymbol: if right != e.symbol { problems.append("\(kind): \(right) ≠ \(e.symbol)") }
                case .nameToNumber: if right != String(e.z) { problems.append("\(kind): \(right) ≠ \(e.z)") }
                case .family: if right != e.familyKind?.label { problems.append("family: \(right) ≠ \(String(describing: e.familyKind?.label))") }
                case .configuration: if right != e.name { problems.append("config: \(right) ≠ \(e.name)") }
                case .trend:
                    let answer = byZ[q.answerZ]!
                    if right != answer.name { problems.append("trend: \(right) ≠ \(answer.name)") }
                    // verify against the data: the prompt names the property and direction
                    let words = q.prompt
                    let props: [(String, (Element) -> Double?)] = [
                        ("electronegativity", { (x: Element) in x.electronegativity }), ("first ionization energy", { (x: Element) in x.ionization }),
                        ("covalent radius", { (x: Element) in x.radiusCovalent }), ("atomic mass", { (x: Element) in x.mass }),
                        ("melting point", { (x: Element) in x.meltingPoint }), ("boiling point", { (x: Element) in x.boilingPoint })]
                    if let p = props.first(where: { words.contains($0.0) }) {
                        let other = q.options.first { $0 != right }.flatMap { n in ElementStore.all.first { $0.name == n } }
                        if let a = p.1(answer), let b = other.flatMap(p.1) {
                            let wantHigher = words.contains("higher")
                            if wantHigher ? !(a > b) : !(a < b) { problems.append("trend wrong: \(q.prompt) → \(right)") }
                        } else { problems.append("trend: missing data \(q.prompt)") }
                    } else { problems.append("trend: unknown property \(q.prompt)") }
                case .findOnTable: break
                }
            }
        }
        SelfTest.check(problems.isEmpty, "quiz: 8 question types × 80 seeds all have unique options and a correct answer matching the element data", "\(problems.prefix(4))")
        SelfTest.check(QuizKind.allCases.allSatisfy { (perKind[$0] ?? 0) >= 40 }, "quiz: every question type can actually be generated (≥ 40 of 80 attempts)", "\(perKind.mapValues { $0 })")

        var rngA = SeededRNG(seed: 7), rngB = SeededRNG(seed: 7)
        var ea = QuizEngine(upTo: 36, kinds: [.symbolToName, .family], stats: stats), eb = ea
        var qa: [String] = [], qb: [String] = []
        for _ in 0..<10 { qa.append(ea.next(using: &rngA).prompt); qb.append(eb.next(using: &rngB).prompt) }
        SelfTest.check(qa == qb, "quiz: the same seed gives the same questions")

        var small = QuizEngine(upTo: 20, kinds: QuizKind.allCases, stats: stats)
        var rng = SeededRNG(seed: 3)
        var inRange = true
        for _ in 0..<100 { if small.next(using: &rng).z > 20 { inRange = false } }
        SelfTest.check(inRange, "quiz: questions stay inside the chosen range of elements")

        // weak spots
        for _ in 0..<6 { stats.record(z: 26, correct: false) }
        for _ in 0..<6 { stats.record(z: 8, correct: true) }
        SelfTest.check(stats.weight(26) == 6 && stats.weight(8) == 1 && stats.weight(99) == 1, "quiz: an always-missed element weighs 6, a known or unseen one weighs 1", "\(stats.weight(26)) \(stats.weight(8))")
        var weighted = QuizEngine(upTo: 36, kinds: [.symbolToName], stats: stats, weighted: true)
        var rng2 = SeededRNG(seed: 11)
        var drawn: [Int] = []
        for _ in 0..<3000 { drawn.append(weighted.pick(using: &rng2).z) }
        let fe = Double(drawn.filter { $0 == 26 }.count) / 3000, base = Double(drawn.filter { $0 == 10 }.count) / 3000
        SelfTest.check(fe > 4 * base && fe > 0.1, "quiz: practising weak spots picks the missed element far more often", "Fe \(fe) vs Ne \(base)")
        SelfTest.check(stats.weakSpots.first?.z == 26 && QuizStats(defaults: suite).entries[26]?.missed == 6, "quiz: weak spots are ranked and survive a restart")
        stats.reset()
        SelfTest.check(stats.weakSpots.isEmpty && QuizStats(defaults: suite).entries.isEmpty, "quiz: resetting clears the history")
        suite.removePersistentDomain(forName: "xenon.test.quiz")

        let g: [String: Int?] = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0.iupacGroup) })
        SelfTest.check(g["H"] == 1 && g["He"] == 18 && g["Ge"] == 14 && g["Fe"] == 8 && g["Zn"] == 12 && g["Ga"] == 13 && (g["La"] ?? 0) == nil && g["La"] != nil && g["Hf"] == 4 && g["Og"] == 18,
                       "quiz: groups use modern IUPAC numbering (He 18, Ge 14, Fe 8; lanthanides have none)", "\(String(describing: g["Ge"])) \(String(describing: g["He"]))")
        var gq = QuizEngine(upTo: 36, kinds: [.findOnTable], stats: stats), grng = SeededRNG(seed: 1)
        var germ = ""
        for _ in 0..<400 { let q = gq.next(using: &grng); if q.z == 32 { germ = q.explanation; break } }
        SelfTest.check(germ.contains("group 14") && germ.contains("period 4"), "quiz: the table question says Germanium is in group 14", germ)
        SelfTest.check(QuizEngine.pretty("[He] 2s2 2p4") == "[He] 2s² 2p⁴" && QuizEngine.pretty("1s1") == "1s¹", "quiz: configurations are shown with superscripts", QuizEngine.pretty("[He] 2s2 2p4"))
    }
}
