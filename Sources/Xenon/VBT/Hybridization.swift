import Foundation

/// Valence bond theory for a single atom: given how many σ and π bonds it makes, work out lone pairs,
/// hybridization, VSEPR geometry, and the orbital-box diagram (ground state → hybridized).
struct Hybridization {
    let element: Element
    let valence: Int          // electrons the atom actually has (neutral valence minus formal charge)
    let charge: Int
    let sigma: Int
    let pi: Int
    let lonePairs: Int

    // MARK: construction

    /// Valence electrons of a main-group element; nil for transition metals and f-block.
    static func valenceElectrons(_ e: Element) -> Int? {
        if e.z == 2 { return 2 }
        let p = e.gridPosition
        guard p.row < 8 else { return nil }
        switch p.col {
        case 0, 1: return p.col + 1
        case 12...17: return p.col - 9
        default: return nil
        }
    }

    /// Principal quantum number of the valence shell.
    var shell: Int { element.gridPosition.row + 1 }

    /// nil when the bonding does not fit a neutral atom (an ion, a dative bond, or an impossible count).
    static func make(_ e: Element, sigma: Int, pi: Int, charge: Int = 0) -> Hybridization? {
        guard let v = valenceElectrons(e), sigma >= 0, pi >= 0 else { return nil }
        let have = v - charge
        let rest = have - sigma - pi           // electrons not used in bonds
        guard rest >= 0, rest % 2 == 0 else { return nil }
        // Second-period atoms cannot hold more than 8 electrons around them; heavier ones may expand to 12.
        let around = rest + 2 * (sigma + pi)
        guard around <= (e.gridPosition.row <= 1 ? 8 : 12) else { return nil }
        return Hybridization(element: e, valence: have, charge: charge, sigma: sigma, pi: pi, lonePairs: rest / 2)
    }

    /// Like `make`, but if the neutral atom cannot form these bonds it tries formal charges 0, +1, −1, +2, −2
    /// (carbon monoxide's C⁻ and O⁺, ammonium's N⁺ ...).
    static func makeAllowingCharge(_ e: Element, sigma: Int, pi: Int) -> Hybridization? {
        // Prefer a completed octet, then the smallest charge, then a negative charge before a positive one.
        let options = [0, -1, 1, -2, 2].compactMap { make(e, sigma: sigma, pi: pi, charge: $0) }
        func octetGap(_ h: Hybridization) -> Int {
            let around = 2 * h.lonePairs + 2 * (h.sigma + h.pi)
            return around >= 8 ? 0 : 8 - around
        }
        return options.min { (octetGap($0), abs($0.charge)) < (octetGap($1), abs($1.charge)) }
    }

    // MARK: geometry

    var steric: Int { sigma + lonePairs }

    var hybridName: String? {
        switch steric {
        case 2: return "sp"
        case 3: return "sp²"
        case 4: return "sp³"
        case 5: return "sp³d"
        case 6: return "sp³d²"
        case 7: return "sp³d³"
        default: return nil
        }
    }

    /// (s, p, d) orbitals mixed into the hybrid set.
    var mix: (s: Int, p: Int, d: Int) {
        switch steric {
        case 2: return (1, 1, 0)
        case 3: return (1, 2, 0)
        case 4: return (1, 3, 0)
        case 5: return (1, 3, 1)
        case 6: return (1, 3, 2)
        case 7: return (1, 3, 3)
        default: return (1, 0, 0)
        }
    }

    var electronGeometry: String? {
        ["linear", "trigonal planar", "tetrahedral", "trigonal bipyramidal", "octahedral", "pentagonal bipyramidal"][safe: steric - 2]
    }

    /// Molecular shape and the ideal bond angle for this combination of bonds and lone pairs.
    var shape: (name: String, angle: String)? {
        switch (steric, lonePairs) {
        case (2, 0): return ("linear", "180°")
        case (2, 1): return ("terminal atom (one neighbour)", "—")
        case (3, 2): return ("terminal atom (one neighbour)", "—")
        case (3, 0): return ("trigonal planar", "120°")
        case (3, 1): return ("bent", "<120°")
        case (4, 0): return ("tetrahedral", "109.5°")
        case (4, 1): return ("trigonal pyramidal", "<109.5° (≈107°)")
        case (4, 2): return ("bent", "<109.5° (≈104.5°)")
        case (4, 3): return ("linear (two atoms)", "—")
        case (5, 0): return ("trigonal bipyramidal", "90° and 120°")
        case (5, 1): return ("seesaw", "<90° and <120°")
        case (5, 2): return ("T-shaped", "<90°")
        case (5, 3): return ("linear", "180°")
        case (6, 0): return ("octahedral", "90°")
        case (6, 1): return ("square pyramidal", "<90°")
        case (6, 2): return ("square planar", "90°")
        case (7, 0): return ("pentagonal bipyramidal", "72° and 90°")
        default: return nil
        }
    }

