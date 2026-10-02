import SwiftUI
import Charts

/// Plots a system of equations (theoretical curve) and fits experimental titration points
/// with y = a·tanh(b·(x + c)) + d; the equivalence point is x = −c.
struct TitrationView: View {
    struct Equation: Identifiable { let id = UUID(); var name = ""; var text = "" }
    struct Point: Identifiable { let id = UUID(); var y = ""; var x = "" }

    @State private var equations: [Equation] = (0..<6).map { _ in Equation() }
    @State private var points: [Point] = (0..<8).map { _ in Point() }
    @State private var xVar = ""
    @State private var yVar = ""
    @State private var xMin = 0.0
    @State private var xMax = 60.0
    @State private var yMin = 0.0
    @State private var yMax = 14.0

    struct Sample: Identifiable { let id = UUID(); let x: Double; let y: Double; let series: String }
    struct Fit { let a, b, c, d: Double; var equivalence: Double { -c } }

    // MARK: model

    private func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    private var experimental: [(x: Double, y: Double)] {
        points.compactMap { p in
            guard let x = number(p.x), let y = number(p.y) else { return nil }
            return (x, y)
        }
    }

    private var theory: (samples: [Sample], formula: String)? {
        guard !yVar.isEmpty, !xVar.isEmpty else { return nil }
        let table = Dictionary(equations.filter { !$0.name.isEmpty && !$0.text.isEmpty }.map { ($0.name, $0.text) },
                               uniquingKeysWith: { a, _ in a })
        guard table[yVar] != nil else { return nil }
        var parsed: [String: Expr] = [:]
        for (k, v) in table { guard let e = Expr.parse(v) else { return nil }; parsed[k] = e }

        func value(of name: String, x: Double, depth: Int) throws -> Double {
            if name == xVar { return x }
            guard depth < 50 else { throw Expr.EvalError.depth }
            guard let e = parsed[name] else { throw Expr.EvalError.unknownVariable(name) }
            return try e.eval { try value(of: $0, x: x, depth: depth + 1) }
        }
        let steps = 240
        var out: [Sample] = []
        for i in 0...steps {
            let x = xMin + (xMax - xMin) * Double(i) / Double(steps)
            if let y = try? value(of: yVar, x: x, depth: 0), y.isFinite { out.append(Sample(x: x, y: y, series: "Theory")) }
        }
        return out.isEmpty ? nil : (out, "\(yVar) = \(table[yVar] ?? "")")
    }

    private var fit: Fit? {
        let pts = experimental
        guard pts.count >= 3, let first = pts.first, let last = pts.last, last.x != first.x else { return nil }
        let a = last.y - first.y
        guard a != 0 else { return nil }
        let b = 4 / (last.x - first.x)
        let d = a > 0 ? first.y + a / 2 : last.y - a / 2
        var sum = 0.0, count = 0
        for p in pts.dropFirst().dropLast() {
            let r = (p.y - d) / a
            guard abs(r) < 1 else { continue }
            let ci = 0.5 * log((1 + r) / (1 - r)) / b - p.x
            if ci.isFinite { sum += ci; count += 1 }
        }
        guard count > 0 else { return nil }
        return Fit(a: a, b: b, c: sum / Double(count), d: d)
    }

    private var samples: [Sample] {
        var all = theory?.samples ?? []
        all += experimental.map { Sample(x: $0.x, y: $0.y, series: "Experiment") }
        if let f = fit {
            for i in 0...240 {
                let x = xMin + (xMax - xMin) * Double(i) / 240
                all.append(Sample(x: x, y: f.a * tanh(f.b * (x + f.c)) + f.d, series: "Fit"))
            }
        }
        return all
    }

    // MARK: view

    var body: some View {
        HSplitView {
            Form {
                Section("Equations (name = expression)") {
                    ForEach($equations) { $e in
                        HStack {
                            TextField("", text: $e.name, prompt: Text("Var")).frame(width: 64).lineLimit(1)
                            Text("=")
                            TextField("", text: $e.text, prompt: Text("e.g. (C*D)/(B*K)")).lineLimit(1)
                        }
                    }
                    Button("Add row") { equations.append(Equation()) }
                    Text("Operators + − * / ^ and ( ). Functions: sqrt, ln, log, exp, abs, sin, cos, tan, tanh.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Axes") {
                    TextField("X variable", text: $xVar)
                    TextField("Y variable", text: $yVar)
                    LabeledContent("X range") { HStack { TextField("", value: $xMin, format: .number).frame(width: 70); Text("to"); TextField("", value: $xMax, format: .number).frame(width: 70) } }
                    LabeledContent("Y range") { HStack { TextField("", value: $yMin, format: .number).frame(width: 70); Text("to"); TextField("", value: $yMax, format: .number).frame(width: 70) } }
                }
                Section("Experimental points (y, x)") {
                    ForEach($points) { $p in
                        HStack { TextField("", text: $p.y, prompt: Text("y")); TextField("", text: $p.x, prompt: Text("x")) }
                    }
                    Button("Add row") { points.append(Point()) }
                }
                Section {
                    HStack {
                        Button("Load example") { loadExample() }
                        Button("Clear", role: .destructive) { clear() }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
            .onAppear { startupExample() }

            VStack(alignment: .leading, spacing: 10) {
                Chart(samples) { s in
                    if s.series == "Experiment" {
                        PointMark(x: .value("x", s.x), y: .value("y", s.y)).foregroundStyle(by: .value("Series", s.series))
                    } else {
                        LineMark(x: .value("x", s.x), y: .value("y", s.y), series: .value("Series", s.series))
                            .foregroundStyle(by: .value("Series", s.series))
                    }
                }
                .chartForegroundStyleScale(["Theory": Color.red, "Experiment": Color.blue, "Fit": Color.green])
                .chartXScale(domain: xMin...max(xMax, xMin + 1))
                .chartYScale(domain: yMin...max(yMax, yMin + 1))
                .frame(minHeight: 280)

                if let t = theory { Text("Theoretical curve: \(t.formula)").font(.callout) }
                if let f = fit {
                    Text("Approximated curve: \(formatNumber(f.a))·tanh(\(formatNumber(f.b))·(x + \(formatNumber(f.c)))) + \(formatNumber(f.d))")
                        .font(.callout)
                    Text("Equivalence point: x = \(formatNumber(f.equivalence))").font(.headline)
                } else if experimental.count > 0 {
                    Text("Enter at least three experimental points, in increasing x order, to fit a curve.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
        }
    }

    private func startupExample() {
        if ProcessInfo.processInfo.environment["XENON_EXAMPLE"] != nil { loadExample() }
    }

    private func clear() {
        equations = (0..<6).map { _ in Equation() }; points = (0..<8).map { _ in Point() }
        xVar = ""; yVar = ""
    }

    private func loadExample() {
        let rows = [("A", "(C*D)/(B*K)"), ("K", "10^-3"), ("C", "OH"), ("OH", "(10^-14)/H"), ("H", "10^-4"), ("B", "6*(10^-2)")]
        equations = rows.map { var e = Equation(); e.name = $0.0; e.text = $0.1; return e }
        xVar = "D"; yVar = "A"
        xMin = 0; xMax = 60; yMin = 0; yMax = 14
        points = [("7,19", "30"), ("7,64", "30,5"), ("10,02", "31"), ("10,45", "31,5")].map {
            var p = Point(); p.y = $0.0; p.x = $0.1; return p
        }
    }
}
