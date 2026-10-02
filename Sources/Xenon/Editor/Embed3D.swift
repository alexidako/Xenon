import Foundation

/// Turns a 2D sketch into plausible 3D coordinates. Not a force field: it relaxes bond lengths, ideal bond angles
/// (from valence bond theory) and atom repulsion until the structure settles.
enum Embed3D {
    private struct V { var x = 0.0, y = 0.0, z = 0.0 }

    /// Ideal angle (degrees) between two bonds at an atom, from its bonding and lone pairs.
    static func idealAngle(_ e: Element?, sigma: Int, pi: Int) -> Double {
        if let e, let h = Hybridization.make(e, sigma: sigma, pi: pi) {
            switch (h.steric, h.lonePairs) {
            case (2, _): return 180
            case (3, 0): return 120
            case (3, _): return 117
            case (4, 0): return 109.5
            case (4, 1): return 107
            case (4, _): return 104.5
            case (5, _): return 105
            case (6, _): return 90
            default: break
            }
        }
        switch sigma { case 2: return pi >= 2 ? 180 : 109.5; case 3: return 120; default: return 109.5 }
    }

    static func embed(_ sketch: Sketch, name: String) -> Molecule {
        let s = sketch.addingHydrogens()
        let n = s.atoms.count
        guard n > 0 else { return Molecule(name: name, atoms: [], bonds: []) }
        let index = Dictionary(uniqueKeysWithValues: s.atoms.enumerated().map { ($1.id, $0) })
        let bySymbol = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0) })

        struct B { let i: Int, j: Int, order: Int }
        let bonds = s.bonds.compactMap { b -> B? in
            guard let i = index[b.a], let j = index[b.b] else { return nil }
            return B(i: i, j: j, order: b.order)
        }
        var nbrs = [[Int]](repeating: [], count: n)
        var pi = [Int](repeating: 0, count: n)
        for b in bonds { nbrs[b.i].append(b.j); nbrs[b.j].append(b.i); pi[b.i] += b.order - 1; pi[b.j] += b.order - 1 }

        func cov(_ i: Int) -> Double { bySymbol[s.atoms[i].symbol]?.radiusCovalent ?? 0.8 }
        func r0(_ b: B) -> Double { (cov(b.i) + cov(b.j)) * [1.0, 0.87, 0.78][min(max(b.order, 1), 3) - 1] }

        // 1-2 pairs, 1-3 pairs (with target distance)
        var bondLen: [[Int: Double]] = Array(repeating: [:], count: n)
        for b in bonds { bondLen[b.i][b.j] = r0(b); bondLen[b.j][b.i] = r0(b) }
        var angleTargets: [(i: Int, j: Int, d: Double)] = []
        var excluded = Set<Int>()                                  // i * n + j for bonded or 1-3 pairs
        for b in bonds { excluded.insert(b.i * n + b.j); excluded.insert(b.j * n + b.i) }
        for c in 0..<n where nbrs[c].count >= 2 {
            let theta = idealAngle(bySymbol[s.atoms[c].symbol], sigma: nbrs[c].count, pi: pi[c]) * .pi / 180
            for a in 0..<nbrs[c].count {
                for b in (a + 1)..<nbrs[c].count {
                    let i = nbrs[c][a], j = nbrs[c][b]
                    let ra = bondLen[c][i] ?? 1.5, rb = bondLen[c][j] ?? 1.5
                    angleTargets.append((i, j, sqrt(max(0.01, ra * ra + rb * rb - 2 * ra * rb * cos(theta)))))
                    excluded.insert(i * n + j); excluded.insert(j * n + i)
                }
            }
        }

        // Start from the drawing; atoms that belong to π systems stay flat, others get a small deterministic z kick.
        var seed: UInt64 = 12345
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double((seed >> 33) % 2000) / 1000 - 1 }
        let scale = 1.5 / Sketch.bondLength
        var flat = [Bool](repeating: false, count: n)
        for i in 0..<n { flat[i] = pi[i] > 0 || nbrs[i].contains { pi[$0] > 0 } }
        for i in 0..<n where s.atoms[i].symbol == "H" { flat[i] = nbrs[i].first.map { pi[$0] > 0 } ?? false }
        var p = (0..<n).map { i in V(x: s.atoms[i].x * scale, y: -s.atoms[i].y * scale, z: flat[i] ? 0 : rnd() * 0.35) }

        var step = 0.12
        for iter in 0..<900 {
            var g = [V](repeating: V(), count: n)
            func spring(_ i: Int, _ j: Int, _ d0: Double, _ k: Double) {
                let dx = p[i].x - p[j].x, dy = p[i].y - p[j].y, dz = p[i].z - p[j].z
                let d = max(1e-6, sqrt(dx * dx + dy * dy + dz * dz))
                let f = k * (d - d0) / d
                g[i].x += f * dx; g[i].y += f * dy; g[i].z += f * dz
                g[j].x -= f * dx; g[j].y -= f * dy; g[j].z -= f * dz
            }
            for b in bonds { spring(b.i, b.j, r0(b), 1.0) }
            for a in angleTargets { spring(a.i, a.j, a.d, 0.6) }
            for i in 0..<n {
                for j in (i + 1)..<n where !excluded.contains(i * n + j) {
                    let dmin = (s.atoms[i].symbol == "H" || s.atoms[j].symbol == "H") ? 2.0 : 2.6
                    let dx = p[i].x - p[j].x, dy = p[i].y - p[j].y, dz = p[i].z - p[j].z
                    let d = max(1e-6, sqrt(dx * dx + dy * dy + dz * dz))
                    if d < dmin { spring(i, j, dmin, 0.25) }
                }
            }
            // keep three-coordinate π centres flat: penalise the volume spanned by their three bonds
            for c in 0..<n where pi[c] > 0 && nbrs[c].count == 3 {
                let a = nbrs[c][0], b = nbrs[c][1], d = nbrs[c][2]
                func rel(_ i: Int) -> V { V(x: p[i].x - p[c].x, y: p[i].y - p[c].y, z: p[i].z - p[c].z) }
                func cross(_ u: V, _ v: V) -> V { V(x: u.y * v.z - u.z * v.y, y: u.z * v.x - u.x * v.z, z: u.x * v.y - u.y * v.x) }
                let ra = rel(a), rb = rel(b), rd = rel(d)
                let vol = ra.x * cross(rb, rd).x + ra.y * cross(rb, rd).y + ra.z * cross(rb, rd).z
                let k = 0.15 * vol
                let ga = cross(rb, rd), gb = cross(rd, ra), gd = cross(ra, rb)
                for (i, grad) in [(a, ga), (b, gb), (d, gd)] {
                    g[i].x += k * grad.x; g[i].y += k * grad.y; g[i].z += k * grad.z
                    g[c].x -= k * grad.x; g[c].y -= k * grad.y; g[c].z -= k * grad.z
                }
            }
            if iter % 150 == 149 { step *= 0.7 }
            for i in 0..<n {
                p[i].x -= step * g[i].x; p[i].y -= step * g[i].y; p[i].z -= step * g[i].z
            }
        }

        let cx = p.reduce(0) { $0 + $1.x } / Double(n), cy = p.reduce(0) { $0 + $1.y } / Double(n), cz = p.reduce(0) { $0 + $1.z } / Double(n)
        return Molecule(name: name,
                        atoms: (0..<n).map { MolAtom(symbol: s.atoms[$0].symbol, x: p[$0].x - cx, y: p[$0].y - cy, z: p[$0].z - cz) },
                        bonds: bonds.map { MolBond(a: $0.i, b: $0.j, order: $0.order) })
    }
}

