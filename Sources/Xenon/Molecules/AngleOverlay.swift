import SceneKit

/// Draws every bond angle as a small arc with its value in degrees, always facing the camera.
enum AngleOverlay {
    static let arcColor = NSColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1)

    /// One entry per pair of bonds at an atom (hydrogens are never centres). `atoms`: only these centres (empty = all).
    /// With no atoms chosen, the H–X–H angles of an atom that also has heavy neighbours are left out so larger molecules stay readable;
    /// choosing the atom shows all of its angles.
    static func angles(for m: Molecule, atoms: Set<Int> = []) -> [(center: Int, a: Int, b: Int, degrees: Double)] {
        var nbrs = [[Int]](repeating: [], count: m.atoms.count)
        for b in m.bonds where b.a < m.atoms.count && b.b < m.atoms.count { nbrs[b.a].append(b.b); nbrs[b.b].append(b.a) }
        var out: [(Int, Int, Int, Double)] = []
        for c in m.atoms.indices where nbrs[c].count >= 2 && m.atoms[c].symbol != "H" && (atoms.isEmpty || atoms.contains(c)) {
            let degs = VBT.angles(at: c, in: m, neighbors: nbrs[c])
            var k = 0
            let hasHeavy = nbrs[c].contains { m.atoms[$0].symbol != "H" }
            for i in 0..<nbrs[c].count { for j in (i + 1)..<nbrs[c].count {
                let bothH = m.atoms[nbrs[c][i]].symbol == "H" && m.atoms[nbrs[c][j]].symbol == "H"
                if k < degs.count, !(atoms.isEmpty && hasHeavy && bothH) { out.append((c, nbrs[c][i], nbrs[c][j], degs[k])) }
                k += 1
            } }
        }
        return out
    }

    static func nodes(for m: Molecule, pts: [SCNVector3], atoms: Set<Int>, atomRadius: (Int) -> Double) -> [SCNNode] {
        func v(_ p: SCNVector3) -> V3 { V3(Double(p.x), Double(p.y), Double(p.z)) }
        var out: [SCNNode] = []
        let all = angles(for: m, atoms: atoms)
        // at a crowded atom, give each angle its own radius (smallest angle innermost) so arcs and labels do not pile up
        var rank: [Int: [Double]] = [:]
        for x in all { rank[x.center, default: []].append(x.degrees) }
        for c in rank.keys { rank[c]!.sort() }
        for (c, a, b, deg) in all {
            let k = Double(rank[c]?.firstIndex(of: deg) ?? 0)
            let origin = v(pts[c])
            let ua = normalize(v(pts[a]) - origin), ub = normalize(v(pts[b]) - origin)
            let bondLen = min(simd_length(v(pts[a]) - origin), simd_length(v(pts[b]) - origin))
            let r = max(0.55, min(bondLen * 0.55, 1.1), atomRadius(c) + 0.28) + 0.13 * k
            // arc: spherical interpolation from ua to ub
            let theta = acos(max(-1, min(1, simd_dot(ua, ub))))
            guard theta > 0.02 else { continue }
            let steps = max(6, Int(theta / 0.12))
            var prev = origin + ua * r
            for s in 1...steps {
                let t = Double(s) / Double(steps)
                let dir = theta > 3.1 ? normalize(ua * (1 - t) + ub * t) : normalize(ua * (sin((1 - t) * theta) / sin(theta)) + ub * (sin(t * theta) / sin(theta)))
                let next = origin + dir * r
                out.append(segment(from: prev, to: next)); prev = next
            }
            // label just outside the arc, on the bisector
            var bis = ua + ub
            if simd_length(bis) < 1e-6 { bis = perpendicular(to: ua) }
            let pos = origin + normalize(bis) * (r + 0.3)
            out.append(label(String(format: "%.1f°", deg), at: pos))
        }
        return out
    }

    private static func perpendicular(to u: V3) -> V3 { OrbitalMath.perpendicular(to: u) }

    private static func segment(from p: V3, to q: V3) -> SCNNode {
        let d = q - p, len = simd_length(d)
        let cyl = SCNCylinder(radius: 0.018, height: CGFloat(max(len, 1e-4)))
        let m = SCNMaterial(); m.diffuse.contents = arcColor; m.emission.contents = arcColor.withAlphaComponent(0.6); m.lightingModel = .constant
        cyl.materials = [m]
        let node = SCNNode(geometry: cyl)
        node.simdPosition = SIMD3<Float>(Float((p.x + q.x) / 2), Float((p.y + q.y) / 2), Float((p.z + q.z) / 2))
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(Float(d.x / max(len, 1e-9)), Float(d.y / max(len, 1e-9)), Float(d.z / max(len, 1e-9))))
        return node
    }

    private static func label(_ text: String, at p: V3) -> SCNNode {
        let t = SCNText(string: text, extrusionDepth: 0)
        t.font = NSFont.systemFont(ofSize: 1, weight: .semibold)
        t.flatness = 0.05
        let m = SCNMaterial(); m.diffuse.contents = arcColor; m.emission.contents = arcColor; m.lightingModel = .constant
        m.readsFromDepthBuffer = false; m.writesToDepthBuffer = false          // always readable, even behind atoms
        t.materials = [m]
        let node = SCNNode(geometry: t)
        let (lo, hi) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0)
        node.scale = SCNVector3(0.22, 0.22, 0.22)
        node.simdPosition = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
        node.constraints = [SCNBillboardConstraint()]
        node.renderingOrder = 100
        return node
    }
}

