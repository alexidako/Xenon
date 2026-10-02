import SwiftUI

struct SpectrumView: View {
    enum SpectrumType: String, CaseIterable, Identifiable { case emission = "Emission", absorption = "Absorption"; var id: String { rawValue } }
    enum WavelengthUnit: String, CaseIterable, Identifiable {
        case nm = "nm", angstrom = "Å", micron = "µm", eV = "eV"
        var id: String { rawValue }
        func fromNM(_ nm: Double) -> Double {
            switch self { case .nm: return nm; case .angstrom: return nm * 10; case .micron: return nm / 1000; case .eV: return 1239.841984 / nm }
        }
        func toNM(_ v: Double) -> Double {
            switch self { case .nm: return v; case .angstrom: return v / 10; case .micron: return v * 1000; case .eV: return 1239.841984 / v }
        }
    }

    let element: Element
    @State private var type: SpectrumType = .emission
    @State private var unit: WavelengthUnit = .nm
    @State private var lo = 380.0     // always stored in nm
    @State private var hi = 780.0

    var body: some View {
        let lines = (SpectrumStore.byElement[element.z] ?? []).sorted { $0.wavelength < $1.wavelength }
        VStack(alignment: .leading, spacing: 14) {
            if lines.isEmpty {
                Text(tr("No spectrum is available for {name}.", ["name": tr(element.name)])).foregroundStyle(.secondary)
            } else {
                HStack {
                    Picker("Type", selection: $type) { ForEach(SpectrumType.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).frame(maxWidth: 220)
                    Picker("Unit", selection: $unit) { ForEach(WavelengthUnit.allCases) { Text($0.rawValue).tag($0) } }
                        .frame(maxWidth: 120)
                }
                HStack {
                    Text("Range")
                    TextField("", value: loField, format: .number.precision(.significantDigits(1...6))).frame(width: 80)
                    Text("to")
                    TextField("", value: hiField, format: .number.precision(.significantDigits(1...6))).frame(width: 80)
                    Text(unit.rawValue)
                    Spacer()
                    Button("Visible") { lo = 380; hi = 780 }
                    Button("All") {
                        lo = max(1, (lines.first?.nanometers ?? 380) - 5); hi = (lines.last?.nanometers ?? 780) + 5
                    }
                }
                Strip(lines: lines, lo: min(lo, hi), hi: max(lo, hi), absorption: type == .absorption)
                    .frame(height: 70).clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Text(label(min(lo, hi))); Spacer(); Text(label(max(lo, hi)))
                }.font(.caption).foregroundStyle(.secondary)

                let shown = lines.filter { $0.nanometers >= min(lo, hi) && $0.nanometers <= max(lo, hi) }
                Text(tr("{n} of {total} lines in range", ["n": shown.count, "total": lines.count])).font(.caption).foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow { Text(""); Text("Wavelength"); Text("Intensity"); Text("Region") }
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        GridRow {
                            Circle().fill(wavelengthColor(line.nanometers)).frame(width: 10, height: 10)
                            Text(formatNumber(unit.fromNM(line.nanometers)) + " " + unit.rawValue).monospacedDigit()
                            Text(line.intensity.formatted()).monospacedDigit()
                            Text(region(line.nanometers)).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .opacity(line.nanometers >= min(lo, hi) && line.nanometers <= max(lo, hi) ? 1 : 0.4)
                    }
                }
            }
        }
    }

    /// Range fields show and edit the nm-stored bounds in the selected unit.
    private var loField: Binding<Double> {
        Binding(get: { unit.fromNM(lo) }, set: { if $0 > 0 { lo = unit.toNM($0) } })
    }
    private var hiField: Binding<Double> {
        Binding(get: { unit.fromNM(hi) }, set: { if $0 > 0 { hi = unit.toNM($0) } })
    }

    private func label(_ nm: Double) -> String { formatNumber(unit.fromNM(nm)) + " " + unit.rawValue }
    private func region(_ nm: Double) -> String { nm < 380 ? "UV" : nm > 780 ? "IR" : "visible" }
}

private struct Strip: View {
    let lines: [SpectrumLine]
    let lo: Double, hi: Double
    let absorption: Bool

    var body: some View {
        Canvas { ctx, size in
            guard hi > lo else { return }
            if absorption {
                // continuous colors with dark absorption lines
                let steps = 120
                for i in 0..<steps {
                    let nm = lo + (hi - lo) * (Double(i) + 0.5) / Double(steps)
                    let x = size.width * CGFloat(i) / CGFloat(steps)
                    ctx.fill(Path(CGRect(x: x, y: 0, width: size.width / CGFloat(steps) + 1, height: size.height)),
                             with: .color(wavelengthColor(nm, clampToVisible: true)))
                }
            } else {
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            }
            let maxI = lines.map(\.intensity).max() ?? 1
            for line in lines where line.nanometers >= lo && line.nanometers <= hi {
                let x = CGFloat((line.nanometers - lo) / (hi - lo)) * size.width
                let alpha = 0.35 + 0.65 * line.intensity / maxI
                let color: Color = absorption ? .black : wavelengthColor(line.nanometers, clampToVisible: true)
                ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(color.opacity(alpha)))
            }
        }
    }
}
