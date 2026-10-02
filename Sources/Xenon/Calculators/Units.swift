import SwiftUI

/// value_in_base = value * factor + offset
struct Unit: Hashable {
    let name: String
    let factor: Double
    var offset: Double = 0

    func toBase(_ v: Double) -> Double { v * factor + offset }
    func fromBase(_ b: Double) -> Double { (b - offset) / factor }
}

enum Units {
    static let mass = [Unit(name: "g", factor: 1), Unit(name: "mg", factor: 1e-3), Unit(name: "kg", factor: 1e3),
                       Unit(name: "t", factor: 1e6), Unit(name: "ct", factor: 0.2), Unit(name: "lb", factor: 453.59237),
                       Unit(name: "oz", factor: 28.349523125), Unit(name: "oz t", factor: 31.1034768)]
    static let pressure = [Unit(name: "atm", factor: 1), Unit(name: "Pa", factor: 1 / 101325), Unit(name: "bar", factor: 0.986923267),
                           Unit(name: "mbar", factor: 0.000986923267), Unit(name: "Torr", factor: 1 / 760)]
    static let temperature = [Unit(name: "K", factor: 1), Unit(name: "°C", factor: 1, offset: 273.15),
                              Unit(name: "°F", factor: 5 / 9, offset: 273.15 - 160 / 9)]
    static let volume = [Unit(name: "L", factor: 1), Unit(name: "mL", factor: 1e-3), Unit(name: "m³", factor: 1000),
                         Unit(name: "gal (US)", factor: 3.785411784)]
    static let time = [Unit(name: "y", factor: 31_557_600), Unit(name: "weeks", factor: 604_800), Unit(name: "d", factor: 86_400),
                       Unit(name: "h", factor: 3_600), Unit(name: "min", factor: 60), Unit(name: "s", factor: 1)]
}

func formatNumber(_ v: Double) -> String {
    guard v.isFinite else { return "—" }
    if v == 0 { return "0" }
    let a = abs(v)
    if a >= 1e7 || a < 1e-4 { return String(format: "%.5g", v) }
    return v.formatted(.number.precision(.significantDigits(1...7)).grouping(.never))
}

/// A labeled numeric input with an optional unit picker, or a read-only computed value.
struct QuantityRow: View {
    let title: String
    @Binding var value: Double
    var units: [Unit] = []
    var unit: Binding<Int>? = nil
    var computed: Double? = nil   // when set, the row shows this instead of an editor

    var body: some View {
        LabeledContent(title) {
            HStack {
                if let c = computed {
                    Text(formatNumber(c)).monospacedDigit().fontWeight(.semibold).textSelection(.enabled)
                        .frame(minWidth: 120, alignment: .trailing)
                } else {
                    TextField("", value: $value, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing).frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                }
                if let unit, !units.isEmpty {
                    Picker("", selection: unit) {
                        ForEach(units.indices, id: \.self) { Text(units[$0].name).tag($0) }
                    }
                    .labelsHidden().frame(width: 92)
                }
            }
        }
    }
}
