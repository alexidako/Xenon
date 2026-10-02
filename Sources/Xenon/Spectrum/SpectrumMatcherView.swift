import SwiftUI

/// "Which gas is in this tube?" — enter observed wavelengths, get the elements that best explain them.
struct SpectrumMatcherView: View {
    private struct Example: Identifiable { let id = UUID(); let name: String; let text: String }
    private let examples = [
        Example(name: "Hydrogen (Balmer lines)", text: "486.13, 656.28"),
        Example(name: "Helium", text: "587.56, 667.82, 706.52, 501.57"),
        Example(name: "Sodium lamp (D doublet)", text: "589.0, 589.6"),
        Example(name: "Mystery gas: hydrogen + helium", text: "486.13, 656.28, 587.56, 667.82"),
    ]

    @State private var text = ProcessInfo.processInfo.environment["XENON_SPEC"] ?? "486.13, 656.28, 587.56, 667.82"
    @State private var angstrom = false
    @State private var tolerance = 1.0
    @State private var selected: Int?

    private var observed: [Double] { SpectrumMatcher.parse(text, angstrom: angstrom) }
    private var ranked: [SpectrumMatcher.Candidate] { Array(SpectrumMatcher.rank(observed: observed, tolerance: tolerance).prefix(10)) }
    private var current: SpectrumMatcher.Candidate? { ranked.first { $0.id == selected } ?? ranked.first }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Observed lines").font(.headline)
                TextEditor(text: $text).font(.body.monospaced()).frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                HStack {
                    Picker("Unit", selection: $angstrom) { Text("nm").tag(false); Text("Å").tag(true) }
                        .pickerStyle(.segmented).frame(width: 130)
                    Menu("Examples") { ForEach(examples) { ex in Button(tr(ex.name)) { text = ex.text; angstrom = false; selected = nil } } }.fixedSize()
                    Spacer()
                    Text(tr("{n} lines observed", ["n": observed.count])).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Tolerance"); Slider(value: $tolerance, in: 0.1...5, step: 0.1).frame(width: 160)
                    Text("± \(tolerance.formatted(.number.precision(.fractionLength(1)))) nm").monospacedDigit()
                }
                Divider()
                Text("Best matches").font(.headline)
                if ranked.isEmpty {
                    Text(observed.isEmpty ? "Enter one or more wavelengths separated by commas or spaces."
                         : "No element in the database has lines near these wavelengths. Try a wider tolerance.")
                        .foregroundStyle(.secondary)
                } else {
                    List(selection: $selected) {
                        ForEach(ranked) { c in
                            HStack {
                                Text(c.element.symbol).font(.title3.bold()).frame(width: 36)
                                VStack(alignment: .leading) {
                                    Text(c.element.name)
                                    Text(tr("explains {n} of {total} lines", ["n": c.matches.count, "total": observed.count])).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                ScoreBar(score: c.score)
                                Text("\(Int((c.score * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                            }
                            .tag(c.id)
                        }
                    }
                    .frame(minHeight: 200)
                }
            }
            .padding(16)
            .frame(minWidth: 420, idealWidth: 460)

            ScrollView {
                if let c = current {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(c.element.name) vs. your lines").font(.title2.bold())
                        ComparisonStrip(observed: observed, candidate: c, tolerance: tolerance)
                            .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 6))
                        HStack(spacing: 14) {
                            Label("your lines", systemImage: "circle.fill").foregroundStyle(.white)
                            Label("\(c.element.name) lines", systemImage: "circle.fill").foregroundStyle(.yellow)
                        }.font(.caption)
                        Text("Line by line").font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                            GridRow { Text("Observed"); Text("Could be"); Text("Offset") }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(Array(observed.enumerated()), id: \.offset) { _, o in
                                let who = SpectrumMatcher.assignments(for: o, tolerance: tolerance)
                                GridRow {
                                    Text(formatNumber(o) + " nm").monospacedDigit()
                                    Text(who.isEmpty ? "no match" : who.prefix(4).map(\.0.symbol).joined(separator: ", "))
                                        .foregroundStyle(who.isEmpty ? Color.secondary : Color.primary)
                                    Text(who.first.map { "±" + formatNumber($0.1) + " nm" } ?? "—").foregroundStyle(.secondary).monospacedDigit()
                                }.font(.callout)
                            }
                        }
                        Text("Scores combine how many of your lines the element explains with how many of its strong visible lines you actually saw, so a gas that only shares one line scores low.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Matches will appear here").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(40)
                }
            }
            .frame(minWidth: 380)
        }
        .navigationTitle("Spectrum Matcher")
    }
}

private struct ScoreBar: View {
    let score: Double
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.quaternary)
            Capsule().fill(Color.accentColor).frame(width: 90 * max(0.04, score))
        }.frame(width: 90, height: 6)
    }
}

private struct ComparisonStrip: View {
    let observed: [Double]
    let candidate: SpectrumMatcher.Candidate
    let tolerance: Double

    var body: some View {
        Canvas { ctx, size in
            let lines = SpectrumStore.byElement[candidate.element.z] ?? []
            let all = observed + lines.map(\.nanometers).filter { $0 >= 380 && $0 <= 780 }
            let lo = min(380, observed.min() ?? 380) , hi = max(780, observed.max() ?? 780)
            _ = all
            func x(_ nm: Double) -> CGFloat { CGFloat((nm - lo) / (hi - lo)) * size.width }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            // faint rainbow behind both rows
            for i in 0..<100 {
                let nm = lo + (hi - lo) * (Double(i) + 0.5) / 100
                ctx.fill(Path(CGRect(x: size.width * CGFloat(i) / 100, y: size.height / 2 - 1, width: size.width / 100 + 1, height: 2)),
                         with: .color(wavelengthColor(nm, clampToVisible: true).opacity(0.5)))
            }
            let maxI = lines.map(\.intensity).max() ?? 1
            for l in lines where l.nanometers >= lo && l.nanometers <= hi {
                let a = 0.4 + 0.6 * l.intensity / maxI
                ctx.fill(Path(CGRect(x: x(l.nanometers) - 1, y: size.height / 2 + 4, width: 2, height: size.height / 2 - 8)),
                         with: .color(.yellow.opacity(a)))
            }
            for o in observed where o >= lo && o <= hi {
                ctx.fill(Path(CGRect(x: x(o) - 1.5, y: 4, width: 3, height: size.height / 2 - 8)), with: .color(.white))
            }
            ctx.draw(Text("\(Int(lo)) nm").font(.system(size: 9)).foregroundColor(.secondary), at: CGPoint(x: 18, y: size.height - 7))
            ctx.draw(Text("\(Int(hi)) nm").font(.system(size: 9)).foregroundColor(.secondary), at: CGPoint(x: size.width - 20, y: size.height - 7))
        }
    }
}
