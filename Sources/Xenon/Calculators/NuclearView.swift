import SwiftUI

/// Radioactive decay: N = N0 · 2^(−t / T½)
struct NuclearView: View {
    enum Solve: String, CaseIterable, Identifiable {
        case final = "Final amount", initial = "Initial amount", time = "Time"
        var id: String { rawValue }
    }

    @State private var z = 92
    @State private var isotopeID = 238 + 92 * 1000
    @State private var solve: Solve = .time
    @State private var halfLifeValue = 4.468e9
    @State private var uHalf = 0
    @State private var initial = 6.0
    @State private var uInit = 0
    @State private var final = 3.0
    @State private var uFinal = 0
    @State private var time = 4.468e9
    @State private var uTime = 0
    @State private var inMoles = false
    @State private var halfLivesSlider = 1.0

    private var isotopes: [Isotope] { (IsotopeStore.byElement[z] ?? []).filter { $0.halfLife != nil } }
    private var isotope: Isotope? { isotopes.first { $0.id == isotopeID } ?? isotopes.first }
    private var atomicMass: Double { isotope?.mass ?? Double(isotope?.a ?? 1) }

    private var halfLifeSeconds: Double { Units.time[uHalf].toBase(halfLifeValue) }
    private var t: Double { Units.time[uTime].toBase(time) }

    /// Amounts are handled in grams internally.
    private func grams(_ v: Double, _ u: Int) -> Double { inMoles ? v * atomicMass : Units.mass[u].toBase(v) }
    private func display(_ g: Double, _ u: Int) -> Double { inMoles ? g / atomicMass : Units.mass[u].fromBase(g) }

    private var result: Double? {
        guard halfLifeSeconds > 0 else { return nil }
        switch solve {
        case .final:
            return display(grams(initial, uInit) / pow(2, t / halfLifeSeconds), uFinal)
        case .initial:
            return display(grams(final, uFinal) * pow(2, t / halfLifeSeconds), uInit)
        case .time:
            let i = grams(initial, uInit), f = grams(final, uFinal)
            guard i > 0, f > 0, f <= i else { return nil }
            return Units.time[uTime].fromBase(log2(i / f) * halfLifeSeconds)
        }
    }

    var body: some View {
        Form {
            Section("Isotope") {
                Picker("Element", selection: $z) {
                    ForEach(ElementStore.all) { Text("\($0.z)  \($0.name)").tag($0.z) }
                }
                .onChange(of: z) { _, _ in
                    if let first = isotopes.first { isotopeID = first.id; useHalfLife(first) }
                }
                Picker("Isotope", selection: $isotopeID) {
                    ForEach(isotopes) { Text("\($0.a)\(ElementStore.all[z - 1].symbol)  (\($0.halfLifeText))").tag($0.id) }
                }
                .onChange(of: isotopeID) { _, _ in if let iso = isotope { useHalfLife(iso) } }
                QuantityRow(title: "Half-life", value: $halfLifeValue, units: Units.time, unit: $uHalf)
            }
            Section {
                Picker("Solve for", selection: $solve) { ForEach(Solve.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                Picker("Amounts in", selection: $inMoles) { Text("Mass").tag(false); Text("Moles").tag(true) }
                    .pickerStyle(.segmented)
            }
            Section("Amounts") {
                QuantityRow(title: "Initial amount", value: $initial, units: inMoles ? [] : Units.mass, unit: $uInit,
                            computed: solve == .initial ? result : nil)
                QuantityRow(title: "Final amount", value: $final, units: inMoles ? [] : Units.mass, unit: $uFinal,
                            computed: solve == .final ? result : nil)
                QuantityRow(title: "Elapsed time", value: $time, units: Units.time, unit: $uTime,
                            computed: solve == .time ? result : nil)
                if solve != .time {
                    LabeledContent("In half-lives") {
                        Slider(value: Binding(get: { t / max(halfLifeSeconds, 1e-300) },
                                              set: { time = Units.time[uTime].fromBase($0 * halfLifeSeconds) }), in: 0...10)
                            .frame(width: 220)
                    }
                    LabeledContent("Fraction remaining") {
                        Text((100 / pow(2, t / max(halfLifeSeconds, 1e-300))).formatted(.number.precision(.fractionLength(0...3))) + " %")
                            .monospacedDigit()
                    }
                }
            }
            if result == nil {
                Label("Enter positive amounts (final ≤ initial) and a non-zero half-life.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }

    private func useHalfLife(_ iso: Isotope) {
        guard let s = iso.halfLife else { return }
        // pick the largest unit in which the half-life is at least 1
        let idx = Units.time.firstIndex { s >= $0.factor } ?? Units.time.count - 1
        uHalf = idx; halfLifeValue = Units.time[idx].fromBase(s)
    }
}
