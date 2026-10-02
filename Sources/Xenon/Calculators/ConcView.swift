import SwiftUI

/// Solution concentration: amounts of solute and solvent → all common concentration units,
/// or a target concentration → required amount of solute.
struct ConcView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case concentration = "Find concentration", solute = "Find amount of solute"
        var id: String { rawValue }
    }
    enum SoluteKind: String, CaseIterable, Identifiable { case mass = "Mass (g)", volume = "Volume (L)", moles = "Moles"; var id: String { rawValue } }
    enum SolventKind: String, CaseIterable, Identifiable { case volume = "Volume (L)", mass = "Mass (g)", moles = "Moles"; var id: String { rawValue } }
    enum ConcKind: String, CaseIterable, Identifiable {
        case molar = "Molarity (mol/L)", normal = "Normality (eq/L)", molal = "Molality (mol/kg)"
        case massPct = "% (mass)", volPct = "% (volume)", molePct = "% (moles)"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .concentration
    @State private var soluteKind: SoluteKind = .mass
    @State private var soluteAmount = 117.0
    @State private var molarMass = 58.5
    @State private var eqMass = 58.5
    @State private var soluteDensity = 2.17      // g/mL
    @State private var solventKind: SolventKind = .volume
    @State private var solventAmount = 1.0
    @State private var solventMolarMass = 18.015
    @State private var solventDensity = 1.0      // g/mL
    @State private var targetKind: ConcKind = .molar
    @State private var target = 2.0

    // MARK: derived amounts

    private var solventMass: Double {
        switch solventKind {
        case .mass: return solventAmount
        case .volume: return solventAmount * solventDensity * 1000
        case .moles: return solventAmount * solventMolarMass
        }
    }
    private var solventVolume: Double { solventMass / (solventDensity * 1000) }   // litres
    private var solventMoles: Double { solventMass / solventMolarMass }

    private func soluteMass(from v: Double, kind: SoluteKind) -> Double {
        switch kind {
        case .mass: return v
        case .volume: return v * 1000 * soluteDensity
        case .moles: return v * molarMass
        }
    }
    private var soluteMassG: Double { soluteMass(from: soluteAmount, kind: soluteKind) }
    private var soluteMoles: Double { soluteMassG / molarMass }
    private var soluteEquivalents: Double { soluteMassG / eqMass }
    private var soluteVolume: Double { soluteMassG / (soluteDensity * 1000) }

    private var computed: [(ConcKind, Double)] {
        [(.molar, soluteMoles / solventVolume),
         (.normal, soluteEquivalents / solventVolume),
         (.molal, soluteMoles * 1000 / solventMass),
         (.massPct, soluteMassG / (soluteMassG + solventMass) * 100),
         (.volPct, soluteVolume / (soluteVolume + solventVolume) * 100),
         (.molePct, soluteMoles / (soluteMoles + solventMoles) * 100)]
    }

    /// Grams of solute that give the target concentration with the given solvent.
    private var requiredSoluteMass: Double? {
        let c = target
        switch targetKind {
        case .molar: return c * solventVolume * molarMass
        case .normal: return c * solventVolume * eqMass
        case .molal: return c * solventMass / 1000 * molarMass
        case .massPct: return c < 100 ? c / (100 - c) * solventMass : nil
        case .volPct: return c < 100 ? c / (100 - c) * solventVolume * soluteDensity * 1000 : nil
        case .molePct: return c < 100 ? c / (100 - c) * solventMoles * molarMass : nil
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
            }
            Section("Solute") {
                if mode == .concentration {
                    Picker("Amount given as", selection: $soluteKind) { ForEach(SoluteKind.allCases) { Text($0.rawValue).tag($0) } }
                    QuantityRow(title: "Amount", value: $soluteAmount)
                }
                QuantityRow(title: "Molar mass (g/mol)", value: $molarMass)
                QuantityRow(title: "Equivalent mass (g/eq)", value: $eqMass)
                QuantityRow(title: "Density (g/mL)", value: $soluteDensity)
            }
            Section("Solvent") {
                Picker("Amount given as", selection: $solventKind) { ForEach(SolventKind.allCases) { Text($0.rawValue).tag($0) } }
                QuantityRow(title: "Amount", value: $solventAmount)
                QuantityRow(title: "Molar mass (g/mol)", value: $solventMolarMass)
                QuantityRow(title: "Density (g/mL)", value: $solventDensity)
            }
            if mode == .concentration {
                Section("Concentration") {
                    ForEach(computed, id: \.0) { kind, v in
                        LabeledContent(kind.rawValue) { Text(formatNumber(v)).monospacedDigit().fontWeight(.semibold) }
                    }
                    Text("Molarity and normality are per volume of solvent, as in Kalzium.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("Target") {
                    Picker("Concentration unit", selection: $targetKind) { ForEach(ConcKind.allCases) { Text($0.rawValue).tag($0) } }
                    QuantityRow(title: "Concentration", value: $target)
                }
                Section("Required solute") {
                    if let m = requiredSoluteMass, m.isFinite, m >= 0 {
                        LabeledContent("Mass (g)") { Text(formatNumber(m)).monospacedDigit().fontWeight(.semibold) }
                        LabeledContent("Moles") { Text(formatNumber(m / molarMass)).monospacedDigit().fontWeight(.semibold) }
                        LabeledContent("Volume (L)") { Text(formatNumber(m / (soluteDensity * 1000))).monospacedDigit().fontWeight(.semibold) }
                    } else {
                        Label("Percentages must be below 100 and values positive.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
