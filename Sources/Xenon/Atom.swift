import SwiftUI

/// Electron configuration expansion: "[Ar] 3d6 4s2" -> subshell occupancies.
struct Subshell: Hashable {
    let n: Int
    let l: Character   // s p d f
    var electrons: Int
}

enum ElectronConfiguration {
    private static let cores: [String: String] = [
        "He": "1s2",
        "Ne": "[He] 2s2 2p6",
        "Ar": "[Ne] 3s2 3p6",
        "Kr": "[Ar] 4s2 3d10 4p6",
        "Xe": "[Kr] 5s2 4d10 5p6",
        "Rn": "[Xe] 6s2 4f14 5d10 6p6",
    ]

    static func subshells(_ text: String) -> [Subshell] {
        var out: [Subshell] = []
        for token in text.split(separator: " ") {
            if token.hasPrefix("[") {
                let name = token.dropFirst().dropLast()
                if let core = cores[String(name)] { out += subshells(core) }
            } else if let l = token.dropFirst().first(where: { "spdf".contains($0) }),
                      let n = Int(token.prefix(1)), let e = Int(token.dropFirst(2)) {
                out.append(Subshell(n: n, l: l, electrons: e))
            }
        }
        return out
    }

    /// Electrons per principal shell n = 1, 2, 3 ...
    static func shells(_ text: String) -> [Int] {
        var counts: [Int: Int] = [:]
        for s in subshells(text) { counts[s.n, default: 0] += s.electrons }
        return (1...(counts.keys.max() ?? 1)).map { counts[$0] ?? 0 }
    }
}

struct AtomModelView: View {
    let element: Element

    var body: some View {
        let shells = ElectronConfiguration.shells(element.configuration ?? "")
        let subs = ElectronConfiguration.subshells(element.configuration ?? "")
        VStack(alignment: .leading, spacing: 14) {
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = min(size.width, size.height) / 2 - 6
                let nucleusR = maxR * 0.12
                let step: CGFloat = (maxR - nucleusR - 4) / CGFloat(max(shells.count, 1))

                for (i, count) in shells.enumerated() {
                    let r: CGFloat = nucleusR + 4 + step * CGFloat(i + 1)
                    ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(.secondary.opacity(0.6)), lineWidth: 1)
                    for k in 0..<count {
                        let frac: Double = Double(k) / Double(max(count, 1))
                        let a: Double = 2 * Double.pi * frac - Double.pi / 2 + Double(i) * 0.3
                        let c = CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)), with: .color(.yellow))
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)),
                                   with: .color(.orange), lineWidth: 0.8)
                    }
                }
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - nucleusR, y: center.y - nucleusR, width: 2 * nucleusR, height: 2 * nucleusR)),
                         with: .color(.red))
            }
            .frame(height: 280)
            .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.25)))

            Text("Each ring is an electron shell; each yellow dot an electron.")
                .font(.caption).foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow { Text("Shell").foregroundStyle(.secondary); Text("Electrons").foregroundStyle(.secondary); Text("Subshells").foregroundStyle(.secondary) }
                    .font(.caption.weight(.semibold))
                ForEach(Array(shells.enumerated()), id: \.offset) { i, count in
                    GridRow {
                        Text("\(i + 1) (\(Array("KLMNOPQ")[min(i, 6)]))")
                        Text("\(count)").monospacedDigit()
                        Text(subs.filter { $0.n == i + 1 }.map { "\($0.n)\($0.l)\($0.electrons)" }.joined(separator: "  ")).monospaced()
                    }
                    .font(.callout)
                }
            }
            LabeledContent("Protons / electrons") { Text("\(element.z)").monospacedDigit() }
            LabeledContent("Configuration") { Text(element.configuration.map(QuizEngine.pretty) ?? "—").textSelection(.enabled) }
        }
    }
}