@MainActor enum AngleOverlaySelfTest {
    static func run() {
        func mol(_ n: String) -> Molecule { Embed3D.embed(SketchTemplates.make(n, cx: 0, cy: 0), name: n) }
        let water = AngleOverlay.angles(for: mol("Water"))
        SelfTest.check(water.count == 1 && abs(water[0].degrees - 104.5) < 3, "angles: water shows exactly one angle, ≈104.5°", "\(water.map(\.degrees))")
        let methane = AngleOverlay.angles(for: mol("Methane"))
        SelfTest.check(methane.count == 6 && methane.allSatisfy { abs($0.degrees - 109.5) < 4 }, "angles: methane shows six H–C–H angles of ≈109.5°", "\(methane.count)")
        let co2 = AngleOverlay.angles(for: mol("Carbon dioxide"))
        SelfTest.check(co2.count == 1 && co2[0].degrees > 177, "angles: CO₂ shows one angle of 180°", "\(co2.map(\.degrees))")
        let eth = mol("Ethanol")
        let all = AngleOverlay.angles(for: eth).count
        let oIdx = eth.atoms.firstIndex { $0.symbol == "O" }!
        let c1 = eth.atoms.indices.first { eth.atoms[$0].symbol == "C" }!
        SelfTest.check(AngleOverlay.angles(for: eth, atoms: [c1]).count > AngleOverlay.angles(for: eth).filter { $0.center == c1 }.count, "angles: choosing a carbon shows its H–C–H angles too, the overview leaves them out")
        SelfTest.check(AngleOverlay.angles(for: eth, atoms: [oIdx]).count == 1 && all > 1, "angles: the per-atom filter limits which centres are drawn", "all \(all)")
        let pts = eth.atoms.map { SCNVector3($0.x, $0.y, $0.z) }
        let nodes = AngleOverlay.nodes(for: eth, pts: pts, atoms: [], atomRadius: { _ in 0.3 })
        SelfTest.check(nodes.count > all * 6, "angles: every angle gets an arc and a label", "\(nodes.count) nodes for \(all) angles")
        SelfTest.check(AngleOverlay.angles(for: Molecule(name: "x", atoms: [], bonds: [])).isEmpty, "angles: an empty molecule has none")
    }
}
