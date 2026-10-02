import Foundation
import simd
import SceneKit

/// Works out where each atom's orbitals point in a molecule: σ lobes toward bonded atoms, lone pairs in the
/// remaining space, and the p axes that make π bonds. Based on the valence bond analysis plus the 3D coordinates.
enum MolecularOrbitals {
    struct Lobe { let atom: Int; let direction: V3; let hybrid: String }
    struct PiBond { let a: Int; let b: Int; let axis: V3 }
    struct Result {
        var sigma: [Lobe] = []
        var lonePairs: [Lobe] = []
        var pi: [PiBond] = []
        var hydrogens: [Int] = []          // atoms drawn with a 1s orbital
    }

    static func analyze(_ m: Molecule) -> Result {
        let info = VBT.analyze(m).atoms
        func pos(_ i: Int) -> V3 { V3(m.atoms[i].x, m.atoms[i].y, m.atoms[i].z) }
        func dir(from i: Int, to j: Int) -> V3 { normalize(pos(j) - pos(i)) }
        var res = Result()

        // π bonds: one axis per extra bond order
        var piAxes: [Int: [V3]] = [:]            // atom → axes of its π bonds
        var sp2Doubles: [Int: Int] = [:]          // how many double bonds an sp atom has used so far
        for b in m.bonds where b.order >= 2 && b.a < m.atoms.count && b.b < m.atoms.count {
            let ha = info[b.a].hybrid, hb = info[b.b].hybrid
            guard ha?.hybridName != nil || hb?.hybridName != nil else { continue }
            let spAtom: Int? = ha?.steric == 2 ? b.a : (hb?.steric == 2 ? b.b : nil)
            var axes: [V3] = []
            if let sp = spAtom {
                let other = sp == b.a ? b.b : b.a
                let u = dir(from: sp, to: other)
                let a1 = OrbitalMath.perpendicular(to: u), a2 = normalize(simd_cross(u, a1))
                if b.order >= 3 { axes = [a1, a2] }
                else { let k = sp2Doubles[sp, default: 0]; sp2Doubles[sp] = k + 1; axes = [k % 2 == 0 ? a1 : a2] }
            } else {
                axes = [planeNormal(of: info[b.a].neighbors.count >= info[b.b].neighbors.count ? b.a : b.b, info: info, pos: pos)]
                if b.order == 3 { axes.append(normalize(simd_cross(dir(from: b.a, to: b.b), axes[0]))) }
            }
            for ax in axes {
                res.pi.append(PiBond(a: b.a, b: b.b, axis: ax))
                piAxes[b.a, default: []].append(ax); piAxes[b.b, default: []].append(ax)
            }
        }

        for (i, a) in info.enumerated() {
            if a.element?.symbol == "H" { res.hydrogens.append(i); continue }
            guard let h = a.hybrid, let name = h.hybridName else { continue }
            let nb = a.neighbors.map { dir(from: i, to: $0) }
            for u in nb { res.sigma.append(Lobe(atom: i, direction: u, hybrid: name)) }
            for u in lonePairDirections(h, neighbors: nb, piAxis: piAxes[i]?.first) {
                res.lonePairs.append(Lobe(atom: i, direction: u, hybrid: name))
            }
        }
        return res
    }

    /// Normal of the plane an sp² atom sits in.
    static func planeNormal(of i: Int, info: [VBT.AtomAnalysis], pos: (Int) -> V3) -> V3 {
        func normal(_ c: Int, _ nbrs: [Int]) -> V3? {
            guard nbrs.count >= 2 else { return nil }
            let n = simd_cross(pos(nbrs[0]) - pos(c), pos(nbrs[1]) - pos(c))
            return simd_length(n) > 1e-3 ? normalize(n) : nil
        }
        if let n = normal(i, info[i].neighbors) { return n }
        if let first = info[i].neighbors.first {
            if let n = normal(first, info[first].neighbors) { return n }
            return OrbitalMath.perpendicular(to: pos(first) - pos(i))
        }
        return V3(0, 0, 1)
    }

