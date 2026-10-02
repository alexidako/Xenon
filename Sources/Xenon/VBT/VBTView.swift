import SwiftUI

/// Valence bond theory: hybridization, geometry and orbital-box diagrams.
struct VBTView: View {
    enum Mode: String, CaseIterable, Identifiable { case molecules = "Molecules", predict = "Predict", resonance = "Resonance"; var id: String { rawValue } }

    @State private var mode: Mode = Mode(rawValue: ProcessInfo.processInfo.environment["XENON_VBT_MODE"] ?? "") ?? .molecules

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 340).padding(10)
            Divider()
            switch mode {
            case .molecules: VBTMoleculeMode()
            case .predict: VBTPredictMode()
            case .resonance: ResonanceView()
            }
        }
        .navigationTitle("Valence Bond Theory")
    }
}

// MARK: predict mode

private struct VBTPredictMode: View {
    struct Preset: Identifiable { let id = UUID(); let name: String; let symbol: String; let sigma: Int; let pi: Int }
    private let presets = [
        Preset(name: "CH₄ – carbon", symbol: "C", sigma: 4, pi: 0), Preset(name: "NH₃ – nitrogen", symbol: "N", sigma: 3, pi: 0),
        Preset(name: "H₂O – oxygen", symbol: "O", sigma: 2, pi: 0), Preset(name: "BF₃ – boron", symbol: "B", sigma: 3, pi: 0),
        Preset(name: "BeCl₂ – beryllium", symbol: "Be", sigma: 2, pi: 0), Preset(name: "C₂H₄ – carbon", symbol: "C", sigma: 3, pi: 1),
        Preset(name: "CO₂ – carbon", symbol: "C", sigma: 2, pi: 2), Preset(name: "SO₂ – sulfur", symbol: "S", sigma: 2, pi: 2),
        Preset(name: "SF₄ – sulfur", symbol: "S", sigma: 4, pi: 0), Preset(name: "ClF₃ – chlorine", symbol: "Cl", sigma: 3, pi: 0),
        Preset(name: "PCl₅ – phosphorus", symbol: "P", sigma: 5, pi: 0), Preset(name: "SF₆ – sulfur", symbol: "S", sigma: 6, pi: 0),
        Preset(name: "XeF₄ – xenon", symbol: "Xe", sigma: 4, pi: 0),
    ]

    private let mainGroup = ElementStore.all.filter { Hybridization.valenceElectrons($0) != nil && $0.z != 1 }
    @State private var symbol = ProcessInfo.processInfo.environment["XENON_VBT_ELEMENT"] ?? "C"
    @State private var sigma = Int(ProcessInfo.processInfo.environment["XENON_VBT_SIGMA"] ?? "") ?? 4
    @State private var pi = Int(ProcessInfo.processInfo.environment["XENON_VBT_PI"] ?? "") ?? 0