    // MARK: orbital boxes

    enum BoxKind { case s, p, d, hybridLonePair, hybridBond, piP, piD }
    struct Box: Identifiable {
        let id = UUID()
        let label: String
        let electrons: Int      // 0, 1 or 2
        let kind: BoxKind
    }

    /// Valence orbitals of the free atom, filled by Hund's rule. Empty d boxes appear when d orbitals take part.
    var groundState: [Box] {
        let n = shell
        var boxes = [Box(label: "\(n)s", electrons: min(2, valence), kind: .s)]
        var left = max(0, valence - 2)
        var pCounts = [0, 0, 0]
        for i in 0..<3 where left > 0 { pCounts[i] = 1; left -= 1 }
        for i in 0..<3 where left > 0 { pCounts[i] += 1; left -= 1 }
        boxes += pCounts.map { Box(label: "\(n)p", electrons: $0, kind: .p) }
        boxes += (0..<mix.d).map { _ in Box(label: "\(n)d", electrons: 0, kind: .d) }
        return boxes
    }

    /// After mixing: hybrids hold the lone pairs and the σ bonds; leftover p (or d) orbitals hold the π bonds.
    var hybridized: [Box] {
        guard let name = hybridName else { return groundState }
        var boxes: [Box] = (0..<lonePairs).map { _ in Box(label: name, electrons: 2, kind: .hybridLonePair) }
        boxes += (0..<sigma).map { _ in Box(label: name, electrons: 1, kind: .hybridBond) }
        let pFree = max(0, 3 - mix.p)
        var piLeft = pi
        for _ in 0..<pFree {
            boxes.append(Box(label: "\(shell)p", electrons: piLeft > 0 ? 1 : 0, kind: .piP)); piLeft -= 1
        }
        while piLeft > 0 { boxes.append(Box(label: "\(shell)d", electrons: 1, kind: .piD)); piLeft -= 1 }
        return boxes
    }

    /// True when the ground-state electrons must be rearranged (promotion) to form the bonds.
    var needsPromotion: Bool {
        func unpaired(_ b: [Box]) -> Int { b.filter { $0.electrons == 1 }.count }
        return unpaired(groundState) != unpaired(hybridized) || mix.d > 0
    }

    var summary: String {
        "\(element.symbol)\(Hybridization.chargeText(charge)): \(sigma) σ, \(pi) π, \(lonePairs) lone pair\(lonePairs == 1 ? "" : "s")"
    }

    static func chargeText(_ c: Int) -> String {
        c == 0 ? "" : (abs(c) == 1 ? "" : "\(abs(c))") + (c > 0 ? "⁺" : "⁻")
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: whole molecules

enum VBT {
    struct AtomAnalysis: Identifiable {
        let index: Int
        let label: String            // C1, H3 ...
        let element: Element?
        let neighbors: [Int]
        let hybrid: Hybridization?   // nil for hydrogen and for atoms that need formal charges
        let note: String?
        let measuredAngles: [Double] // degrees between every pair of bonds at this atom
        var id: Int { index }
    }

    struct BondAnalysis: Identifiable {
        let id: Int
        let label: String
        let detail: String
    }

    static func analyze(_ m: Molecule) -> (atoms: [AtomAnalysis], bonds: [BondAnalysis]) {
        let bySymbol = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0) })
        var neighbors = [[Int]](repeating: [], count: m.atoms.count)
        var pi = [Int](repeating: 0, count: m.atoms.count)
        for b in m.bonds where b.a < m.atoms.count && b.b < m.atoms.count {
            neighbors[b.a].append(b.b); neighbors[b.b].append(b.a)
            pi[b.a] += b.order - 1; pi[b.b] += b.order - 1
        }
        var counts: [String: Int] = [:]
        let labels = m.atoms.map { a -> String in counts[a.symbol, default: 0] += 1; return "\(a.symbol)\(counts[a.symbol]!)" }