    /// Directions of an atom's lone pairs from its bonds (VSEPR positions).
    static func lonePairDirections(_ h: Hybridization, neighbors nb: [V3], piAxis: V3?) -> [V3] {
        let lp = h.lonePairs
        guard lp > 0 else { return [] }
        func sum() -> V3 { nb.reduce(V3(0, 0, 0), +) }
        switch (h.steric, nb.count) {
        case (2, 1): return [-nb[0]]
        case (3, 2): return [-normalize(sum())]
        case (3, 1):
            let ax = piAxis ?? OrbitalMath.perpendicular(to: nb[0])
            let t = normalize(simd_cross(ax, nb[0])), c = cos(2 * Double.pi / 3), s = sin(2 * Double.pi / 3)
            return [nb[0] * c + t * s, nb[0] * c - t * s]
        case (4, 3): return [-normalize(sum())]
        case (4, 2):
            let b = normalize(nb[0] + nb[1]), n = normalize(simd_cross(nb[0], nb[1])), phi = 54.75 * Double.pi / 180
            return [-b * cos(phi) + n * sin(phi), -b * cos(phi) - n * sin(phi)]
        case (4, 1):
            let p1 = OrbitalMath.perpendicular(to: nb[0]), p2 = normalize(simd_cross(nb[0], p1)), th = 109.5 * Double.pi / 180
            return (0..<3).map { k in
                let a = Double(k) * 2 * .pi / 3
                return nb[0] * cos(th) + (p1 * cos(a) + p2 * sin(a)) * sin(th)
            }
        default:
            return farthestDirections(count: lp, avoiding: nb + nb.map { -$0 }.filter { _ in false })
        }
    }

    /// Fallback for crowded atoms (sp³d, sp³d²): pick directions that stay as far from everything else as possible.
    static func farthestDirections(count: Int, avoiding fixed: [V3]) -> [V3] {
        let n = 200
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let candidates = (0..<n).map { i -> V3 in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(n), r = (1 - y * y).squareRoot(), t = golden * Double(i)
            return V3(r * cos(t), y, r * sin(t))
        }
        var chosen = fixed
        var out: [V3] = []
        for _ in 0..<count {
            let best = candidates.max { a, b in
                (chosen.map { simd_dot(a, $0) }.max() ?? -1) > (chosen.map { simd_dot(b, $0) }.max() ?? -1)
            }!
            out.append(best); chosen.append(best)
        }
        return out
    }
}

