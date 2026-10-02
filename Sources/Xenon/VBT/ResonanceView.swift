import SwiftUI

struct ResonanceView: View {
    @State private var selected = ProcessInfo.processInfo.environment["XENON_RESONANCE"] ?? "Nitrate"
    private var input: ResonanceInput { Resonance.presets.first { $0.name == selected } ?? Resonance.presets[0] }
    private var structures: [LewisStructure] { Resonance.structures(input) ?? [] }

    var body: some View {
        HSplitView {
            List(Resonance.presets, id: \.name, selection: Binding(get: { selected }, set: { if let v = $0 { selected = v } })) { p in
                HStack { Text(p.name); Spacer(); Text(p.formula).foregroundStyle(.secondary) }.tag(p.name)
            }
            .frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
            ScrollView { content.padding(22).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }

    @ViewBuilder private var content: some View {
        let ss = structures
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tr(input.name)).font(.largeTitle.bold())
                Text(input.formula).font(.title2).foregroundStyle(.secondary)
            }
            if ss.isEmpty {
                Label("No valid Lewis structure found.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                Text(summary(ss)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(ss.count == 1 ? tr("Lewis structure") : tr("{n} resonance structures", ["n": ss.count])).font(.headline)
                FlowLayout(spacing: 14) {
                    ForEach(Array(ss.enumerated()), id: \.element.id) { i, s in
                        VStack(spacing: 4) {
                            LewisCanvas(input: input, orders: s.orders.map(Double.init), lonePairs: s.lonePairs, charges: s.charges.map(Double.init), showLonePairs: true)
                                .frame(width: 190, height: 170)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            if ss.count > 1 { Text(tr("Structure {n}", ["n": i + 1])).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if ss.count > 1 {
                    Text("The real molecule is a blend of all of them, a resonance hybrid:").font(.headline)
                    LewisCanvas(input: input, orders: Resonance.hybridOrders(ss), lonePairs: [], charges: Resonance.averageCharges(ss), showLonePairs: false)
                        .frame(width: 260, height: 230)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    Text("Numbers on the bonds are average bond orders; charges are averaged over the structures. Equal bond lengths in the real molecule show that the structures are not flipping back and forth, the electrons are spread over all of them.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                atomTable(ss)
            }
        }
    }

    private func summary(_ ss: [LewisStructure]) -> String {
        let chargeText = input.charge == 0 ? tr("neutral") : tr("charge {c}", ["c": (input.charge > 0 ? "+" : "−") + "\(abs(input.charge))"])
        let electrons = input.atoms.compactMap { a in ElementStore.all.first { $0.symbol == a.symbol }.flatMap(Resonance.valence) }.reduce(0, +) - input.charge
        return tr("{n} valence electrons in total ({charge}). The structures shown are all the ways to place the bonds and lone pairs that keep formal charges as small as possible while giving each second-period atom a full octet.", ["n": electrons, "charge": chargeText])
    }

    private func atomTable(_ ss: [LewisStructure]) -> some View {
        let el = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0) })
        var neighbours = [[Int]](repeating: [], count: input.atoms.count)
        for (a, b) in input.bonds { neighbours[a].append(b); neighbours[b].append(a) }
        return GroupBox("Hybridization of each atom") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                GridRow { Text("Atom").foregroundStyle(.secondary); Text("Bonds (σ)").foregroundStyle(.secondary); Text("Lone pairs").foregroundStyle(.secondary); Text("Hybridization").foregroundStyle(.secondary) }
                    .font(.caption.weight(.semibold))
                ForEach(input.atoms.indices.filter { input.atoms[$0].symbol != "H" }, id: \.self) { i in
                    let first = ss[0]
                    let pis = ss.map { s in input.bonds.indices.filter { input.bonds[$0].0 == i || input.bonds[$0].1 == i }.reduce(0) { $0 + s.orders[$1] - 1 } }
                    let delocalized = Set(pis).count > 1
                    let h = el[input.atoms[i].symbol].flatMap { Hybridization.make($0, sigma: neighbours[i].count, pi: pis[0], charge: first.charges[i]) }
                    let lpRange = Set(ss.map { $0.lonePairs[i] })
                    GridRow {
                        Text("\(input.atoms[i].symbol)\(i + 1)").fontWeight(.semibold)
                        Text("\(neighbours[i].count)")
                        Text(lpRange.sorted().map(String.init).joined(separator: tr(" or ")))
                        Text(delocalized ? tr("sp² (one p orbital is part of the π system shared by the structures)") : (h?.hybridName.map { $0 + (h!.charge == 0 ? "" : " " + tr("(formal charge {charge})", ["charge": (h!.charge > 0 ? "+" : "−") + "\(abs(h!.charge))"])) } ?? "—"))
                    }.font(.callout)
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Draws one Lewis structure (or the averaged hybrid) from the preset's 2D layout.
struct LewisCanvas: View {
    let input: ResonanceInput
    let orders: [Double]
    let lonePairs: [Int]
    let charges: [Double]
    let showLonePairs: Bool

    var body: some View {
        Canvas { ctx, size in
            let xs = input.atoms.map(\.x), ys = input.atoms.map(\.y)
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 1, minY = ys.min() ?? 0, maxY = ys.max() ?? 1
            let span = max(maxX - minX, maxY - minY, 0.5)
            let scale = min(size.width, size.height) * 0.62 / span
            let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
            func pos(_ i: Int) -> CGPoint { CGPoint(x: size.width / 2 + (input.atoms[i].x - cx) * scale, y: size.height / 2 + (input.atoms[i].y - cy) * scale) }

            for (k, b) in input.bonds.enumerated() {
                let p = pos(b.0), q = pos(b.1)
                let dx = q.x - p.x, dy = q.y - p.y, len = max(1, hypot(dx, dy)), ux = dx / len, uy = dy / len
                let trim: CGFloat = input.atoms[b.0].symbol == "H" || input.atoms[b.1].symbol == "H" ? 9 : 12
                let order = orders.indices.contains(k) ? orders[k] : 1
                let whole = Int(order.rounded(.down)), frac = order - Double(whole)
                let lines = max(1, order.rounded() == order ? Int(order) : whole + 1)
                for l in 0..<lines {
                    let off = (CGFloat(l) - CGFloat(lines - 1) / 2) * 5
                    var path = Path()
                    path.move(to: CGPoint(x: p.x + ux * trim - uy * off, y: p.y + uy * trim + ux * off))
                    path.addLine(to: CGPoint(x: q.x - ux * trim - uy * off, y: q.y - uy * trim + ux * off))
                    let dashed = frac > 0.001 && l == lines - 1
                    ctx.stroke(path, with: .color(.primary.opacity(dashed ? 0.55 : 0.9)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [4, 3] : []))
                }
                if order.rounded() != order {
                    ctx.draw(Text(order.formatted(.number.precision(.fractionLength(2)))).font(.system(size: 10)).foregroundColor(.accentColor),
                             at: CGPoint(x: (p.x + q.x) / 2 - uy * 13, y: (p.y + q.y) / 2 + ux * 13))
                }
            }
            for i in input.atoms.indices {
                let p = pos(i), sym = input.atoms[i].symbol
                ctx.draw(Text(sym).font(.system(size: 19, weight: .bold)), at: p)
                if showLonePairs, lonePairs.indices.contains(i), sym != "H" {
                    // lone pairs sit on the side away from the bonds
                    var away = CGPoint.zero
                    for b in input.bonds where b.0 == i || b.1 == i { let q = pos(b.0 == i ? b.1 : b.0); away.x += p.x - q.x; away.y += p.y - q.y }
                    let base = atan2(away.y, away.x)
                    let n = lonePairs[i]
                    for k in 0..<n {
                        let spread = n == 1 ? 0 : (Double(k) - Double(n - 1) / 2) * 0.95
                        let a = base + spread
                        let c = CGPoint(x: p.x + cos(a) * 19, y: p.y + sin(a) * 19)
                        let px = -sin(a) * 3, py = cos(a) * 3
                        for sgn in [-1.0, 1.0] { ctx.fill(Path(ellipseIn: CGRect(x: c.x + px * sgn - 1.8, y: c.y + py * sgn - 1.8, width: 3.6, height: 3.6)), with: .color(.primary)) }
                    }
                }
                if charges.indices.contains(i), abs(charges[i]) > 0.001 {
                    let c = charges[i]
                    let label = c.rounded() == c ? (abs(c) == 1 ? (c > 0 ? "+" : "−") : "\(Int(abs(c)))" + (c > 0 ? "+" : "−"))
                                                  : (c > 0 ? "+" : "−") + Fraction3.text(abs(c))
                    let corner = CGPoint(x: p.x + 15, y: p.y - 15)
                    ctx.stroke(Path(ellipseIn: CGRect(x: corner.x - 8, y: corner.y - 8, width: 16, height: 16)), with: .color(c > 0 ? .blue : .red), lineWidth: 1.3)
                    ctx.draw(Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(c > 0 ? .blue : .red), at: corner)
                }
            }
        }
    }
}

enum Fraction3 {
    /// 0.667 → "⅔", 0.333 → "⅓", otherwise a short decimal.
    static func text(_ v: Double) -> String {
        if abs(v - 2.0 / 3) < 0.01 { return "⅔" }
        if abs(v - 1.0 / 3) < 0.01 { return "⅓" }
        if abs(v - 0.5) < 0.01 { return "½" }
        return v.formatted(.number.precision(.fractionLength(0...2)))
    }
}