        let atoms = m.atoms.enumerated().map { i, a -> AtomAnalysis in
            let e = bySymbol[a.symbol]
            var hyb: Hybridization?
            var note: String?
            if let e, e.symbol != "H" {
                hyb = Hybridization.makeAllowingCharge(e, sigma: neighbors[i].count, pi: pi[i])
                if hyb == nil { note = "These bonds cannot be explained for a main-group atom, even with a formal charge." }
                else if let c = hyb?.charge, c != 0 { note = "Formal charge \(c > 0 ? "+" : "−")\(abs(c))." }
                else if hyb?.hybridName == nil { note = "Too few electron domains to hybridize." }
            }
            return AtomAnalysis(index: i, label: labels[i], element: e, neighbors: neighbors[i], hybrid: hyb, note: note,
                                measuredAngles: angles(at: i, in: m, neighbors: neighbors[i]))
        }

        func orbital(_ i: Int) -> String {
            if m.atoms[i].symbol == "H" { return "1s" }
            return atoms[i].hybrid?.hybridName ?? "?"
        }
        let bonds = m.bonds.enumerated().compactMap { k, b -> BondAnalysis? in
            guard b.a < m.atoms.count, b.b < m.atoms.count else { return nil }
            var parts = ["σ (\(orbital(b.a)) + \(orbital(b.b)))"]
            if b.order >= 2 {
                let n = atoms[b.a].hybrid.map { "\($0.shell)p" } ?? "p"
                parts += (1..<b.order).map { _ in "π (\(n) + \(atoms[b.b].hybrid.map { "\($0.shell)p" } ?? "p"))" }
            }
            return BondAnalysis(id: k, label: "\(labels[b.a]) – \(labels[b.b])", detail: parts.joined(separator: ", "))
        }
        return (atoms, bonds)
    }

    static func angles(at i: Int, in m: Molecule, neighbors: [Int]) -> [Double] {
        guard neighbors.count >= 2 else { return [] }
        let c = m.atoms[i]
        func vec(_ j: Int) -> (Double, Double, Double) { (m.atoms[j].x - c.x, m.atoms[j].y - c.y, m.atoms[j].z - c.z) }
        var out: [Double] = []
        for a in 0..<neighbors.count {
            for b in (a + 1)..<neighbors.count {
                let u = vec(neighbors[a]), v = vec(neighbors[b])
                let dot = u.0 * v.0 + u.1 * v.1 + u.2 * v.2
                let lu = sqrt(u.0 * u.0 + u.1 * u.1 + u.2 * u.2), lv = sqrt(v.0 * v.0 + v.1 * v.1 + v.2 * v.2)
                guard lu > 0, lv > 0 else { continue }
                out.append(acos(max(-1, min(1, dot / (lu * lv)))) * 180 / .pi)
            }
        }
        return out
    }
}

// MARK: self-test

