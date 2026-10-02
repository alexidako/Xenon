import SwiftUI

/// Lewis structures with formal charges, and resonance: every bond-order pattern on a fixed skeleton that has the lowest
/// formal-charge cost is a valid resonance structure.
struct ResonanceInput {
    struct Atom { let symbol: String; let x: Double; let y: Double }
    let name: String
    let formula: String
    let atoms: [Atom]
    let bonds: [(Int, Int)]
    let charge: Int
}

struct LewisStructure: Identifiable {
    let id = UUID()
    let orders: [Int]          // per bond
    let lonePairs: [Int]       // per atom
    let charges: [Int]         // formal charge per atom
    let cost: Double
}

enum Resonance {
    private static let bySymbol = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0) })

    static func valence(_ e: Element) -> Int? { Hybridization.valenceElectrons(e) }

    /// All lowest-cost Lewis structures, or nil if the electrons cannot be arranged or the molecule is too big.
    static func structures(_ input: ResonanceInput, maxBonds: Int = 9) -> [LewisStructure]? {
        let atoms = input.atoms.compactMap { bySymbol[$0.symbol] }
        guard atoms.count == input.atoms.count, atoms.allSatisfy({ valence($0) != nil }) else { return nil }
        let n = atoms.count
        let isH = atoms.map { $0.symbol == "H" }
        let flexible = input.bonds.indices.filter { !(isH[input.bonds[$0].0] || isH[input.bonds[$0].1]) }
        guard flexible.count <= maxBonds else { return nil }
        let totalValence = atoms.reduce(0) { $0 + valence($1)! } - input.charge

        var best = Double.infinity
        var kept: [LewisStructure] = []
        let combos = Int(pow(3.0, Double(flexible.count)))
        for code in 0..<max(combos, 1) {
            var orders = [Int](repeating: 1, count: input.bonds.count)
            var c = code
            for i in flexible { orders[i] = c % 3 + 1; c /= 3 }

            var s = [Int](repeating: 0, count: n)
            for (i, b) in input.bonds.enumerated() { s[b.0] += orders[i]; s[b.1] += orders[i] }
            let bondElectrons = s.reduce(0, +)
            let lpTotal2 = totalValence - bondElectrons
            guard lpTotal2 >= 0, lpTotal2 % 2 == 0 else { continue }
            let lpTotal = lpTotal2 / 2

            // choices per atom: (lone pairs, cost)
            var choices: [[(lp: Int, cost: Double)]] = []
            var feasible = true
            for a in 0..<n {
                let e = atoms[a], v = valence(e)!, period = e.gridPosition.row
                var opts: [(Int, Double)] = []
                if isH[a] {
                    if s[a] == 1 { opts = [(0, 0)] }
                } else {
                    let maxElectrons = period >= 2 ? 12 : 8
                    for lp in 0...6 where 2 * lp + 2 * s[a] <= maxElectrons {
                        let fc = v - 2 * lp - s[a], electrons = 2 * lp + 2 * s[a]
                        var cost = Double(abs(fc)) + 0.05 * Double(fc) * (e.electronegativity ?? 2)
                        if electrons < 8 { cost += ["B", "Be", "Al"].contains(e.symbol) ? 0.2 : 3.0 * Double((8 - electrons) / 2) }
                        if electrons > 8 { cost += 0.02 * Double((electrons - 8) / 2) }
                        opts.append((lp, cost))
                    }
                }
                if opts.isEmpty { feasible = false; break }
                choices.append(opts.map { (lp: $0.0, cost: $0.1) })
            }
            guard feasible else { continue }

            // distribute exactly lpTotal lone pairs over the atoms at minimum cost
            var dp = [[Double]](repeating: [Double](repeating: .infinity, count: lpTotal + 1), count: n + 1)
            var pick = [[Int]](repeating: [Int](repeating: -1, count: lpTotal + 1), count: n + 1)
            dp[0][0] = 0
            for a in 0..<n {
                for used in 0...lpTotal where dp[a][used].isFinite {
                    for (k, o) in choices[a].enumerated() where used + o.lp <= lpTotal {
                        let v = dp[a][used] + o.cost
                        if v < dp[a + 1][used + o.lp] - 1e-12 { dp[a + 1][used + o.lp] = v; pick[a + 1][used + o.lp] = k }
                    }
                }
            }
            let cost = dp[n][lpTotal]
            guard cost.isFinite, cost <= best + 1e-9 else { continue }
            var lps = [Int](repeating: 0, count: n), used = lpTotal
            for a in stride(from: n, to: 0, by: -1) { let o = choices[a - 1][pick[a][used]]; lps[a - 1] = o.lp; used -= o.lp }
            let charges = (0..<n).map { valence(atoms[$0])! - 2 * lps[$0] - s[$0] }
            if cost < best - 1e-9 { best = cost; kept = [] }
            kept.append(LewisStructure(orders: orders, lonePairs: lps, charges: charges, cost: cost))
        }
        return kept.isEmpty ? nil : kept
    }

    /// Average bond order over the structures, e.g. 1.33 for each N–O bond in nitrate.
    static func hybridOrders(_ structures: [LewisStructure]) -> [Double] {
        guard let first = structures.first else { return [] }
        return first.orders.indices.map { i in Double(structures.reduce(0) { $0 + $1.orders[i] }) / Double(structures.count) }
    }

    static func averageCharges(_ structures: [LewisStructure]) -> [Double] {
        guard let first = structures.first else { return [] }
        return first.charges.indices.map { i in Double(structures.reduce(0) { $0 + $1.charges[i] }) / Double(structures.count) }
    }

    // MARK: presets

    private static func ring(_ n: Int, radius: Double, offset: Double = -90) -> [(Double, Double)] {
        (0..<n).map { k in let t = (offset + Double(k) * 360 / Double(n)) * .pi / 180; return (radius * cos(t), radius * sin(t)) }
    }

    static let presets: [ResonanceInput] = {
        func a(_ s: String, _ p: (Double, Double)) -> ResonanceInput.Atom { .init(symbol: s, x: p.0, y: p.1) }
        func star(_ centre: String, _ outer: [String], charge: Int, name: String, formula: String) -> ResonanceInput {
            let pts = ring(outer.count, radius: 1)
            return ResonanceInput(name: name, formula: formula, atoms: [a(centre, (0, 0))] + zip(outer, pts).map { a($0, $1) },
                                  bonds: outer.indices.map { (0, $0 + 1) }, charge: charge)
        }
        let benz = ring(6, radius: 1)
        let benzH = ring(6, radius: 1.9)
        return [
            ResonanceInput(name: "Ozone", formula: "O₃", atoms: [a("O", (-1, 0.55)), a("O", (0, 0)), a("O", (1, 0.55))], bonds: [(0, 1), (1, 2)], charge: 0),
            star("N", ["O", "O", "O"], charge: -1, name: "Nitrate", formula: "NO₃⁻"),
            star("C", ["O", "O", "O"], charge: -2, name: "Carbonate", formula: "CO₃²⁻"),
            ResonanceInput(name: "Nitrite", formula: "NO₂⁻", atoms: [a("O", (-1, 0.55)), a("N", (0, 0)), a("O", (1, 0.55))], bonds: [(0, 1), (1, 2)], charge: -1),
            ResonanceInput(name: "Sulfur dioxide", formula: "SO₂", atoms: [a("O", (-1, 0.55)), a("S", (0, 0)), a("O", (1, 0.55))], bonds: [(0, 1), (1, 2)], charge: 0),
            ResonanceInput(name: "Carbon monoxide", formula: "CO", atoms: [a("C", (-0.6, 0)), a("O", (0.6, 0))], bonds: [(0, 1)], charge: 0),
            ResonanceInput(name: "Formate", formula: "HCO₂⁻", atoms: [a("C", (0, 0)), a("O", (-1, 0.8)), a("O", (1, 0.8)), a("H", (0, -1))], bonds: [(0, 1), (0, 2), (0, 3)], charge: -1),
            ResonanceInput(name: "Acetate", formula: "CH₃CO₂⁻",
                           atoms: [a("C", (0, 0)), a("O", (-1, 0.8)), a("O", (1, 0.8)), a("C", (0, -1.1)), a("H", (-0.9, -1.6)), a("H", (0, -2.1)), a("H", (0.9, -1.6))],
                           bonds: [(0, 1), (0, 2), (0, 3), (3, 4), (3, 5), (3, 6)], charge: -1),
            star("S", ["O", "O", "O", "O"], charge: -2, name: "Sulfate", formula: "SO₄²⁻"),
            ResonanceInput(name: "Benzene", formula: "C₆H₆", atoms: benz.map { a("C", $0) } + benzH.map { a("H", $0) },
                           bonds: (0..<6).map { ($0, ($0 + 1) % 6) } + (0..<6).map { ($0, $0 + 6) }, charge: 0),
            ResonanceInput(name: "Ammonium", formula: "NH₄⁺", atoms: [a("N", (0, 0))] + ring(4, radius: 1).map { a("H", $0) }, bonds: (1...4).map { (0, $0) }, charge: 1),
            ResonanceInput(name: "Hydronium", formula: "H₃O⁺", atoms: [a("O", (0, 0))] + ring(3, radius: 1).map { a("H", $0) }, bonds: (1...3).map { (0, $0) }, charge: 1),
        ]
    }()
}

