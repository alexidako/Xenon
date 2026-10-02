import Foundation

struct SketchAtom: Identifiable, Hashable {
    var id = UUID()
    var symbol: String
    var x: Double
    var y: Double
}

struct SketchBond: Identifiable, Hashable {
    var id = UUID()
    var a: UUID
    var b: UUID
    var order: Int
}

/// A 2D drawing of a molecule. Hydrogens on heavy atoms are implicit (filled in from valence) until "Add hydrogens".
struct Sketch: Equatable {
    var atoms: [SketchAtom] = []
    var bonds: [SketchBond] = []

    static let bondLength = 46.0

    static let valences: [String: [Int]] = [
        "H": [1], "B": [3], "C": [4], "N": [3, 5], "O": [2], "F": [1], "Si": [4], "P": [3, 5], "S": [2, 4, 6],
        "Cl": [1], "Se": [2, 4, 6], "Br": [1], "I": [1, 3, 5],
    ]

    func atom(_ id: UUID) -> SketchAtom? { atoms.first { $0.id == id } }

    func bonds(of id: UUID) -> [SketchBond] { bonds.filter { $0.a == id || $0.b == id } }

    func neighbors(of id: UUID) -> [UUID] { bonds(of: id).map { $0.a == id ? $0.b : $0.a } }

    func bondOrderSum(_ id: UUID) -> Int { bonds(of: id).reduce(0) { $0 + $1.order } }

    /// Hydrogens needed to complete the atom's valence. nil means the atom has too many bonds.
    func implicitHydrogens(_ id: UUID) -> Int? {
        guard let a = atom(id), let options = Sketch.valences[a.symbol] else { return 0 }   // metals etc.: no guessing
        let s = bondOrderSum(id)
        guard let v = options.first(where: { $0 >= s }) else { return nil }
        return v - s
    }

    /// Atoms with more bonds than any valence allows.
    var problems: [(atom: SketchAtom, message: String)] {
        atoms.compactMap { a in
            implicitHydrogens(a.id) == nil
                ? (a, "\(a.symbol) has \(bondOrderSum(a.id)) bonds; at most \(Sketch.valences[a.symbol]?.max() ?? 0) are allowed.") : nil
        }
    }

    /// Element counts including implicit hydrogens.
    var counts: [String: Int] {
        var c: [String: Int] = [:]
        for a in atoms { c[a.symbol, default: 0] += 1; c["H", default: 0] += implicitHydrogens(a.id) ?? 0 }
        return c.filter { $0.value > 0 }
    }

    /// Hill order: C, H, then alphabetical.
    var formula: String {
        let c = counts
        func part(_ s: String) -> String { c[s].map { $0 == 1 ? s : "\(s)\($0)" } ?? "" }
        var out = c["C"] != nil ? part("C") + part("H") : ""
        for s in c.keys.sorted() where !(c["C"] != nil && (s == "C" || s == "H")) { out += part(s) }
        return out
    }

