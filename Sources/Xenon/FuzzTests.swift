import Foundation
import simd

/// Robustness and consistency checks across the whole app. A crash here kills the process, which the test script reports.
@MainActor enum FuzzTests {
    private static func randomString<T: RandomNumberGenerator>(_ rng: inout T, alphabet: [Character], maxLength: Int) -> String {
        String((0..<Int.random(in: 0...maxLength, using: &rng)).map { _ in alphabet.randomElement(using: &rng)! })
    }

    static func run() {
        var rng = SeededRNG(seed: 20261001)
        let t0 = Date()
        let chem = Array("CHONSPFClBrIKNaMgCaFeCuZn()[]0123456789+-=→ ->abcdxyz.,").map { $0 }
        let text = Array("abcdefghijklmnopqrstuvwxyz ABCXYZ0123456789.,;:()[]{}+-*/^<>=!?#%&\"'\\\n\t éßµΩ💥").map { $0 }

        // ---- parsers must never crash or hang on garbage ----
        var formulaOK = 0
        for _ in 0..<4000 {
            let s = randomString(&rng, alphabet: chem, maxLength: 24)
            if let parts = FormulaParser.parse(s) {
                formulaOK += 1
                if parts.isEmpty || parts.contains(where: { $0.count <= 0 }) { SelfTest.check(false, "fuzz: formula '\(s)' produced an empty or zero-count result") }
            }
        }
        SelfTest.check(formulaOK > 50, "fuzz: 4000 random formulas parsed without crashing (\(formulaOK) were valid)")
        for _ in 0..<3000 { _ = EquationSolver.solve(randomString(&rng, alphabet: chem, maxLength: 40), isElement: { sym in ElementStore.all.contains { $0.symbol == sym } }) }
        for _ in 0..<3000 { _ = Expr.parse(randomString(&rng, alphabet: Array("0123456789.,+-*/^()xyzABsqrtlnexp ").map { $0 }, maxLength: 24)) }
        for _ in 0..<3000 { _ = ElementQuery.run(randomString(&rng, alphabet: text, maxLength: 40)) }
        for _ in 0..<3000 { _ = QuickLookup.search(randomString(&rng, alphabet: text, maxLength: 20)) }
        for _ in 0..<2000 { _ = SpectrumMatcher.parse(randomString(&rng, alphabet: Array("0123456789., ;\nÅnm-eE+").map { $0 }, maxLength: 40), angstrom: Bool.random(using: &rng)) }
        for _ in 0..<2000 { _ = Markup.plain(randomString(&rng, alphabet: Array("[]/subpi br0123456789abc").map { $0 }, maxLength: 40)) }
        for _ in 0..<1500 {
            let cml = "<molecule>" + randomString(&rng, alphabet: Array("<>/=\" atomborder1x3y3z3Hc").map { $0 }, maxLength: 80) + "</molecule>"
            _ = MoleculeIO.parseCML(cml, fallbackName: "x")
            _ = MoleculeIO.parseMOL(randomString(&rng, alphabet: Array("0123456789 .-\nCHOV2000M END").map { $0 }, maxLength: 120), fallbackName: "x")
            _ = MoleculeIO.parseXYZ(randomString(&rng, alphabet: Array("0123456789 .-\nCHO").map { $0 }, maxLength: 80), fallbackName: "x")
        }
        SelfTest.check(true, "fuzz: query, lookup, expression, equation, spectrum, markup and molecule-file parsers survived 20,000 random inputs")

        // ---- every quick-lookup / query result must point at something real ----
        var bad: [String] = []
        for _ in 0..<500 {
            for item in QuickLookup.search(randomString(&rng, alphabet: Array("abcdefghijklmnopqrstuvwxyz 0123456789").map { $0 }, maxLength: 6)) {
                switch item.target {
                case .element(let z): if !(1...118).contains(z) { bad.append("element \(z)") }
                case .glossary(let n): if !(ReferenceStore.data?.glossary.contains { $0.name == n } ?? false) { bad.append("glossary \(n)") }
                case .equipment(let n): if !(ReferenceStore.data?.tools.contains { $0.name == n } ?? false) { bad.append("equipment \(n)") }
                case .molecule(let id): if !MoleculeLibrary.bundled.contains(where: { $0.id == id }) { bad.append("molecule") }
                case .screen: break
                }
            }
        }
        SelfTest.check(bad.isEmpty, "consistency: every ⌘K result points to a real element, term, tool, molecule or screen", "\(bad.prefix(3))")

        // ---- data consistency ----
        let els = ElementStore.all
        SelfTest.check(els.count == 118 && els.map(\.z) == Array(1...118), "data: 118 elements numbered 1 to 118 with no gaps")
        SelfTest.check(Set(els.map(\.symbol)).count == 118 && Set(els.map(\.name)).count == 118, "data: element symbols and names are all unique")
        var positions = Set<String>()
        for e in els { let p = e.gridPosition; positions.insert("\(p.row),\(p.col)") }
        SelfTest.check(positions.count == 118 && els.allSatisfy { $0.gridPosition.col >= 0 && $0.gridPosition.col < 18 }, "data: all 118 elements sit in different cells of the table")
        SelfTest.check(els.allSatisfy { $0.mass.map { $0 > 0 } ?? false } || els.filter { $0.mass == nil }.count <= 2, "data: every element has a mass (except at most two)", "\(els.filter { $0.mass == nil }.map(\.symbol))")
        let melt = els.filter { ($0.meltingPoint ?? 0) > ($0.boilingPoint ?? .infinity) }.map(\.symbol)
        SelfTest.check(melt.sorted() == ["As", "Bk"], "data: only arsenic and berkelium (which sublime) are listed above their boiling point", "\(melt)")
        let asEl = els.first { $0.symbol == "As" }!, fe = els.first { $0.symbol == "Fe" }!, hg = els.first { $0.symbol == "Hg" }!
        SelfTest.check(asEl.state(atKelvin: 300) == .solid && asEl.state(atKelvin: 1000) == .gas && fe.state(atKelvin: 300) == .solid && fe.state(atKelvin: 2000) == .liquid && fe.state(atKelvin: 4000) == .gas && hg.state(atKelvin: 298) == .liquid,
                       "data: state of matter is right for arsenic (sublimes), iron and mercury")
        var stateGaps: [String] = []
        for e in els { var last = e.state(atKelvin: 0); var seen: [MatterState] = [last]; for t in stride(from: 1.0, through: 6000, by: 25) { let s = e.state(atKelvin: t); if s != last { seen.append(s); last = s } }
            let order: [MatterState: Int] = [.solid: 0, .liquid: 1, .gas: 2, .unknown: -1]
            if seen.contains(.unknown) { continue }
            if zip(seen, seen.dropFirst()).contains(where: { order[$0]! >= order[$1]! }) { stateGaps.append(e.symbol) } }
        SelfTest.check(stateGaps.isEmpty, "data: every element goes solid → liquid → gas as it heats (never backwards)", "\(stateGaps)")
        let cfgBad = els.filter { e in ElectronConfiguration.subshells(e.configuration ?? "").reduce(0) { $0 + $1.electrons } != e.z }.map(\.symbol)
        SelfTest.check(cfgBad.isEmpty, "data: every electron configuration adds up to the atomic number", "\(cfgBad)")
        let isoBad = IsotopeStore.all.filter { $0.a < $0.z || $0.z < 1 || $0.z > 118 || ($0.abundance ?? 0) > 100 || ($0.halfLife ?? 1) <= 0 }
        SelfTest.check(isoBad.isEmpty, "data: all \(IsotopeStore.all.count) isotopes have sensible numbers", "\(isoBad.prefix(3).map { "\($0.z)-\($0.a)" })")
        var abundance: [Int: Double] = [:]
        for i in IsotopeStore.all { abundance[i.z, default: 0] += i.abundance ?? 0 }
        let abBad = abundance.filter { $0.value > 100.5 }.keys.sorted()
        SelfTest.check(abBad.isEmpty, "data: natural abundances never add up to more than 100%", "\(abBad)")
        let spBad = SpectrumStore.byElement.filter { $0.value.contains { !($0.wavelength > 0) || !($0.intensity > 0) } }.keys.sorted()
        SelfTest.check(spBad.isEmpty, "data: every spectral line has a positive wavelength and intensity", "\(spBad)")
        let ref = ReferenceStore.data!
        SelfTest.check(ref.glossary.allSatisfy { !$0.name.isEmpty && !$0.desc.isEmpty } && ref.tools.allSatisfy { !$0.desc.isEmpty }, "data: no glossary or equipment entry is empty")
        let missingPics = ref.tools.filter { !$0.picture.isEmpty && ReferenceStore.image($0.picture, in: "toolpics") == nil }.map(\.name)
        SelfTest.check(missingPics.isEmpty, "data: every lab-equipment picture loads", "\(missingPics)")
        let missingIcons = els.filter { ElementIcons.image($0.z) == nil }.map(\.symbol)
        SelfTest.check(missingIcons.isEmpty, "data: all 118 element icons load", "\(missingIcons)")
        let refs = ref.glossary.flatMap(\.refs).filter { r in !ref.glossary.contains { $0.name == r } }
        SelfTest.check(refs.isEmpty, "data: every glossary 'see also' link points to an existing term", "\(refs)")

        // ---- molecules: every bundled molecule through every analysis ----
        let mols = MoleculeLibrary.bundled
        SelfTest.check(mols.count == 19 && mols.allSatisfy { !$0.atoms.isEmpty }, "molecules: all 19 bundled molecules load")
        var molProblems: [String] = []
        for m in mols {
            let r = VBT.analyze(m)
            if r.atoms.count != m.atoms.count { molProblems.append("\(m.name): VBT count") }
            let o = MolecularOrbitals.analyze(m)
            for l in o.sigma + o.lonePairs where !(simd_length(l.direction) > 0.99 && simd_length(l.direction) < 1.01) { molProblems.append("\(m.name): orbital direction not unit") }
            if m.bonds.contains(where: { $0.a >= m.atoms.count || $0.b >= m.atoms.count }) { molProblems.append("\(m.name): bond index") }
            for f in MoleculeIO.Format.allCases {
                let text = MoleculeIO.export(m, as: f)
                let back: Molecule? = {
                    switch f { case .cml: return MoleculeIO.parseCML(text, fallbackName: "x"); case .mol: return MoleculeIO.parseMOL(text, fallbackName: "x"); case .xyz: return MoleculeIO.parseXYZ(text, fallbackName: "x") }
                }()
                guard let b = back else { molProblems.append("\(m.name): \(f) did not read back"); continue }
                if b.atoms.count != m.atoms.count { molProblems.append("\(m.name): \(f) atoms \(b.atoms.count) vs \(m.atoms.count)") }
                if f != .xyz && b.bonds.count != m.bonds.count { molProblems.append("\(m.name): \(f) bonds \(b.bonds.count) vs \(m.bonds.count)") }
                if zip(m.atoms, b.atoms).contains(where: { $0.symbol != $1.symbol || abs($0.x - $1.x) > 1e-3 }) { molProblems.append("\(m.name): \(f) coordinates changed") }
                if f == .mol, Molecule(name: "", atoms: b.atoms, bonds: b.bonds).formula != m.formula { molProblems.append("\(m.name): \(f) formula changed") }
            }
        }
        SelfTest.check(molProblems.isEmpty, "molecules: all 19 survive VBT, orbital placement and CML/MOL/XYZ save-and-reload", "\(molProblems.prefix(4))")

        // ---- editor: templates, 3D, formula agreement ----
        var edProblems: [String] = []
        for name in SketchTemplates.names {
            let sk = SketchTemplates.make(name, cx: 0, cy: 0)
            if !sk.problems.isEmpty { edProblems.append("\(name): valence problem") }
            let m = Embed3D.embed(sk, name: name)
            if m.formula != sk.formula && Molecule(name: "", atoms: m.atoms, bonds: m.bonds).formula != sk.formula { edProblems.append("\(name): 3D formula \(m.formula) vs \(sk.formula)") }
            if m.atoms.contains(where: { !$0.x.isFinite || !$0.y.isFinite || !$0.z.isFinite }) { edProblems.append("\(name): NaN coordinate"); continue }
            for b in m.bonds {
                let a = m.atoms[b.a], c = m.atoms[b.b]
                let d = sqrt(pow(a.x - c.x, 2) + pow(a.y - c.y, 2) + pow(a.z - c.z, 2))
                if d < 0.8 || d > 1.9 { edProblems.append("\(name): bond \(a.symbol)-\(c.symbol) is \(String(format: "%.2f", d)) Å") }
            }
            for i in 0..<m.atoms.count { for j in (i + 1)..<m.atoms.count {
                let a = m.atoms[i], c = m.atoms[j]
                if sqrt(pow(a.x - c.x, 2) + pow(a.y - c.y, 2) + pow(a.z - c.z, 2)) < 0.7 { edProblems.append("\(name): atoms \(i) and \(j) overlap") }
            } }
            if let parsed = FormulaParser.parse(sk.formula) {
                let mass = parsed.reduce(0) { $0 + $1.mass }
                if abs(mass - sk.mass) > 0.01 { edProblems.append("\(name): mass \(mass) vs \(sk.mass)") }
            } else { edProblems.append("\(name): formula '\(sk.formula)' does not parse") }
        }
        SelfTest.check(edProblems.isEmpty, "editor: all 12 templates have valid valences, sane 3D bond lengths, no overlapping atoms, and a formula/mass that the formula parser agrees with", "\(edProblems.prefix(4))")

        // random sketches: embedding must never crash or return NaN
        var nan = 0
        for _ in 0..<120 {
            var sk = Sketch()
            let n = Int.random(in: 1...9, using: &rng)
            for _ in 0..<n { sk.atoms.append(SketchAtom(symbol: ["C", "N", "O", "H", "S", "Cl", "P", "Br"].randomElement(using: &rng)!, x: Double.random(in: 0...300, using: &rng), y: Double.random(in: 0...300, using: &rng))) }
            for _ in 0..<Int.random(in: 0...(n * 2), using: &rng) {
                let a = sk.atoms.randomElement(using: &rng)!, b = sk.atoms.randomElement(using: &rng)!
                if a.id != b.id, !sk.bonds.contains(where: { ($0.a == a.id && $0.b == b.id) || ($0.a == b.id && $0.b == a.id) }) {
                    sk.bonds.append(SketchBond(a: a.id, b: b.id, order: Int.random(in: 1...3, using: &rng)))
                }
            }
            let m = Embed3D.embed(sk, name: "r")
            if m.atoms.contains(where: { !$0.x.isFinite || !$0.y.isFinite || !$0.z.isFinite }) { nan += 1 }
            _ = VBT.analyze(m); _ = MolecularOrbitals.analyze(m); _ = sk.formula; _ = sk.mass; _ = sk.problems
        }
        SelfTest.check(nan == 0, "editor: 120 random drawings (even nonsense ones) embed in 3D without NaN or a crash", "\(nan) bad")

        // ---- engines on every element ----
        var engProblems: [String] = []
        for e in els {
            let fill = FillState()
            if fill.verdict(for: e).complete { engProblems.append("\(e.symbol): empty fill complete") }
            var s = FillState()
            while let t = s.nextTarget(electrons: e.z) { _ = s.place(sub: t.sub, box: t.box, electrons: e.z, strictAufbau: true) }
            if s.total != e.z { engProblems.append("\(e.symbol): autofill \(s.total)/\(e.z)") }
            let v = s.verdict(for: e)
            let isException = Subshells.aufbau(e.z) != Subshells.actual(e)
            if v.matchesActual == isException { engProblems.append("\(e.symbol): verdict wrong (exception=\(isException))") }
        }
        SelfTest.check(engProblems.isEmpty, "filling: auto-fill works and is judged correctly for all 118 elements", "\(engProblems.prefix(4))")

        var qProblems: [String] = []
        for kind in QuizKind.allCases {
            var engine = QuizEngine(upTo: 118, kinds: [kind], stats: QuizStats(defaults: UserDefaults(suiteName: "xenon.test.fuzz")!))
            for _ in 0..<150 {
                let q = engine.next(using: &rng, kind: kind)
                if q.kind != .findOnTable && (q.options.count < 2 || q.correct >= q.options.count) { qProblems.append("\(kind) bad options") }
                if q.prompt.isEmpty || q.explanation.isEmpty { qProblems.append("\(kind) empty text") }
            }
        }
        UserDefaults(suiteName: "xenon.test.fuzz")!.removePersistentDomain(forName: "xenon.test.fuzz")
        SelfTest.check(qProblems.isEmpty, "quiz: 1,200 questions over all 118 elements are well-formed", "\(qProblems.prefix(3))")

        var spec: [String] = []
        for (z, lines) in SpectrumStore.byElement where lines.count >= 3 {
            let obs = lines.sorted { $0.intensity > $1.intensity }.prefix(4).map(\.nanometers)
            let ranked = SpectrumMatcher.rank(observed: Array(obs), tolerance: 0.3)
            if !ranked.prefix(3).contains(where: { $0.element.z == z }) { spec.append(ElementStore.all[z - 1].symbol) }
        }
        SelfTest.check(spec.count <= 3, "spectrum matcher: an element's own 4 strongest lines identify it (top 3) for all but ≤3 elements", "\(spec)")

        var unitProblems: [String] = []
        for _ in 0..<500 {
            let v = Double.random(in: -300...5000, using: &rng)
            for u in TemperatureUnit.allCases where abs(u.toKelvin(u.fromKelvin(v)) - v) > 1e-9 { unitProblems.append(u.rawValue) }
        }
        SelfTest.check(unitProblems.isEmpty, "settings: temperature conversion round-trips for 500 random values")

        let secs = Date().timeIntervalSince(t0)
        SelfTest.check(secs < 60, "fuzz: the whole robustness suite finished in under a minute", String(format: "%.1fs", secs))
    }
}