@MainActor enum ResonanceSelfTest {
    static func run() {
        func preset(_ n: String) -> ResonanceInput { Resonance.presets.first { $0.name == n }! }
        func run(_ n: String) -> [LewisStructure] { Resonance.structures(preset(n)) ?? [] }
        func fmt(_ s: LewisStructure) -> String { "\(s.orders) fc \(s.charges)" }

        let o3 = run("Ozone")
        SelfTest.check(o3.count == 2 && o3.allSatisfy { $0.orders.sorted() == [1, 2] && $0.charges.sorted() == [-1, 0, 1] }, "resonance: ozone has 2 structures (O=O⁺–O⁻ and its mirror)", "\(o3.map(fmt))")
        let no3 = run("Nitrate")
        SelfTest.check(no3.count == 3 && no3.allSatisfy { $0.orders.sorted() == [1, 1, 2] && $0.charges[0] == 1 && $0.charges.reduce(0, +) == -1 }, "resonance: nitrate has 3 structures, N is +1 and the charges sum to −1", "\(no3.map(fmt))")
        let orders = Resonance.hybridOrders(no3)
        SelfTest.check(orders.allSatisfy { abs($0 - 4.0 / 3) < 1e-9 }, "resonance: every N–O bond in nitrate averages 1.33", "\(orders)")
        let avg = Resonance.averageCharges(no3)
        SelfTest.check(avg[0] == 1 && avg[1...].allSatisfy { abs($0 + 2.0 / 3) < 1e-9 }, "resonance: each nitrate oxygen carries −2/3 on average", "\(avg)")
        let co3 = run("Carbonate")
        SelfTest.check(co3.count == 3 && co3.allSatisfy { $0.charges[0] == 0 && $0.charges.reduce(0, +) == -2 }, "resonance: carbonate has 3 structures with neutral carbon", "\(co3.map(fmt))")
        let co = run("Carbon monoxide")
        SelfTest.check(co.count == 1 && co[0].orders == [3] && co[0].charges == [-1, 1], "resonance: carbon monoxide is C≡O with C⁻ and O⁺", "\(co.map(fmt))")
        let so4 = run("Sulfate")
        SelfTest.check(so4.count == 6 && so4.allSatisfy { $0.orders.filter { $0 == 2 }.count == 2 && $0.charges[0] == 0 }, "resonance: sulfate has 6 structures with two S=O bonds and neutral sulfur", "\(so4.count) \(so4.first.map(fmt) ?? "")")
        let so2 = run("Sulfur dioxide")
        SelfTest.check(so2.count == 1 && so2[0].orders == [2, 2] && so2[0].charges == [0, 0, 0], "resonance: sulfur dioxide is O=S=O with no formal charges", "\(so2.map(fmt))")
        let benz = run("Benzene")
        SelfTest.check(benz.count == 2 && benz.allSatisfy { Array($0.orders.prefix(6)).sorted() == [1, 1, 1, 2, 2, 2] } && Resonance.hybridOrders(benz).prefix(6).allSatisfy { abs($0 - 1.5) < 1e-9 },
                       "resonance: benzene has 2 Kekulé structures averaging 1.5", "\(benz.count) \(Resonance.hybridOrders(benz).prefix(6))")
        let acetate = run("Acetate")
        SelfTest.check(acetate.count == 2 && Resonance.hybridOrders(acetate)[0...1].allSatisfy { abs($0 - 1.5) < 1e-9 }, "resonance: acetate's two C–O bonds average 1.5", "\(acetate.count)")
        let nh4 = run("Ammonium")
        SelfTest.check(nh4.count == 1 && nh4[0].charges[0] == 1 && nh4[0].lonePairs[0] == 0, "resonance: ammonium is N⁺ with no lone pair", "\(nh4.map(fmt))")
        let h3o = run("Hydronium")
        SelfTest.check(h3o.count == 1 && h3o[0].charges[0] == 1 && h3o[0].lonePairs[0] == 1, "resonance: hydronium is O⁺ with one lone pair", "\(h3o.map(fmt))")
        for p in Resonance.presets {
            guard let ss = Resonance.structures(p) else { SelfTest.check(false, "resonance: \(p.name) solvable"); continue }
            let total = ss.allSatisfy { $0.charges.reduce(0, +) == p.charge }
            if !total { SelfTest.check(false, "resonance: \(p.name) charges sum to \(p.charge)", "\(ss.map(fmt))") }
        }
        SelfTest.check(Resonance.presets.allSatisfy { p in (Resonance.structures(p) ?? []).allSatisfy { s in
            s.lonePairs.indices.allSatisfy { i in
                let e = ElementStore.all.first { $0.symbol == p.atoms[i].symbol }!
                let bonds = p.bonds.indices.filter { p.bonds[$0].0 == i || p.bonds[$0].1 == i }.reduce(0) { $0 + s.orders[$1] }
                return e.symbol == "H" ? (bonds == 1) : (2 * s.lonePairs[i] + 2 * bonds <= 12)
            } } }, "resonance: every preset obeys the octet limits and hydrogen keeps one bond")
        let impossible = ResonanceInput(name: "x", formula: "x", atoms: [.init(symbol: "Fe", x: 0, y: 0)], bonds: [], charge: 0)
        SelfTest.check(Resonance.structures(impossible) == nil, "resonance: transition metals are refused rather than guessed")
        let odd = ResonanceInput(name: "NO2", formula: "NO₂", atoms: [.init(symbol: "O", x: 0, y: 0), .init(symbol: "N", x: 1, y: 0), .init(symbol: "O", x: 2, y: 0)], bonds: [(0, 1), (1, 2)], charge: 0)
        SelfTest.check(Resonance.structures(odd) == nil, "resonance: an odd number of electrons (NO₂ radical) is refused")
    }
}
