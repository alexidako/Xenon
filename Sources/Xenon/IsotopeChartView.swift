import SwiftUI

/// Chart of the nuclides: neutrons on x, protons on y.
struct IsotopeChartView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case decay = "Decay type", halfLife = "Half-life", abundance = "Natural abundance"
        var id: String { rawValue }
    }
    enum DecayClass: String, CaseIterable {
        case stable = "Stable / natural", betaMinus = "β⁻ decay", betaPlus = "β⁺ / electron capture", alpha = "α decay"
        case proton = "Proton emission", neutron = "Neutron emission", fission = "Fission", unknownDecay = "Decay mode unknown", noData = "No data"

        var color: Color {
            switch self {
            case .stable: return Color(white: 0.95)
            case .betaMinus: return Color(red: 0.35, green: 0.55, blue: 0.95)
            case .betaPlus: return Color(red: 0.92, green: 0.35, blue: 0.35)
            case .alpha: return Color(red: 0.98, green: 0.82, blue: 0.25)
            case .proton: return Color(red: 0.95, green: 0.55, blue: 0.2)
            case .neutron: return Color(red: 0.35, green: 0.8, blue: 0.85)
            case .fission: return Color(red: 0.45, green: 0.75, blue: 0.4)
            case .unknownDecay: return Color(white: 0.5)
            case .noData: return Color(white: 0.28)
            }
        }
    }

    private let isotopes = IsotopeStore.all
    private let lookup: [Int: Isotope] = Dictionary(uniqueKeysWithValues: IsotopeStore.all.map { (($0.a - $0.z) * 1000 + $0.z, $0) })
    private let maxN = IsotopeStore.all.map { $0.a - $0.z }.max() ?? 176
    private let maxZ = IsotopeStore.all.map(\.z).max() ?? 115
    private let magic = [2, 8, 20, 28, 50, 82, 126]
    private let margin: CGFloat = 34

    @State private var mode: Mode = Mode(rawValue: ProcessInfo.processInfo.environment["XENON_ISO_MODE"] ?? "") ?? .decay
    @State private var cell: Double = 9
    @State private var fit = true
    @State private var showMagic = true
    @State private var selection: Isotope?

    private func decayClass(_ i: Isotope) -> DecayClass {
        if i.halfLife == nil { return i.abundance != nil ? .stable : .noData }
        guard let m = i.decays.first?.mode else { return .unknownDecay }
        if m.contains("fission") { return .fission }
        if m == "alpha" || (m.contains("alpha") && !m.hasPrefix("beta") && !m.hasPrefix("ec")) { return .alpha }
        if m.hasPrefix("betaminus") || m.hasPrefix("2betaminus") { return .betaMinus }
        if m.hasPrefix("betaplus") || m.hasPrefix("ec") || m.hasPrefix("2betaplus") || m.hasPrefix("2ec") { return .betaPlus }
        if m.contains("proton") { return .proton }
        if m.contains("neutron") { return .neutron }
        return .unknownDecay
    }

    private func color(_ i: Isotope) -> Color {
        switch mode {
        case .decay: return decayClass(i).color
        case .halfLife:
            guard let h = i.halfLife, h > 0 else { return i.abundance != nil ? Color(white: 0.95) : Color(white: 0.28) }
            // 1e-22 s ... 1e30 s on a log scale
            return Overlay.gradientColor((log10(h) + 22) / 52)
        case .abundance:
            guard let a = i.abundance else { return Color(white: 0.25) }
            return Overlay.gradientColor(a / 100)
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                controls.padding(10)
                Divider()
                legend.padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
                GeometryReader { geo in
                    let fitCell = min((geo.size.width - margin - 8) / CGFloat(maxN + 2), (geo.size.height - margin - 8) / CGFloat(maxZ + 2))
                    ScrollView([.horizontal, .vertical]) { chart(cell: fit ? max(3, floor(fitCell)) : CGFloat(cell)) }
                }
            }
            .frame(minWidth: 520)
            info.frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
        }
        .navigationTitle("Isotope Chart")
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("Color by", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }.frame(maxWidth: 280)
            Toggle("Fit window", isOn: $fit).toggleStyle(.checkbox)
            HStack { Text("Zoom").fixedSize(); Slider(value: $cell, in: 4...22).frame(width: 140) }.disabled(fit)
            Toggle("Magic numbers", isOn: $showMagic).toggleStyle(.checkbox)
            Spacer()
        }
    }

    @ViewBuilder private var legend: some View {
        switch mode {
        case .decay:
            FlowLayout(spacing: 12) {
                ForEach(DecayClass.allCases, id: \.self) { c in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(c.color).frame(width: 14, height: 14)
                        Text(c.rawValue).font(.callout)
                    }
                }
            }
        case .halfLife, .abundance:
            HStack(spacing: 8) {
                Text(mode == .halfLife ? "10⁻²² s" : "0 %").font(.callout.monospacedDigit())
                LinearGradient(colors: (0...10).map { Overlay.gradientColor(Double($0) / 10) }, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 12).clipShape(Capsule()).frame(maxWidth: 320)
                Text(mode == .halfLife ? "10³⁰ s" : "100 %").font(.callout.monospacedDigit())
                Spacer()
            }
        }
    }

    private func chart(cell c: CGFloat) -> some View {
        let w = margin + CGFloat(maxN + 2) * c, h = margin + CGFloat(maxZ + 2) * c
        return Canvas { ctx, _ in
            func rect(n: Int, z: Int) -> CGRect {
                CGRect(x: margin + CGFloat(n) * c, y: CGFloat(maxZ - z + 1) * c, width: c - 0.5, height: c - 0.5)
            }
            if showMagic {
                for m in magic {
                    if m <= maxN {
                        ctx.fill(Path(CGRect(x: margin + CGFloat(m) * c, y: 0, width: c, height: h - margin)), with: .color(.white.opacity(0.08)))
                    }
                    if m <= maxZ {
                        ctx.fill(Path(CGRect(x: margin, y: CGFloat(maxZ - m + 1) * c, width: w - margin, height: c)), with: .color(.white.opacity(0.08)))
                    }
                }
            }
            for i in isotopes { ctx.fill(Path(rect(n: i.a - i.z, z: i.z)), with: .color(color(i))) }
            if let s = selection {
                ctx.stroke(Path(rect(n: s.a - s.z, z: s.z).insetBy(dx: -1, dy: -1)), with: .color(.accentColor), lineWidth: 2)
            }
            // axes
            let axisFont = Font.system(size: 10)
            for z in stride(from: 10, through: maxZ, by: 10) {
                let r = rect(n: 0, z: z)
                ctx.draw(Text("\(z)").font(axisFont).foregroundColor(.secondary), at: CGPoint(x: margin - 6, y: r.midY), anchor: .trailing)
            }
            for n in stride(from: 20, through: maxN, by: 20) {
                let r = rect(n: n, z: 0)
                ctx.draw(Text("\(n)").font(axisFont).foregroundColor(.secondary), at: CGPoint(x: r.midX, y: h - margin + 12), anchor: .center)
            }
            ctx.draw(Text("Z").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary), at: CGPoint(x: 10, y: 8), anchor: .center)
            ctx.draw(Text("N").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary), at: CGPoint(x: w - 10, y: h - margin + 12), anchor: .center)
        }
        .frame(width: w, height: h)
        .onTapGesture { loc in
            let n = Int(floor((loc.x - margin) / c)), z = maxZ + 1 - Int(floor(loc.y / c))
            selection = lookup[n * 1000 + z]
        }
    }

    private var info: some View {
        ScrollView {
            if let i = selection, let el = ElementStore.all.first(where: { $0.z == i.z }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(i.a)\(el.symbol)").font(.largeTitle.bold())
                    Text("\(el.name)-\(i.a)").foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                        row("Protons", "\(i.z)"); row("Neutrons", "\(i.a - i.z)"); row("Nucleons", "\(i.a)")
                        row("Exact mass", i.mass.map { formatNumber($0) + " u" } ?? "—")
                        row("Half-life", i.halfLife == nil ? (i.abundance != nil ? "stable" : "unknown") : i.halfLifeText)
                        row("Abundance", i.abundance.map { formatNumber($0) + " %" } ?? "—")
                        row("Spin", i.spin ?? "Unknown")
                        row("Magnetic moment", i.magneticMoment.map { formatNumber($0) } ?? "Unknown")
                    }
                    if !i.decays.isEmpty {
                        Text("Decay").font(.headline).padding(.top, 6)
                        ForEach(i.decays, id: \.self) { d in
                            Text("\(d.label)" + (d.percent.map { "  \(formatNumber($0)) %" } ?? "") + (d.energy.map { "  (\(formatNumber($0)) MeV)" } ?? ""))
                                .font(.callout)
                        }
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Click an isotope for details").foregroundStyle(.secondary).padding(30)
            }
        }
    }

    private func row(_ l: String, _ v: String) -> some View {
        GridRow { Text(l).foregroundStyle(.secondary); Text(v).textSelection(.enabled) }
    }
}