enum VBTSelfTest {
    static func run() {
        let el = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0) })
        func h(_ sym: String, _ s: Int, _ p: Int = 0) -> Hybridization? { Hybridization.make(el[sym]!, sigma: s, pi: p) }
        func check(_ name: String, _ x: Hybridization?, hybrid: String, lp: Int, shape: String) {
            let ok = x?.hybridName == hybrid && x?.lonePairs == lp && x?.shape?.name == shape
            SelfTest.check(ok, "VBT \(name): \(hybrid), \(lp) LP, \(shape)", "got \(x?.hybridName ?? "nil"), \(x?.lonePairs ?? -1) LP, \(x?.shape?.name ?? "nil")")
        }
        check("CH4 (C)", h("C", 4), hybrid: "sp³", lp: 0, shape: "tetrahedral")
        check("NH3 (N)", h("N", 3), hybrid: "sp³", lp: 1, shape: "trigonal pyramidal")
        check("H2O (O)", h("O", 2), hybrid: "sp³", lp: 2, shape: "bent")
        check("BF3 (B)", h("B", 3), hybrid: "sp²", lp: 0, shape: "trigonal planar")
        check("BeCl2 (Be)", h("Be", 2), hybrid: "sp", lp: 0, shape: "linear")
        check("CO2 (C)", h("C", 2, 2), hybrid: "sp", lp: 0, shape: "linear")
        check("ethene (C)", h("C", 3, 1), hybrid: "sp²", lp: 0, shape: "trigonal planar")
        check("SO2 (S)", h("S", 2, 2), hybrid: "sp²", lp: 1, shape: "bent")
        check("SF4 (S)", h("S", 4), hybrid: "sp³d", lp: 1, shape: "seesaw")
        check("ClF3 (Cl)", h("Cl", 3), hybrid: "sp³d", lp: 2, shape: "T-shaped")
        check("PCl5 (P)", h("P", 5), hybrid: "sp³d", lp: 0, shape: "trigonal bipyramidal")
        check("SF6 (S)", h("S", 6), hybrid: "sp³d²", lp: 0, shape: "octahedral")
        check("XeF4 (Xe)", h("Xe", 4), hybrid: "sp³d²", lp: 2, shape: "square planar")
        SelfTest.check(h("C", 1, 2) == nil, "VBT a neutral carbon cannot make one σ and two π bonds")
        let cMinus = Hybridization.makeAllowingCharge(el["C"]!, sigma: 1, pi: 2), oPlus = Hybridization.makeAllowingCharge(el["O"]!, sigma: 1, pi: 2)
        SelfTest.check(cMinus?.charge == -1 && cMinus?.hybridName == "sp" && cMinus?.lonePairs == 1 && oPlus?.charge == 1 && oPlus?.hybridName == "sp" && oPlus?.lonePairs == 1,
                       "VBT carbon monoxide: C⁻ and O⁺, both sp with one lone pair", "\(String(describing: cMinus?.charge)) \(String(describing: oPlus?.charge))")
        let nPlus = Hybridization.makeAllowingCharge(el["N"]!, sigma: 4, pi: 0)
        SelfTest.check(nPlus?.charge == 1 && nPlus?.hybridName == "sp³" && nPlus?.lonePairs == 0, "VBT ammonium nitrogen is N⁺, sp³, no lone pair")
        SelfTest.check(Hybridization.makeAllowingCharge(el["C"]!, sigma: 4, pi: 0)?.charge == 0, "VBT ordinary atoms stay neutral")
        SelfTest.check(Hybridization.makeAllowingCharge(el["F"]!, sigma: 3, pi: 0) == nil || Hybridization.makeAllowingCharge(el["F"]!, sigma: 3, pi: 0)?.charge != 0, "VBT impossible neutral bonding is never reported as neutral")
        SelfTest.check(h("Fe", 2) == nil, "VBT transition metals are not covered")

        // electron bookkeeping: boxes always hold exactly the valence electrons
        let all = [h("C", 4), h("N", 3), h("O", 2), h("S", 6), h("Xe", 4), h("C", 2, 2), h("Cl", 3)].compactMap { $0 }
        SelfTest.check(all.allSatisfy { $0.hybridized.reduce(0) { $0 + $1.electrons } == $0.valence && $0.groundState.reduce(0) { $0 + $1.electrons } == $0.valence },
                       "VBT orbital boxes hold exactly the valence electrons")
        SelfTest.check(h("C", 4)?.needsPromotion == true && h("N", 3)?.needsPromotion == false, "VBT carbon needs promotion, nitrogen does not",
                       "C \(String(describing: h("C", 4)?.needsPromotion)) N \(String(describing: h("N", 3)?.needsPromotion))")

        // whole molecules from the bundled library, including measured angles
        func mol(_ name: String) -> Molecule? { MoleculeLibrary.bundled.first { $0.name.lowercased().contains(name) } }
        if let m = mol("methane") {
            let a = VBT.analyze(m).atoms.first { $0.element?.symbol == "C" }
            let ang = a?.measuredAngles ?? []
            SelfTest.check(a?.hybrid?.hybridName == "sp³" && !ang.isEmpty && ang.allSatisfy { abs($0 - 109.5) < 2 }, "VBT methane: sp³ with ≈109.5° bond angles", "\(String(describing: a?.hybrid?.hybridName)) \(ang)")
        } else { SelfTest.check(false, "VBT methane found in library") }
        if let m = mol("water") {
            let a = VBT.analyze(m).atoms.first { $0.element?.symbol == "O" }
            SelfTest.check(a?.hybrid?.shape?.name == "bent" && abs((a?.measuredAngles.first ?? 0) - 104.5) < 3, "VBT water: bent, ≈104.5°", "\(String(describing: a?.hybrid?.shape?.name)) \(a?.measuredAngles ?? [])")
        } else { SelfTest.check(false, "VBT water found in library") }
        if let m = mol("carbon,dioxide") ?? mol("carbon dioxide") {
            let r = VBT.analyze(m)
            let c = r.atoms.first { $0.element?.symbol == "C" }
            SelfTest.check(c?.hybrid?.hybridName == "sp" && r.bonds.allSatisfy { $0.detail.contains("π") }, "VBT CO2: sp carbon, every bond has a π component", "\(String(describing: c?.hybrid?.hybridName)) \(r.bonds.map(\.detail))")
        } else { SelfTest.check(false, "VBT carbon dioxide found in library") }
        if let m = mol("ethanol") {
            let r = VBT.analyze(m)
            SelfTest.check(r.atoms.filter { $0.element?.symbol != "H" }.allSatisfy { $0.hybrid?.hybridName == "sp³" }, "VBT ethanol: every C and O is sp³")
        } else { SelfTest.check(false, "VBT ethanol found in library") }
    }
}