@MainActor enum OrbitalSelfTest {
    static func run() {
        // shapes
        let px = OrbitalMath.atomicFunction("px"), pz = OrbitalMath.atomicFunction("pz"), s = OrbitalMath.atomicFunction("s")
        SelfTest.check(abs(px(V3(0, 1, 0))) < 1e-12 && px(V3(1, 0, 0)) > 0 && px(V3(-1, 0, 0)) < 0, "orbitals: px has a node on the yz plane and opposite signs on its lobes")
        SelfTest.check(abs(OrbitalMath.overlap(s, s) - 1) < 1e-3 && abs(OrbitalMath.overlap(px, px) - 1) < 1e-3, "orbitals: s and p are normalized")
        SelfTest.check(abs(OrbitalMath.overlap(s, px)) < 1e-3 && abs(OrbitalMath.overlap(px, pz)) < 1e-3, "orbitals: s ⟂ p and px ⟂ pz")
        let dz2 = OrbitalMath.atomicFunction("dz2")
        SelfTest.check(dz2(V3(0, 0, 1)) > 0 && dz2(V3(1, 0, 0)) < 0 && abs(OrbitalMath.overlap(dz2, dz2) - 1) < 1e-3, "orbitals: dz² has + lobes on z, a − ring in the xy plane, and is normalized")
        let dxy = OrbitalMath.atomicFunction("dxy"), dx2 = OrbitalMath.atomicFunction("dx2y2")
        SelfTest.check(abs(OrbitalMath.overlap(dxy, dx2)) < 1e-3 && abs(OrbitalMath.overlap(dxy, dxy) - 1) < 1e-3, "orbitals: dxy ⟂ dx²−y² and normalized")

        // hybrid sets must be orthonormal
        for h in OrbitalMath.hybrids where h.id == "sp" || h.id == "sp2" || h.id == "sp3" {
            let lobes = h.directions.map { OrbitalMath.hybridLobe(cs: h.cs, cp: h.cp, direction: $0) }
            var worst = 0.0
            for i in 0..<lobes.count {
                for j in 0..<lobes.count {
                    let target = i == j ? 1.0 : 0.0
                    worst = max(worst, abs(OrbitalMath.overlap(lobes[i], lobes[j], nLat: 90, nLon: 180) - target))
                }
            }
            SelfTest.check(worst < 2e-3, "orbitals: \(h.name) hybrids are orthonormal", "worst deviation \(worst)")
        }
        let sp3 = OrbitalMath.hybridLobe(cs: 0.5, cp: 0.75.squareRoot(), direction: V3(0, 0, 1))
        SelfTest.check(sp3(V3(0, 0, 1)) > 0 && sp3(V3(0, 0, -1)) < 0 && abs(sp3(V3(0, 0, 1))) > 1.9 * abs(sp3(V3(0, 0, -1))), "orbitals: an sp³ lobe is large in front, with a small opposite-phase lobe behind")

        // placement in real molecules
        func lobes(_ m: Molecule, _ symbol: String, nth: Int = 0) -> (sigma: [V3], lp: [V3], pi: [V3])? {
            let idx = m.atoms.indices.filter { m.atoms[$0].symbol == symbol }
            guard nth < idx.count else { return nil }
            let a = idx[nth], r = MolecularOrbitals.analyze(m)
            return (r.sigma.filter { $0.atom == a }.map(\.direction), r.lonePairs.filter { $0.atom == a }.map(\.direction),
                    r.pi.filter { $0.a == a || $0.b == a }.map(\.axis))
        }
        func template(_ name: String) -> Molecule { Embed3D.embed(SketchTemplates.make(name, cx: 0, cy: 0), name: name) }
        func angle(_ a: V3, _ b: V3) -> Double { acos(max(-1, min(1, simd_dot(normalize(a), normalize(b))))) * 180 / .pi }

        if let m = MoleculeLibrary.bundled.first(where: { $0.name == "Methane" }), let c = lobes(m, "C") {
            let bonds = m.atoms.indices.filter { m.atoms[$0].symbol == "H" }.map { normalize(V3(m.atoms[$0].x - m.atoms[0].x, m.atoms[$0].y - m.atoms[0].y, m.atoms[$0].z - m.atoms[0].z)) }
            SelfTest.check(c.sigma.count == 4 && c.lp.isEmpty && c.pi.isEmpty && bonds.count == 4, "orbitals in methane: 4 σ lobes, no lone pairs or π", "\(c.sigma.count) \(c.lp.count) \(c.pi.count)")
        } else { SelfTest.check(false, "orbitals in methane") }

        let nh3 = template("Ammonia")
        if let n = lobes(nh3, "N") {
            let away = -normalize(n.sigma.reduce(V3(0, 0, 0), +))
            SelfTest.check(n.sigma.count == 3 && n.lp.count == 1 && simd_dot(n.lp[0], away) > 0.99, "orbitals in ammonia: 3 σ lobes and the lone pair opposite them")
        } else { SelfTest.check(false, "orbitals in ammonia") }

        let h2o = template("Water")
        if let o = lobes(h2o, "O") {
            let between = o.lp.count == 2 ? angle(o.lp[0], o.lp[1]) : 0
            let toBonds = o.lp.flatMap { l in o.sigma.map { angle(l, $0) } }
            SelfTest.check(o.sigma.count == 2 && o.lp.count == 2 && between > 100 && between < 125 && toBonds.allSatisfy { $0 > 95 && $0 < 125 },
                           "orbitals in water: 2 σ lobes and 2 lone pairs ≈109° from everything", "lp–lp \(between) lp–bond \(toBonds)")
        } else { SelfTest.check(false, "orbitals in water") }

        let ethene = template("Ethene")
        if let c = lobes(ethene, "C") {
            let n = normalize(simd_cross(c.sigma[0], c.sigma[1]))
            SelfTest.check(c.sigma.count == 3 && c.pi.count == 1 && abs(simd_dot(c.pi[0], n)) > 0.98, "orbitals in ethene: 3 σ lobes and a π p-orbital perpendicular to the molecular plane",
                           "σ \(c.sigma.count) π \(c.pi.count)")
        } else { SelfTest.check(false, "orbitals in ethene") }

        let ethyne = template("Ethyne")
        if let c = lobes(ethyne, "C") {
            let axisBond = c.sigma[0]
            SelfTest.check(c.pi.count == 2 && abs(simd_dot(c.pi[0], axisBond)) < 0.05 && abs(simd_dot(c.pi[1], axisBond)) < 0.05 && abs(simd_dot(c.pi[0], c.pi[1])) < 0.05,
                           "orbitals in ethyne: two perpendicular π p-orbitals, both ⟂ the bond", "\(c.pi.count)")
        } else { SelfTest.check(false, "orbitals in ethyne") }

        let acetone = template("Acetone")
        if let o = lobes(acetone, "O") {
            let ok = o.sigma.count == 1 && o.pi.count == 1 && o.lp.count == 2 && o.lp.allSatisfy { abs(simd_dot($0, o.pi[0])) < 0.15 && abs(angle($0, o.sigma[0]) - 120) < 10 }
            SelfTest.check(ok, "orbitals in acetone: carbonyl O has σ toward C, a π p-orbital, and two lone pairs in the plane ≈120° from the bond",
                           "σ \(o.sigma.count) π \(o.pi.count) lp \(o.lp.count) lp·π \(o.lp.map { simd_dot($0, o.pi[0]) }) lp–bond° \(o.lp.map { angle($0, o.sigma[0]) }) π·bond \(simd_dot(o.pi[0], o.sigma[0]))")
        } else { SelfTest.check(false, "orbitals in acetone") }
    }
}

