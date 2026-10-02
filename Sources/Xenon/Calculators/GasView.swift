import SwiftUI

/// Van der Waals gas law: (P + a n²/V²)(V − n b) = n R T.  With a = b = 0 it is the ideal gas law.
struct GasView: View {
    enum Solve: String, CaseIterable, Identifiable {
        case volume = "Volume", pressure = "Pressure", temperature = "Temperature", amount = "Amount"
        var id: String { rawValue }
    }
    private let R = 0.082057366  // L·atm/(mol·K)

    @State private var solve: Solve = .volume
    @State private var pressure = 1.0
    @State private var uP = 0
    @State private var volume = 22.4
    @State private var uV = 0
    @State private var temperature = 273.0
    @State private var uT = 0
    @State private var moles = 1.0
    @State private var mass = 2.016
    @State private var uM = 0
    @State private var molarMass = 2.016
    @State private var amountByMass = false
    @State private var a = 0.0
    @State private var b = 0.0
    @State private var uB = 0

    private var n: Double { amountByMass ? Units.mass[uM].toBase(mass) / molarMass : moles }
    private var P: Double { Units.pressure[uP].toBase(pressure) }
    private var V: Double { Units.volume[uV].toBase(volume) }
    private var T: Double { Units.temperature[uT].toBase(temperature) }
    private var bL: Double { Units.volume[uB].toBase(b) }

    private func newton(_ f: (Double) -> Double, from x0: Double) -> Double? {
        var x = x0
        for _ in 0..<80 {
            let h = max(abs(x) * 1e-6, 1e-9), fx = f(x), d = (f(x + h) - f(x - h)) / (2 * h)
            guard d != 0, d.isFinite else { return nil }
            let nx = x - fx / d
            if abs(nx - x) < 1e-12 * max(1, abs(x)) { return nx }
            x = nx
        }
        return x
    }

    private var result: Double? {
        switch solve {
        case .pressure:
            guard V - n * bL > 0 else { return nil }
            return Units.pressure[uP].fromBase(n * R * T / (V - n * bL) - a * n * n / (V * V))
        case .temperature:
            guard n > 0 else { return nil }
            return Units.temperature[uT].fromBase((P + a * n * n / (V * V)) * (V - n * bL) / (n * R))
        case .volume:
            guard P > 0 else { return nil }
            let v = newton({ v in (P + a * n * n / (v * v)) * (v - n * bL) - n * R * T }, from: n * R * T / P + n * bL)
            return v.map { Units.volume[uV].fromBase($0) }
        case .amount:
            guard T > 0 else { return nil }
            return newton({ m in (P + a * m * m / (V * V)) * (V - m * bL) - m * R * T }, from: P * V / (R * T))
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Solve for", selection: $solve) { ForEach(Solve.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
            }
            Section("Gas") {
                QuantityRow(title: "Molar mass (g/mol)", value: $molarMass)
                if solve != .amount {
                    Picker("Amount given as", selection: $amountByMass) {
                        Text("Moles").tag(false); Text("Mass").tag(true)
                    }.pickerStyle(.segmented)
                    if amountByMass { QuantityRow(title: "Mass", value: $mass, units: Units.mass, unit: $uM) }
                    else { QuantityRow(title: "Moles", value: $moles) }
                } else if let m = result {
                    QuantityRow(title: "Moles", value: $moles, computed: m)
                    QuantityRow(title: "Mass (g)", value: $mass, computed: m * molarMass)
                }
            }
            Section("State") {
                QuantityRow(title: "Pressure", value: $pressure, units: Units.pressure, unit: $uP, computed: solve == .pressure ? result : nil)
                QuantityRow(title: "Volume", value: $volume, units: Units.volume, unit: $uV, computed: solve == .volume ? result : nil)
                QuantityRow(title: "Temperature", value: $temperature, units: Units.temperature, unit: $uT, computed: solve == .temperature ? result : nil)
            }
            Section("Van der Waals constants (0 = ideal gas)") {
                QuantityRow(title: "a (L²·atm/mol²)", value: $a)
                QuantityRow(title: "b (per mole)", value: $b, units: Units.volume, unit: $uB)
            }
            if result == nil {
                Label("Not solvable with these values (check for zero or negative inputs).", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}
