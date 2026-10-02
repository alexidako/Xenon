import Foundation

/// Limiting-reagent and yield calculations for a balanced equation.
enum Stoichiometry {
    struct Species: Identifiable {
        let id: Int
        let formula: String
        let coefficient: Int
        let molarMass: Double
        let isReactant: Bool
    }

    struct Line {
        var species: Species
        var moles: Double
        var grams: Double
        var note: String
    }

    struct Outcome {
        var limiting: Species?
        var reactants: [Line]      // amounts consumed
        var excess: [Line]         // amounts left over
        var products: [Line]       // theoretical yield
        var steps: [String]
    }

    enum Unit: String, CaseIterable, Identifiable {
        case g, mg, kg, mol, mmol
        var id: String { rawValue }
        func toMoles(_ v: Double, molarMass m: Double) -> Double {
            switch self {
            case .g: return v / m
            case .mg: return v / 1000 / m
            case .kg: return v * 1000 / m
            case .mol: return v
            case .mmol: return v / 1000
            }
        }
    }

    static func species(from b: EquationSolver.Balanced, mass: (String) -> Double?) -> [Species] {
        var out: [Species] = []
        for (i, e) in (b.left + b.right).enumerated() {
            let m = e.term.atoms.reduce(0.0) { $0 + (mass($1.key) ?? 0) * Double($1.value) }
            out.append(Species(id: i, formula: e.term.text, coefficient: e.coefficient, molarMass: m, isReactant: i < b.left.count))
        }
        return out
    }

    /// `amounts` maps species id → (value, unit) for reactants. Reactants left out are assumed to be in excess.
    static func solve(_ all: [Species], amounts: [Int: (Double, Unit)]) -> Outcome? {
        let reactants = all.filter(\.isReactant), products = all.filter { !$0.isReactant }
        var ratios: [(Species, Double, Double)] = []   // species, moles, moles / coefficient
        var steps: [String] = []
        for r in reactants {
            guard let (v, u) = amounts[r.id], v > 0, r.molarMass > 0 else { continue }
            let n = u.toMoles(v, molarMass: r.molarMass)
            ratios.append((r, n, n / Double(r.coefficient)))
            let fmt = { (x: Double) in formatNumber(x) }
            if u == .mol || u == .mmol {
                steps.append("\(r.formula): \(fmt(v)) \(u.rawValue) = \(fmt(n)) mol; \(fmt(n)) ÷ \(r.coefficient) = \(fmt(n / Double(r.coefficient)))")
            } else {
                steps.append("\(r.formula): \(fmt(v)) \(u.rawValue) ÷ \(fmt(r.molarMass)) g/mol = \(fmt(n)) mol; ÷ \(r.coefficient) = \(fmt(n / Double(r.coefficient)))")
            }
        }
        guard let limit = ratios.min(by: { $0.2 < $1.2 }) else { return nil }
        let extent = limit.2     // moles of "reaction"
        steps.append("Limiting reagent: \(limit.0.formula) (smallest moles ÷ coefficient = \(formatNumber(extent)))")

        func line(_ s: Species, _ n: Double, _ note: String) -> Line { Line(species: s, moles: n, grams: n * s.molarMass, note: note) }
        let used = ratios.map { line($0.0, extent * Double($0.0.coefficient), "consumed") }
        let excess = ratios.filter { $0.0.id != limit.0.id }.map { line($0.0, $0.1 - extent * Double($0.0.coefficient), "left over") }
        let prod = products.map { line($0, extent * Double($0.coefficient), "theoretical") }
        for p in prod {
            steps.append("\(p.species.formula): \(formatNumber(extent)) × \(p.species.coefficient) = \(formatNumber(p.moles)) mol × \(formatNumber(p.species.molarMass)) g/mol = \(formatNumber(p.grams)) g")
        }
        return Outcome(limiting: limit.0, reactants: used, excess: excess, products: prod, steps: steps)
    }
}

enum StoichSelfTest {
    static func run() {
        let masses = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0.mass ?? 0) })
        func setup(_ eq: String) -> (EquationSolver.Balanced, [Stoichiometry.Species])? {
            let known = Set(masses.keys)
            guard case .success(let b) = EquationSolver.solveStructured(eq, isElement: { known.contains($0) }) else { return nil }
            return (b, Stoichiometry.species(from: b, mass: { masses[$0] }))
        }
        guard let (_, sp) = setup("aH2 + bO2 -> cH2O") else { SelfTest.check(false, "stoichiometry: balance 2H2 + O2 -> 2H2O"); return }
        SelfTest.check(sp.map(\.coefficient) == [2, 1, 2], "balance H2 + O2 -> H2O", "\(sp.map(\.coefficient))")
        // 4.0 g H2 + 32.0 g O2: H2 = 1.984 mol (ratio 0.992), O2 = 1.000 mol (ratio 1.000) -> H2 limits
        let h2 = sp[0], o2 = sp[1]
        let out = Stoichiometry.solve(sp, amounts: [h2.id: (4.0, .g), o2.id: (32.0, .g)])
        SelfTest.check(out?.limiting?.formula == "H2", "limiting reagent is H2", out?.limiting?.formula ?? "nil")
        let water = out?.products.first?.grams ?? 0
        SelfTest.check(abs(water - 35.74) < 0.05, "theoretical water yield ≈ 35.74 g", "\(water)")
        let leftO2 = out?.excess.first?.grams ?? 0
        SelfTest.check(abs(leftO2 - (32.0 - (4.0 / 2.01588 / 2) * 31.9988)) < 0.05, "leftover O2 mass", "\(leftO2)")
        // limiting reagent flips when O2 is scarce
        let out2 = Stoichiometry.solve(sp, amounts: [h2.id: (4.0, .g), o2.id: (8.0, .g)])
        SelfTest.check(out2?.limiting?.formula == "O2", "limiting reagent flips to O2", out2?.limiting?.formula ?? "nil")
        // one reactant only: everything else is in excess
        let out3 = Stoichiometry.solve(sp, amounts: [o2.id: (1.0, .mol)])
        SelfTest.check(abs((out3?.products.first?.moles ?? 0) - 2.0) < 1e-9, "1 mol O2 gives 2 mol H2O", "\(out3?.products.first?.moles ?? -1)")
        if let (_, e) = setup("aCH3CH2OH + bO2 -> cH2O + dCO2") {
            let r = Stoichiometry.solve(e, amounts: [e[0].id: (10.0, .g)])
            let co2 = r?.products.last?.grams ?? 0
            SelfTest.check(abs(co2 - 19.1) < 0.1, "10 g ethanol burns to ≈ 19.1 g CO2", "\(co2)")
        } else { SelfTest.check(false, "ethanol combustion balances") }
    }
}
