import SwiftUI
import Charts

/// Plot one element property against another over a range of elements (Kalzium's "Plot data").
struct PlotView: View {
    enum Property: String, CaseIterable, Identifiable {
        case number = "Atomic number", mass = "Atomic mass", electronegativity = "Electronegativity"
        case melting = "Melting point (K)", boiling = "Boiling point (K)"
        case vdw = "Van der Waals radius (Å)", covalent = "Covalent radius (Å)"
        case ionization = "Ionization energy (eV)", affinity = "Electron affinity (eV)"
        var id: String { rawValue }
        func value(_ e: Element) -> Double? {
            switch self {
            case .number: return Double(e.z)
            case .mass: return e.mass
            case .electronegativity: return e.electronegativity
            case .melting: return e.meltingPoint
            case .boiling: return e.boilingPoint
            case .vdw: return e.radiusVDW
            case .covalent: return e.radiusCovalent
            case .ionization: return e.ionization
            case .affinity: return e.electronAffinity
            }
        }
    }
    enum Style: String, CaseIterable, Identifiable { case points = "Points", line = "Line", both = "Line & points"; var id: String { rawValue } }

    @State private var xProp: Property = .number
    @State private var yProp: Property = Property(rawValue: ProcessInfo.processInfo.environment["XENON_PLOT_Y"] ?? "") ?? .ionization
    @State private var from = 1.0
    @State private var to = 118.0
    @State private var style: Style = .both
    @State private var labels = true

    struct Pt: Identifiable { let id: Int; let x: Double; let y: Double; let symbol: String }

    private var points: [Pt] {
        ElementStore.all.filter { Double($0.z) >= from && Double($0.z) <= to }.compactMap { e in
            guard let x = xProp.value(e), let y = yProp.value(e) else { return nil }
            return Pt(id: e.z, x: x, y: y, symbol: e.symbol)
        }
        .sorted { $0.x < $1.x }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("Y axis", selection: $yProp) { ForEach(Property.allCases) { Text($0.rawValue).tag($0) } }.frame(maxWidth: 300)
                Picker("X axis", selection: $xProp) { ForEach(Property.allCases) { Text($0.rawValue).tag($0) } }.frame(maxWidth: 300)
                Spacer()
            }.padding(10)
            HStack(spacing: 14) {
                Text("Elements")
                TextField("", value: $from, format: .number).frame(width: 60)
                Text("to")
                TextField("", value: $to, format: .number).frame(width: 60)
                Picker("Style", selection: $style) { ForEach(Style.allCases) { Text($0.rawValue).tag($0) } }.frame(maxWidth: 220)
                Toggle("Labels", isOn: $labels).toggleStyle(.checkbox)
                Spacer()
                Text("\(points.count) elements plotted").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 10).padding(.bottom, 10)
            Divider()
            Chart(points) { p in
                if style != .points {
                    LineMark(x: .value(xProp.rawValue, p.x), y: .value(yProp.rawValue, p.y)).foregroundStyle(.blue.opacity(0.6))
                }
                if style != .line {
                    PointMark(x: .value(xProp.rawValue, p.x), y: .value(yProp.rawValue, p.y)).foregroundStyle(.blue)
                        .annotation(position: .top, spacing: 2) {
                            if labels { Text(p.symbol).font(.system(size: 9)).foregroundStyle(.secondary) }
                        }
                }
            }
            .chartXScale(domain: (points.map(\.x).min() ?? 0)...max((points.map(\.x).max() ?? 1), (points.map(\.x).min() ?? 0) + 1))
            .chartXAxisLabel(tr(xProp.rawValue))
            .chartYAxisLabel(tr(yProp.rawValue))
            .padding(20)
        }
        .navigationTitle("Plot Data")
    }
}