@MainActor enum OverlayFilterSelfTest {
    static func run() {
        guard let m = MoleculeLibrary.bundled.first(where: { $0.name == "Ethanol" }) else { SelfTest.check(false, "overlay filter: ethanol found"); return }
        let pts = m.atoms.map { SCNVector3(CGFloat($0.x), CGFloat($0.y), CGFloat($0.z)) }
        let all = OrbitalOverlay.nodes(for: m, pts: pts, mode: .all).count
        let info = VBT.analyze(m).atoms
        let o = info.first { $0.element?.symbol == "O" }!.index
        let oOnly = OrbitalOverlay.nodes(for: m, pts: pts, mode: .all, atoms: [o]).count
        let none = OrbitalOverlay.nodes(for: m, pts: pts, mode: .off, atoms: [o]).count
        // O: 2 σ lobes + 2 lone pairs + the 1s sphere of the H bonded to it
        SelfTest.check(oOnly == 5 && all > oOnly && none == 0, "overlay filter: oxygen alone in ethanol shows 5 shapes (2 σ + 2 lone pairs + its H), all atoms show more", "O only \(oOnly), all \(all), off \(none)")
        let empty = OrbitalOverlay.nodes(for: m, pts: pts, mode: .all, atoms: []).count
        SelfTest.check(empty == all, "overlay filter: an empty selection means every atom", "\(empty) vs \(all)")
        let ethene = Embed3D.embed(SketchTemplates.make("Ethene", cx: 0, cy: 0), name: "e")
        let ep = ethene.atoms.map { SCNVector3(CGFloat($0.x), CGFloat($0.y), CGFloat($0.z)) }
        let c0 = VBT.analyze(ethene).atoms.first { $0.element?.symbol == "C" }!.index
        let withPi = OrbitalOverlay.nodes(for: ethene, pts: ep, mode: .all, atoms: [c0]).count
        let noPi = OrbitalOverlay.nodes(for: ethene, pts: ep, mode: .bonds, atoms: [c0]).count
        SelfTest.check(withPi - noPi == 2, "overlay filter: selecting one carbon of C=C still shows the whole π bond (both p lobes)", "\(withPi) vs \(noPi)")
    }
}
