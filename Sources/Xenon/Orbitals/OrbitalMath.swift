import Foundation
import simd

typealias V3 = SIMD3<Double>

/// Angular parts of atomic orbitals and of hybrids, evaluated at a unit vector. Radial parts are ignored on purpose:
/// the pictures show shape and phase, which is what bonding diagrams are about. Surfaces are drawn at r = ψ².
enum OrbitalMath {
    static let ys = 0.28209479        // 1 / (2√π)
    static let yp = 0.48860251        // √(3 / 4π)
    static let yd = 0.31539157        // ¼√(5/π)   (d_z²)
    static let yd2 = 1.09254843       // ½√(15/π)
    static let yd3 = 0.54627422       // ¼√(15/π)

    struct Atomic: Identifiable, Hashable {
        let id: String
        let label: String
        let kind: String
    }

    static let atomic: [Atomic] = [
        Atomic(id: "s", label: "s", kind: "1 lobe, no node"),
        Atomic(id: "px", label: "pₓ", kind: "2 lobes, node plane yz"),
        Atomic(id: "py", label: "p_y", kind: "2 lobes, node plane xz"),
        Atomic(id: "pz", label: "p_z", kind: "2 lobes, node plane xy"),
        Atomic(id: "dz2", label: "d_z²", kind: "2 lobes and a ring"),
        Atomic(id: "dxz", label: "d_xz", kind: "4 lobes"),
        Atomic(id: "dyz", label: "d_yz", kind: "4 lobes"),
        Atomic(id: "dxy", label: "d_xy", kind: "4 lobes"),
        Atomic(id: "dx2y2", label: "d_x²−y²", kind: "4 lobes on the axes"),
    ]

    static func atomicFunction(_ id: String) -> (V3) -> Double {
        switch id {
        case "s": return { _ in ys }
        case "px": return { yp * $0.x }
        case "py": return { yp * $0.y }
        case "pz": return { yp * $0.z }
        case "dz2": return { yd * (3 * $0.z * $0.z - 1) }
        case "dxz": return { yd2 * $0.x * $0.z }
        case "dyz": return { yd2 * $0.y * $0.z }
        case "dxy": return { yd2 * $0.x * $0.y }
        case "dx2y2": return { yd3 * ($0.x * $0.x - $0.y * $0.y) }
        default: return { _ in 0 }
        }
    }

    /// p orbital pointing along `axis`.
    static func p(axis: V3) -> (V3) -> Double { let a = normalize(axis); return { yp * simd_dot($0, a) } }

    // MARK: hybrids

    struct HybridKind: Identifiable, Hashable {
        let id: String
        let name: String
        let cs: Double      // s coefficient of one lobe
        let cp: Double      // p coefficient
        let directions: [V3]
        let note: String
    }

    static func unit(_ x: Double, _ y: Double, _ z: Double) -> V3 { normalize(V3(x, y, z)) }

    static let hybrids: [HybridKind] = {
        let tet = [unit(1, 1, 1), unit(1, -1, -1), unit(-1, 1, -1), unit(-1, -1, 1)]
        let trig = (0..<3).map { k -> V3 in let t = Double(k) * 2 * .pi / 3; return V3(cos(t), sin(t), 0) }
        return [
            HybridKind(id: "sp", name: "sp", cs: 0.5.squareRoot(), cp: 0.5.squareRoot(), directions: [V3(0, 0, 1), V3(0, 0, -1)],
                       note: "One s and one p orbital mix into two hybrids 180° apart. Two p orbitals are left over for π bonds."),
            HybridKind(id: "sp2", name: "sp²", cs: (1.0 / 3).squareRoot(), cp: (2.0 / 3).squareRoot(), directions: trig,
                       note: "One s and two p orbitals give three hybrids at 120° in a plane. The leftover p orbital stands perpendicular to that plane."),
            HybridKind(id: "sp3", name: "sp³", cs: 0.5, cp: 0.75.squareRoot(), directions: tet,
                       note: "One s and three p orbitals give four hybrids pointing to the corners of a tetrahedron (109.5°)."),
            HybridKind(id: "sp3d", name: "sp³d (schematic)", cs: 0.5, cp: 0.75.squareRoot(),
                       directions: trig + [V3(0, 0, 1), V3(0, 0, -1)],
                       note: "Five hybrids: three in a plane at 120° and two axial. Drawn with the sp³ lobe shape; the d contribution is not rendered."),
            HybridKind(id: "sp3d2", name: "sp³d² (schematic)", cs: 0.5, cp: 0.75.squareRoot(),
                       directions: [V3(1, 0, 0), V3(-1, 0, 0), V3(0, 1, 0), V3(0, -1, 0), V3(0, 0, 1), V3(0, 0, -1)],
                       note: "Six hybrids to the corners of an octahedron (90°). Drawn with the sp³ lobe shape; the d contribution is not rendered."),
        ]
    }()

    static func hybridKind(named n: String?) -> HybridKind? {
        guard let n else { return nil }
        let key = ["sp": "sp", "sp²": "sp2", "sp³": "sp3", "sp³d": "sp3d", "sp³d²": "sp3d2"][n] ?? n
        return hybrids.first { $0.id == key }
    }

    /// One hybrid lobe pointing along `d`: cs·s + cp·p_d. Unit norm because cs² + cp² = 1.
    static func hybridLobe(cs: Double, cp: Double, direction d: V3) -> (V3) -> Double {
        let n = normalize(d)
        return { cs * ys + cp * yp * simd_dot($0, n) }
    }

    // MARK: numerics (used by tests)

    /// ∫ f·g dΩ over the unit sphere (midpoint rule).
    static func overlap(_ f: (V3) -> Double, _ g: (V3) -> Double, nLat: Int = 120, nLon: Int = 240) -> Double {
        var sum = 0.0
        let dt = Double.pi / Double(nLat), dp = 2 * Double.pi / Double(nLon)
        for i in 0..<nLat {
            let th = (Double(i) + 0.5) * dt
            let w = sin(th) * dt * dp
            for j in 0..<nLon {
                let ph = (Double(j) + 0.5) * dp
                let u = V3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th))
                sum += f(u) * g(u) * w
            }
        }
        return sum
    }

    static func perpendicular(to v: V3) -> V3 {
        let u = normalize(v)
        let ref = abs(u.x) < 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)
        return normalize(ref - simd_dot(ref, u) * u)
    }
}
