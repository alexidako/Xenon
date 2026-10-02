import Foundation

/// Balances chemical equations such as `aCH3CH2OH + bO2 -> cH2O + dCO2`.
/// Variables are single lowercase letters; the solver finds the smallest positive integers that balance
/// every element and the electric charge. (Port of Kalzium's OCaml/FaCiLe "eqchem" solver.)
enum EquationSolver {
    enum Failure: Error, Equatable { case parse(String), notFound }

    struct Term {
        var coefficient: Coefficient
        var atoms: [String: Int]
        var charge: Int
        var text: String
    }
    enum Coefficient: Equatable { case number(Int), variable(Character) }

    // MARK: public API

    struct Entry { let coefficient: Int; let term: Term }
    struct Balanced { let left: [Entry]; let right: [Entry] }

    /// Returns the equation rewritten with all coefficients filled in.
    static func solve(_ input: String, isElement: (String) -> Bool) -> Result<String, Failure> {
        solveStructured(input, isElement: isElement).map { b in
            func fill(_ es: [Entry]) -> String { es.map { ($0.coefficient == 1 ? "" : "\($0.coefficient) ") + $0.term.text }.joined(separator: " + ") }
            return fill(b.left) + " -> " + fill(b.right)
        }
    }

    /// Same, but returns each molecule with its solved coefficient.
    static func solveStructured(_ input: String, isElement: (String) -> Bool) -> Result<Balanced, Failure> {
        let cleaned = input.replacingOccurrences(of: "→", with: "->").replacingOccurrences(of: " ", with: "")
        let sides = cleaned.components(separatedBy: "->")
        guard sides.count == 2 else { return .failure(.parse(tr("missing or duplicate arrow"))) }
        do {
            let left = try sides[0].isEmpty ? [] : splitTerms(sides[0]).map { try parseTerm($0, isElement: isElement) }
            let right = try sides[1].isEmpty ? [] : splitTerms(sides[1]).map { try parseTerm($0, isElement: isElement) }
            guard !left.isEmpty, !right.isEmpty else { return .failure(.parse(tr("both sides need at least one molecule"))) }

            // unknowns: one per distinct variable letter
            let letters = Array(Set((left + right).compactMap { t -> Character? in if case .variable(let c) = t.coefficient { return c }; return nil })).sorted()
            let index = Dictionary(uniqueKeysWithValues: letters.enumerated().map { ($1, $0) })
            let n = letters.count

            // one equation per element (and charge): sum(left) - sum(right) = 0
            var keys = Set<String>()
            for t in left + right { keys.formUnion(t.atoms.keys) }
            var rows: [[Fraction]] = []   // n coefficients + constant term
            for key in keys.sorted() + ["\u{0}charge"] {
                var row = [Fraction](repeating: .zero, count: n + 1)
                for (side, sign) in [(left, 1), (right, -1)] {
                    for t in side {
                        let count = key == "\u{0}charge" ? t.charge : (t.atoms[key] ?? 0)
                        guard count != 0 else { continue }
                        switch t.coefficient {
                        case .number(let k): row[n] = row[n] - Fraction(sign * count * k)   // move constants to the right
                        case .variable(let c): row[index[c]!] = row[index[c]!] + Fraction(sign * count)
                        }
                    }
                }
                rows.append(row)
            }

            guard let solution = solveIntegers(rows, unknowns: n) else { return .failure(.notFound) }
            func entries(_ ts: [Term]) -> [Entry] {
                ts.map { t in
                    switch t.coefficient {
                    case .number(let v): return Entry(coefficient: v, term: t)
                    case .variable(let c): return Entry(coefficient: solution[index[c]!], term: t)
                    }
                }
            }
            return .success(Balanced(left: entries(left), right: entries(right)))
        } catch let f as Failure {
            return .failure(f)
        } catch { return .failure(.parse("\(error)")) }
    }

    // MARK: parsing

    /// Split on `+` that is not inside brackets (charges are written like `[2+]`).
    static func splitTerms(_ s: String) throws -> [String] {
        var out: [String] = [], cur = "", depth = 0
        for ch in s {
            if ch == "[" { depth += 1 } else if ch == "]" { depth -= 1 }
            if depth < 0 { throw Failure.parse(tr("unbalanced brackets")) }
            if ch == "+" && depth == 0 { out.append(cur); cur = "" } else { cur.append(ch) }
        }
        if depth != 0 { throw Failure.parse(tr("unbalanced brackets")) }
        out.append(cur)
        if out.contains(where: \.isEmpty) { throw Failure.parse(tr("empty molecule")) }
        return out
    }

