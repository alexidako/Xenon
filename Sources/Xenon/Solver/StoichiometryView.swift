import SwiftUI

/// Limiting reagent, leftover and yield for a balanced equation, with every step shown.
struct StoichiometryView: View {
    let equation: String

    @State private var amounts: [Int: String] = {
        // Test hook: XENON_STOICH="10,30" pre-fills the reactant amounts in order.
        let parts = (ProcessInfo.processInfo.environment["XENON_STOICH"] ?? "").split(separator: ",").map(String.init)
        return Dictionary(uniqueKeysWithValues: parts.enumerated().map { ($0.offset, $0.element) })
    }()
    @State private var units: [Int: Stoichiometry.Unit] = [:]
    @State private var actualProduct = 0
    @State private var actualGrams = ""
    @State private var showSteps = true

    private let masses = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0.mass ?? 0) })

    private var balanced: Result<EquationSolver.Balanced, EquationSolver.Failure> {
        let known = Set(masses.keys)
        return EquationSolver.solveStructured(equation, isElement: { known.contains($0) })
    }

    private func parsed(_ s: String?) -> Double? { s.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } }

    var body: some View {
        switch balanced {
        case .failure(let f):
            Form {
                Section {
                    Label(f == .notFound ? tr("This equation can't be balanced with whole numbers.") : tr("Fix the equation on the Balance tab first."),
                          systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }.formStyle(.grouped)
        case .success(let b):
            content(b)
        }
    }

    @ViewBuilder private func content(_ b: EquationSolver.Balanced) -> some View {
        let species = Stoichiometry.species(from: b, mass: { masses[$0] })
        let reactants = species.filter(\.isReactant), products = species.filter { !$0.isReactant }
        let given: [Int: (Double, Stoichiometry.Unit)] = Dictionary(uniqueKeysWithValues: reactants.compactMap { r in
            parsed(amounts[r.id]).map { (r.id, ($0, units[r.id] ?? .g)) }
        })
        let outcome = Stoichiometry.solve(species, amounts: given)

        Form {
            Section("Balanced equation") {
                Text(Markup.formulaText(species.filter(\.isReactant).map(label).joined(separator: " + ") + "  →  " + products.map(label).joined(separator: " + ")))
                    .font(.title3.monospaced()).textSelection(.enabled)
            }
            Section("Amounts you have (leave blank for “plenty”)") {
                ForEach(reactants) { r in
                    LabeledContent {
                        HStack {
                            TextField("", text: Binding(get: { amounts[r.id] ?? "" }, set: { amounts[r.id] = $0 }), prompt: Text("amount"))
                                .multilineTextAlignment(.trailing).frame(width: 110).textFieldStyle(.roundedBorder)
                            Picker("", selection: Binding(get: { units[r.id] ?? .g }, set: { units[r.id] = $0 })) {
                                ForEach(Stoichiometry.Unit.allCases) { Text(trc("unit", $0.rawValue)).tag($0) }
                            }.labelsHidden().frame(width: 80)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(Markup.formulaText(r.formula)).font(.body.monospaced())
                            Text(tr("{value} g/mol", ["value": formatNumber(r.molarMass)])).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let o = outcome {
                Section("Result") {
                    LabeledContent("Limiting reagent") {
                        Text(Markup.formulaText(o.limiting?.formula ?? "—")).font(.title3.monospaced().bold()).foregroundStyle(.orange)
                    }
                    ForEach(o.excess, id: \.species.id) { l in
                        LabeledContent(tr("Left over: {formula}", ["formula": Markup.formulaText(l.species.formula)])) {
                            Text(tr("{g} g ({mol} mol)", ["g": formatNumber(l.grams), "mol": formatNumber(l.moles)])).monospacedDigit()
                        }
                    }
                    ForEach(o.products, id: \.species.id) { l in
                        LabeledContent(tr("Theoretical yield: {formula}", ["formula": Markup.formulaText(l.species.formula)])) {
                            Text(tr("{g} g ({mol} mol)", ["g": formatNumber(l.grams), "mol": formatNumber(l.moles)])).monospacedDigit().fontWeight(.semibold)
                        }
                    }
                }
                Section("Percent yield") {
                    Picker("Product", selection: $actualProduct) {
                        ForEach(Array(products.enumerated()), id: \.offset) { i, p in Text(Markup.formulaText(p.formula)).tag(i) }
                    }
                    LabeledContent("Actual yield (g)") {
                        TextField("", text: $actualGrams, prompt: Text("grams collected")).multilineTextAlignment(.trailing)
                            .frame(width: 140).textFieldStyle(.roundedBorder)
                    }
                    if let actual = parsed(actualGrams), actualProduct < o.products.count, o.products[actualProduct].grams > 0 {
                        let theory = o.products[actualProduct].grams
                        LabeledContent("Percent yield") {
                            Text("\(formatNumber(actual / theory * 100)) %").font(.title3.monospacedDigit().bold())
                        }
                        Text(tr("{actual} g ÷ {theory} g × 100", ["actual": formatNumber(actual), "theory": formatNumber(theory)])).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    DisclosureGroup("Show the steps", isExpanded: $showSteps) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(o.steps.enumerated()), id: \.offset) { i, s in
                                Text("\(i + 1). \(Markup.formulaText(s))").font(.callout.monospaced()).textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                }
            } else {
                Section { Text("Enter the amount of at least one reactant to see the limiting reagent and yields.").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private func label(_ s: Stoichiometry.Species) -> String { (s.coefficient == 1 ? "" : "\(s.coefficient) ") + s.formula }
}