    private var element: Element? { ElementStore.all.first { $0.symbol == symbol } }
    private var result: Hybridization? { element.flatMap { Hybridization.make($0, sigma: sigma, pi: pi) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose a central atom and how many bonds it makes. Theory works out the lone pairs, hybridization and shape.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Picker("Atom", selection: $symbol) {
                        ForEach(mainGroup) { Text("\($0.symbol) – \(tr($0.name))").tag($0.symbol) }
                    }.frame(maxWidth: 240)
                    Stepper(tr("σ bonds: {n}", ["n": sigma]), value: $sigma, in: 0...7)
                    Stepper(tr("π bonds: {n}", ["n": pi]), value: $pi, in: 0...4)
                    Menu("Examples") {
                        ForEach(presets) { p in Button(tr(p.name)) { symbol = p.symbol; sigma = p.sigma; pi = p.pi } }
                    }.fixedSize()
                }
                if let h = result, h.hybridName != nil {
                    AtomDiagramView(h: h)
                } else if let e = element, Hybridization.valenceElectrons(e) != nil {
                    Label(Hybridization.make(e, sigma: sigma, pi: pi) == nil
                          ? tr("{symbol} has {v} valence electrons. {sigma} σ + {pi} π bonds use {used}, and the rest must pair up as lone pairs, so this combination needs a formal charge or isn't possible for a neutral atom.", ["symbol": e.symbol, "v": Hybridization.valenceElectrons(e) ?? 0, "sigma": sigma, "pi": pi, "used": sigma + pi])
                          : tr("At least two electron domains (bonds plus lone pairs) are needed to hybridize."),
                          systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: molecule mode

private struct VBTMoleculeMode: View {
    @ObservedObject private var user = UserMolecules.shared
    private var molecules: [Molecule] { user.items + MoleculeLibrary.bundled }
    @State private var selection: Molecule.ID?
    @State private var atom: Int?

    private var current: Molecule? {
        let want = (ProcessInfo.processInfo.environment["XENON_MOL"] ?? "").lowercased()
        return molecules.first { $0.id == selection }
            ?? molecules.first { !want.isEmpty && $0.name.lowercased() == want }
            ?? molecules.first { !want.isEmpty && $0.name.lowercased().contains(want) } ?? molecules.first
    }

    var body: some View {
        HSplitView {
            List(molecules, selection: $selection) { Text($0.name).tag($0.id) }
                .frame(minWidth: 180, idealWidth: 210, maxWidth: 280)
            if let m = current { detail(m).id(m.id) } else { Text("No molecule").frame(maxWidth: .infinity) }
        }
        .onAppear { if let f = user.focus { selection = f } }
        .onChange(of: user.focus) { _, f in if let f { selection = f; atom = nil } }
    }

    @ViewBuilder private func detail(_ m: Molecule) -> some View {
        let a = VBT.analyze(m)
        let heavy = a.atoms.filter { $0.element?.symbol != "H" }
        // default to the first atom that can be hybridized
        let chosen = heavy.first { $0.index == atom } ?? heavy.first { $0.hybrid?.hybridName != nil } ?? heavy.first
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(m.name).font(.title.bold())
                    Text(Markup.formulaText(m.formula)).font(.title3.monospaced()).foregroundStyle(.secondary)
                }
                Text("Pick an atom to see how its orbitals hybridize.").foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(heavy) { at in
                        Button { atom = at.index } label: {
                            VStack(spacing: 1) {
                                Text(at.label).font(.callout.weight(.semibold))
                                Text((at.hybrid?.hybridName ?? "—") + (at.hybrid.map { Hybridization.chargeText($0.charge) } ?? "")).font(.caption2)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(at.index == chosen?.index ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(at.index == chosen?.index ? Color.white : Color.primary)
                        }.buttonStyle(.plain)
                    }
                }
                if let c = chosen {
                    if let h = c.hybrid, h.hybridName != nil {
                        AtomDiagramView(h: h, title: c.label)
                        if !c.measuredAngles.isEmpty {
                            GroupBox("Bond angles in this structure") {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tr("Predicted: {angle}", ["angle": tr(h.shape?.angle ?? "—")])).foregroundStyle(.secondary)
                                    Text(tr("Measured from the 3D file: {angles}", ["angles": c.measuredAngles.map { String(format: "%.1f°", $0) }.joined(separator: ", ")])).monospacedDigit()
                                }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        Label(tr(c.note ?? "Hybridization isn't defined for this atom."), systemImage: "info.circle").foregroundStyle(.secondary)
                    }
                }
                GroupBox("Every bond") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                        ForEach(a.bonds) { b in
                            GridRow { Text(b.label).font(.callout.monospaced()); Text(b.detail).font(.callout) }
                        }
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Terminal atoms are hybridized by counting their bonds plus lone pairs, the same rule used for central atoms.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: shared diagram

struct AtomDiagramView: View {
    let h: Hybridization
    var title: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? tr(h.element.name)).font(.caption).foregroundStyle(.secondary)
                    Text(h.hybridName ?? "").font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("hybridized").font(.callout).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    row("Electron domains", tr("{n} ({sigma} σ bonds + {lp} lone pairs)", ["n": h.steric, "sigma": h.sigma, "lp": h.lonePairs]))
                    row("Electron geometry", tr(h.electronGeometry ?? "—"))
                    row("Molecular shape", tr(h.shape?.name ?? "—"))
                    row("Ideal bond angle", tr(h.shape?.angle ?? "—"))
                    row("π bonds", "\(h.pi)")
                    row("Valence electrons", h.charge == 0 ? "\(h.valence)" : tr("{n} (formal charge {charge})", ["n": h.valence, "charge": (h.charge > 0 ? "+" : "−") + "\(abs(h.charge))"]))
                }
            }
            GroupBox("Orbital diagram") {
                VStack(alignment: .leading, spacing: 14) {
                    boxes("Ground state", h.groundState)
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down")
                        Text(h.needsPromotion ? tr(h.mix.d > 0 ? "promote electrons, then mix s, p, d orbitals" : "promote electrons, then mix s, p orbitals") : tr("mix the s and p orbitals"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    boxes("After hybridization", h.hybridized)
                }.padding(8)
            }
            Text(explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var explanation: String {
        var s = tr("Each σ bond is an end-to-end overlap of an {hybrid} orbital with an orbital from the bonded atom.", ["hybrid": h.hybridName ?? "hybrid"])
        if h.lonePairs > 0 { s += " " + tr("Lone pairs sit in hybrid orbitals too, and because they take up more room than bonding pairs they squeeze the bond angles below the ideal value.") }
        if h.pi > 0 { s += " " + (h.pi == 1 ? tr("The π bond comes from side-on overlap of an unhybridized {shell}p orbital.", ["shell": h.shell]) : tr("The {n} π bonds come from side-on overlap of unhybridized {shell}p orbitals.", ["n": h.pi, "shell": h.shell])) }
        return s
    }

    private func row(_ a: String, _ b: String) -> some View {
        GridRow { Text(a).foregroundStyle(.secondary); Text(b).fontWeight(.medium) }
    }

    private func boxes(_ title: String, _ bs: [Hybridization.Box]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 6) { ForEach(bs) { OrbitalBoxView(box: $0) } }
        }
    }
}

struct OrbitalBoxView: View {
    let box: Hybridization.Box

    private var color: Color {
        switch box.kind {
        case .hybridLonePair: return .purple
        case .hybridBond: return .blue
        case .piP, .piD: return .orange
        default: return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.10)))
                HStack(spacing: 3) {
                    if box.electrons >= 1 { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)) }
                    if box.electrons >= 2 { Image(systemName: "arrow.down").font(.system(size: 15, weight: .bold)) }
                }
            }
            .frame(width: 44, height: 40)
            Text(box.label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
