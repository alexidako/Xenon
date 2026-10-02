import Foundation

/// Small arithmetic expression language: numbers (`,` or `.` decimals), variables, + − * / ^, parentheses,
/// and the functions sqrt, ln, log (base 10), exp, abs, sin, cos, tan, tanh.
indirect enum Expr {
    case number(Double)
    case variable(String)
    case unary(Character, Expr)
    case binary(Character, Expr, Expr)
    case call(String, Expr)

    enum EvalError: Error { case unknownVariable(String), depth, badFunction(String) }

    func eval(_ lookup: (String) throws -> Double) throws -> Double {
        switch self {
        case .number(let v): return v
        case .variable(let n): return try lookup(n)
        case .unary(let op, let e): let v = try e.eval(lookup); return op == "-" ? -v : v
        case .binary(let op, let l, let r):
            let a = try l.eval(lookup), b = try r.eval(lookup)
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            case "/": return a / b
            default: return pow(a, b)
            }
        case .call(let f, let e):
            let v = try e.eval(lookup)
            switch f.lowercased() {
            case "sqrt": return sqrt(v)
            case "ln": return log(v)
            case "log": return log10(v)
            case "exp": return exp(v)
            case "abs": return abs(v)
            case "sin": return sin(v)
            case "cos": return cos(v)
            case "tan": return tan(v)
            case "tanh": return tanh(v)
            default: throw EvalError.badFunction(f)
            }
        }
    }

    static func parse(_ text: String) -> Expr? {
        var p = ExprParser(Array(text.replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }))
        guard let e = p.expression(), p.i == p.cs.count else { return nil }
        return e
    }
}

private struct ExprParser {
    let cs: [Character]; var i = 0
    init(_ cs: [Character]) { self.cs = cs }
    var peek: Character? { i < cs.count ? cs[i] : nil }

    mutating func expression() -> Expr? {
        guard var left = term() else { return nil }
        while let c = peek, c == "+" || c == "-" {
            i += 1
            guard let r = term() else { return nil }
            left = .binary(c, left, r)
        }
        return left
    }
    mutating func term() -> Expr? {
        guard var left = unary() else { return nil }
        while let c = peek, c == "*" || c == "/" {
            i += 1
            guard let r = unary() else { return nil }
            left = .binary(c, left, r)
        }
        return left
    }
    mutating func unary() -> Expr? {
        if let c = peek, c == "-" || c == "+" {
            i += 1
            guard let e = unary() else { return nil }
            return .unary(c, e)
        }
        return power()
    }
    mutating func power() -> Expr? {
        guard let base = primary() else { return nil }
        if peek == "^" {
            i += 1
            guard let exp = unary() else { return nil }   // right-associative, allows 10^-3
            return .binary("^", base, exp)
        }
        return base
    }
    mutating func primary() -> Expr? {
        guard let c = peek else { return nil }
        if c.isNumber || c == "." {
            var s = ""
            while let d = peek, d.isNumber || d == "." { s.append(d); i += 1 }
            // scientific notation like 1e-5
            if let e = peek, e == "e" || e == "E", i + 1 < cs.count, cs[i + 1].isNumber || cs[i + 1] == "-" {
                s.append("e"); i += 1
                if peek == "-" { s.append("-"); i += 1 }
                while let d = peek, d.isNumber { s.append(d); i += 1 }
            }
            return Double(s).map(Expr.number)
        }
        if c.isLetter || c == "_" {
            var name = ""
            while let d = peek, d.isLetter || d.isNumber || d == "_" { name.append(d); i += 1 }
            if peek == "(" {
                i += 1
                guard let arg = expression(), peek == ")" else { return nil }
                i += 1
                return .call(name, arg)
            }
            return .variable(name)
        }
        if c == "(" {
            i += 1
            guard let e = expression(), peek == ")" else { return nil }
            i += 1
            return e
        }
        return nil
    }
}