    var mass: Double {
        let m = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0.mass ?? 0) })
        return counts.reduce(0) { $0 + (m[$1.key] ?? 0) * Double($1.value) }
    }

    // MARK: hydrogens

    /// A copy with every implicit hydrogen drawn as its own atom, placed in the biggest free angle around its parent.
    func addingHydrogens() -> Sketch {
        var s = self
        for a in atoms {
            guard let n = implicitHydrogens(a.id), n > 0 else { continue }
            var angles = neighbors(of: a.id).compactMap { id -> Double? in
                guard let o = s.atom(id) else { return nil }
                return atan2(o.y - a.y, o.x - a.x)
            }
            for _ in 0..<n {
                let dir = Sketch.largestGapMiddle(angles)
                angles.append(dir)
                let h = SketchAtom(symbol: "H", x: a.x + cos(dir) * Sketch.bondLength * 0.75, y: a.y + sin(dir) * Sketch.bondLength * 0.75)
                s.atoms.append(h)
                s.bonds.append(SketchBond(a: a.id, b: h.id, order: 1))
            }
        }
        return s
    }

    static func largestGapMiddle(_ angles: [Double]) -> Double {
        guard !angles.isEmpty else { return -Double.pi / 2 }
        let sorted = angles.map { a -> Double in var x = a.truncatingRemainder(dividingBy: 2 * .pi); if x < 0 { x += 2 * .pi }; return x }.sorted()
        var best = (gap: -1.0, mid: 0.0)
        for i in 0..<sorted.count {
            let next = i + 1 < sorted.count ? sorted[i + 1] : sorted[0] + 2 * .pi
            let gap = next - sorted[i]
            if gap > best.gap { best = (gap, sorted[i] + gap / 2) }
        }
        return best.mid
    }

    // MARK: conversion

    /// Flat (z = 0) molecule at about 1.5 Å per bond; used for export of the 2D drawing.
    func toMolecule(name: String) -> Molecule {
        let full = addingHydrogens()
        let index = Dictionary(uniqueKeysWithValues: full.atoms.enumerated().map { ($1.id, $0) })
        let scale = 1.5 / Sketch.bondLength
        return Molecule(name: name,
                        atoms: full.atoms.map { MolAtom(symbol: $0.symbol, x: $0.x * scale, y: -$0.y * scale, z: 0) },
                        bonds: full.bonds.compactMap { b in
                            guard let i = index[b.a], let j = index[b.b] else { return nil }
                            return MolBond(a: i, b: j, order: b.order)
                        })
    }
}

// MARK: templates

enum SketchTemplates {
    static let names = ["Water", "Methane", "Ammonia", "Ethanol", "Propane", "Acetone", "Acetic acid", "Ethene", "Ethyne",
                        "Carbon dioxide", "Benzene", "Cyclohexane"]

    private static let L = Sketch.bondLength

    /// Template centred on (cx, cy).
    static func make(_ name: String, cx: Double, cy: Double) -> Sketch {
        var s = Sketch()
        @discardableResult func add(_ sym: String, _ x: Double, _ y: Double) -> UUID {
            let a = SketchAtom(symbol: sym, x: cx + x, y: cy + y); s.atoms.append(a); return a.id
        }
        func bond(_ a: UUID, _ b: UUID, _ order: Int = 1) { s.bonds.append(SketchBond(a: a, b: b, order: order)) }
        let dx = L * cos(.pi / 6), dy = L * sin(.pi / 6)

        switch name {
        case "Water": add("O", 0, 0)
        case "Methane": add("C", 0, 0)
        case "Ammonia": add("N", 0, 0)
        case "Ethanol", "Propane":
            let last = name == "Ethanol" ? "O" : "C"
            let a = add("C", -dx, dy / 2), b = add("C", 0, -dy / 2), c = add(last, dx, dy / 2)
            bond(a, b); bond(b, c)
        case "Acetone":
            let a = add("C", -dx, dy / 2), b = add("C", 0, -dy / 2), c = add("C", dx, dy / 2), o = add("O", 0, -dy / 2 - L)
            bond(a, b); bond(b, c); bond(b, o, 2)
        case "Acetic acid":
            let a = add("C", -dx, dy / 2), b = add("C", 0, -dy / 2), o1 = add("O", 0, -dy / 2 - L), o2 = add("O", dx, dy / 2)
            bond(a, b); bond(b, o1, 2); bond(b, o2)
        case "Ethene": let a = add("C", -L / 2, 0), b = add("C", L / 2, 0); bond(a, b, 2)
        case "Ethyne": let a = add("C", -L / 2, 0), b = add("C", L / 2, 0); bond(a, b, 3)
        case "Carbon dioxide":
            let o1 = add("O", -L, 0), c = add("C", 0, 0), o2 = add("O", L, 0); bond(o1, c, 2); bond(c, o2, 2)
        case "Benzene", "Cyclohexane":
            let r = L / (2 * sin(.pi / 6))
            let ids = (0..<6).map { k -> UUID in
                let t = -Double.pi / 2 + Double(k) * .pi / 3
                return add("C", r * cos(t), r * sin(t))
            }
            for k in 0..<6 { bond(ids[k], ids[(k + 1) % 6], name == "Benzene" && k % 2 == 0 ? 2 : 1) }
        default: break
        }
        return s
    }
}