@MainActor enum EditorSelfTest {
    static func run() {
        func sketch(_ t: String) -> Sketch { SketchTemplates.make(t, cx: 0, cy: 0) }
        func angles(_ m: Molecule, around symbol: String, nth: Int = 0) -> [Double] {
            let idx = m.atoms.indices.filter { m.atoms[$0].symbol == symbol }
            guard nth < idx.count else { return [] }
            let c = idx[nth]
            let nb = m.bonds.compactMap { $0.a == c ? $0.b : ($0.b == c ? $0.a : nil) }
            return VBT.angles(at: c, in: m, neighbors: nb)
        }
        func near(_ xs: [Double], _ target: Double, _ tol: Double) -> Bool { !xs.isEmpty && xs.allSatisfy { abs($0 - target) <= tol } }

        // formulas and masses
        let eth = sketch("Ethanol")
        SelfTest.check(eth.formula == "C2H6O" && abs(eth.mass - 46.07) < 0.05, "editor: ethanol sketch is C2H6O, 46.07 u", "\(eth.formula) \(eth.mass)")
        SelfTest.check(sketch("Benzene").formula == "C6H6", "editor: benzene is C6H6", sketch("Benzene").formula)
        SelfTest.check(sketch("Acetic acid").formula == "C2H4O2", "editor: acetic acid is C2H4O2", sketch("Acetic acid").formula)
        SelfTest.check(sketch("Ethyne").formula == "C2H2" && sketch("Ammonia").formula == "H3N" && sketch("Water").formula == "H2O", "editor: ethyne, ammonia, water formulas",
                       "\(sketch("Ethyne").formula) \(sketch("Ammonia").formula) \(sketch("Water").formula)")

        // valence checking
        var bad = Sketch()
        let c = SketchAtom(symbol: "C", x: 0, y: 0); bad.atoms.append(c)
        for k in 0..<5 {
            let h = SketchAtom(symbol: "H", x: Double(k) * 10, y: 50); bad.atoms.append(h)
            bad.bonds.append(SketchBond(a: c.id, b: h.id, order: 1))
        }
        SelfTest.check(bad.problems.count == 1 && bad.problems.first?.atom.symbol == "C", "editor: five bonds to carbon is flagged", "\(bad.problems.map(\.message))")
        SelfTest.check(sketch("Methane").addingHydrogens().atoms.count == 5, "editor: add hydrogens turns CH4 into 5 atoms")

        // naming follows the drawing (regression: a drawn molecule kept the name of the last template)
        let named = EditorModel()
        named.load(template: "Ammonia")
        let nameAtLoad = named.name
        let centre = named.sketch.atoms[0].id
        named.setElement(centre, "P")
        let ids = (0..<3).map { k in named.addAtom("Cl", at: CGPoint(x: 100 + Double(k) * 40, y: 100)) }
        ids.forEach { named.connect(centre, $0, order: 1) }
        SelfTest.check(nameAtLoad == "Ammonia" && named.name == "Cl3P", "editor: name follows the drawing, not the last template", "\(nameAtLoad) → \(named.name)")
        named.customName = "My phosphine"
        SelfTest.check(named.name == "My phosphine" && named.molecule3D().name == "My phosphine", "editor: a typed name wins")

        // 3D geometry
        let methane = Embed3D.embed(sketch("Methane"), name: "m")
        SelfTest.check(near(angles(methane, around: "C"), 109.5, 5), "editor 3D: methane H–C–H ≈ 109.5°", "\(angles(methane, around: "C"))")
        let water = Embed3D.embed(sketch("Water"), name: "w")
        SelfTest.check(near(angles(water, around: "O"), 104.5, 5), "editor 3D: water H–O–H ≈ 104.5°", "\(angles(water, around: "O"))")
        let ammonia = Embed3D.embed(sketch("Ammonia"), name: "a")
        SelfTest.check(near(angles(ammonia, around: "N"), 107, 5), "editor 3D: ammonia H–N–H ≈ 107°", "\(angles(ammonia, around: "N"))")
        let co2 = Embed3D.embed(sketch("Carbon dioxide"), name: "c")
        SelfTest.check(near(angles(co2, around: "C"), 180, 3), "editor 3D: CO2 is linear", "\(angles(co2, around: "C"))")
        let ethene = Embed3D.embed(sketch("Ethene"), name: "e")
        SelfTest.check(near(angles(ethene, around: "C"), 120, 6) && ethene.atoms.allSatisfy { abs($0.z - ethene.atoms[0].z) < 0.05 }, "editor 3D: ethene is planar with ≈120° angles",
                       "\(angles(ethene, around: "C")) z=\(ethene.atoms.map(\.z))")
        let ethanol = Embed3D.embed(eth, name: "et")
        let cc = angles(ethanol, around: "C", nth: 0) + angles(ethanol, around: "C", nth: 1) + angles(ethanol, around: "O")
        SelfTest.check(cc.allSatisfy { $0 > 100 && $0 < 118 }, "editor 3D: ethanol angles are all tetrahedral-ish (100–118°)", "\(cc)")
        let benz = Embed3D.embed(sketch("Benzene"), name: "b")
        SelfTest.check(benz.atoms.allSatisfy { abs($0.z) < 0.05 } && near(angles(benz, around: "C"), 120, 6), "editor 3D: benzene is flat with 120° angles", "\(angles(benz, around: "C"))")
        let bonds = benz.bonds.map { b -> Double in
            let a = benz.atoms[b.a], c = benz.atoms[b.b]
            return sqrt(pow(a.x - c.x, 2) + pow(a.y - c.y, 2) + pow(a.z - c.z, 2))
        }
        SelfTest.check(bonds.allSatisfy { $0 > 0.9 && $0 < 1.7 }, "editor 3D: benzene bond lengths are 0.9–1.7 Å", "\(bonds.map { String(format: "%.2f", $0) })")
    }
}