    static func parseTerm(_ s: String, isElement: (String) -> Bool) throws -> Term {
        var chars = Array(s)
        var coefficient = Coefficient.number(1)
        if let f = chars.first, f.isNumber {
            var digits = ""
            while let c = chars.first, c.isNumber { digits.append(c); chars.removeFirst() }
            coefficient = .number(Int(digits) ?? 1)
        } else if chars.count >= 2, chars[0].isLowercase, chars[0].isLetter, chars[1].isUppercase || chars[1] == "(" {
            coefficient = .variable(chars[0]); chars.removeFirst()
        }
        // split off the charge, e.g. "Fe[2+]"
        var charge = 0
        var formulaChars = chars
        if let open = chars.firstIndex(of: "[") {
            guard chars.last == "]" else { throw Failure.parse(tr("bad charge in {s}", ["s": s])) }
            let inner = String(chars[(open + 1)..<(chars.count - 1)])
            let sign = inner.contains("-") ? -1 : 1
            guard inner.contains("+") != inner.contains("-") else { throw Failure.parse(tr("bad charge in {s}", ["s": s])) }
            let digits = inner.filter(\.isNumber)
            charge = sign * (digits.isEmpty ? 1 : Int(digits) ?? 1)
            formulaChars = Array(chars[..<open])
        }
        guard !formulaChars.isEmpty else { throw Failure.parse(tr("missing formula in {s}", ["s": s])) }
        var pos = 0
        let atoms = try parseGroup(formulaChars, &pos, isElement: isElement, top: true)
        guard pos == formulaChars.count else { throw Failure.parse(tr("unexpected character in {s}", ["s": s])) }
        return Term(coefficient: coefficient, atoms: atoms, charge: charge, text: String(chars))
    }

    private static func parseGroup(_ c: [Character], _ pos: inout Int, isElement: (String) -> Bool, top: Bool) throws -> [String: Int] {
        var atoms: [String: Int] = [:]
        while pos < c.count {
            var group: [String: Int]
            if c[pos].isUppercase {
                var sym = String(c[pos]); pos += 1
                while pos < c.count, c[pos].isLowercase { sym.append(c[pos]); pos += 1 }
                guard isElement(sym) else { throw Failure.parse(tr("unknown element {sym}", ["sym": sym])) }
                group = [sym: 1]
            } else if c[pos] == "(" {
                pos += 1
                group = try parseGroup(c, &pos, isElement: isElement, top: false)
                guard pos < c.count, c[pos] == ")" else { throw Failure.parse(tr("missing )")) }
                pos += 1
            } else if c[pos] == ")" {
                if top { throw Failure.parse(tr("unexpected )")) }
                return atoms
            } else { throw Failure.parse(tr("unexpected '{ch}'", ["ch": String(c[pos])])) }
            var digits = ""
            while pos < c.count, c[pos].isNumber { digits.append(c[pos]); pos += 1 }
            let mult = Int(digits) ?? 1
            for (k, v) in group { atoms[k, default: 0] += v * mult }
        }
        if !top { throw Failure.parse(tr("missing )")) }
        return atoms
    }

    // MARK: linear algebra over the rationals

    /// Rows are [a1 ... an | rhs]. Returns the smallest positive integer solution, if any.
    static func solveIntegers(_ input: [[Fraction]], unknowns n: Int) -> [Int]? {
        if n == 0 { return input.allSatisfy { $0[0] == .zero } ? [] : nil }
        var m = input
        var pivotCols: [Int] = []
        var r = 0
        for col in 0..<n where r < m.count {
            guard let p = (r..<m.count).first(where: { m[$0][col] != .zero }) else { continue }
            m.swapAt(r, p)
            let inv = m[r][col]
            m[r] = m[r].map { $0 / inv }
            for i in 0..<m.count where i != r && m[i][col] != .zero {
                let f = m[i][col]
                m[i] = zip(m[i], m[r]).map { $0 - f * $1 }
            }
            pivotCols.append(col); r += 1
        }
        // inconsistent rows: 0 = nonzero
        for i in r..<m.count where m[i][n] != .zero { return nil }
        let free = (0..<n).filter { !pivotCols.contains($0) }
        guard free.count <= 3 else { return nil }

        func evaluate(_ freeValues: [Int]) -> [Int]? {
            var x = [Fraction](repeating: .zero, count: n)
            for (k, col) in free.enumerated() { x[col] = Fraction(freeValues[k]) }
            for (row, col) in pivotCols.enumerated() {
                var v = m[row][n]
                for (k, fc) in free.enumerated() { v = v - m[row][fc] * Fraction(freeValues[k]) }
                x[col] = v
            }
            var out: [Int] = []
            for v in x { guard v.den == 1, v.num > 0 else { return nil }; out.append(v.num) }
            return out
        }
        if free.isEmpty { return evaluate([]) }
        // smallest total first
        let limit = free.count == 1 ? 400 : free.count == 2 ? 40 : 14
        var best: [Int]?, bestSum = Int.max
        func search(_ depth: Int, _ vals: [Int]) {
            if depth == free.count {
                if let sol = evaluate(vals), sol.reduce(0, +) < bestSum { best = sol; bestSum = sol.reduce(0, +) }
                return
            }
            for v in 1...limit { search(depth + 1, vals + [v]) }
        }
        search(0, [])
        return best
    }
}

struct Fraction: Equatable {
    var num: Int
    var den: Int
    static let zero = Fraction(0)

    init(_ n: Int) { num = n; den = 1 }
    init(_ n: Int, _ d: Int) {
        let g = Fraction.gcd(abs(n), abs(d))
        let s = d < 0 ? -1 : 1
        num = s * n / max(g, 1); den = s * d / max(g, 1)
    }
    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    static func + (a: Fraction, b: Fraction) -> Fraction { Fraction(a.num * b.den + b.num * a.den, a.den * b.den) }
    static func - (a: Fraction, b: Fraction) -> Fraction { Fraction(a.num * b.den - b.num * a.den, a.den * b.den) }
    static func * (a: Fraction, b: Fraction) -> Fraction { Fraction(a.num * b.num, a.den * b.den) }
    static func / (a: Fraction, b: Fraction) -> Fraction { Fraction(a.num * b.den, a.den * b.num) }
}
