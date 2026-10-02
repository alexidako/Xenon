import Foundation

/// Finds the lowest-energy 3D shape of a molecule with a small molecular-mechanics force field.
///
/// Energy terms (kcal/mol, Å, radians): bond stretching, bond-angle bending toward the VSEPR/valence-bond ideal,
/// torsion (staggered sp³–sp³, flat double bonds and conjugated bonds), out-of-plane bending for flat sp² centres and
/// Lennard-Jones repulsion/attraction between atoms three or more bonds apart. It is a simple classical model, not
/// quantum chemistry, so it finds sensible shapes and relative strain, not exact energies.
///
/// "Most stable" is a search: several starting shapes are generated (rotating every rotatable bond, and shaking
/// ring systems), each is relaxed to a minimum, and the lowest one wins.
enum Optimizer {
    struct Result {
        var molecule: Molecule
        var energyBefore: Double
        var energyAfter: Double
        var starts: Int
        var rotors: Int
    }

    // MARK: force field

    struct Field {
        struct Bond { let i: Int, j: Int, r0: Double }
        struct Angle { let i: Int, j: Int, k: Int, cos0: Double, linear: Bool, ka: Double }
        struct Torsion { let i: Int, j: Int, k: Int, l: Int, v: Double, n: Double, phase: Double }   // E = ½V(1 + cos(nφ − phase))
        struct Planar { let c: Int, a: Int, b: Int, d: Int }
        struct Pair { let i: Int, j: Int, r: Double, eps: Double }

        var n = 0
        var bonds: [Bond] = [], angles: [Angle] = [], torsions: [Torsion] = [], planars: [Planar] = [], pairs: [Pair] = []
        var neighbors: [[Int]] = []
        var rotors: [(a: Int, b: Int)] = []
        var rings: [[Int]] = []

        static let kBond = 600.0, kPlanar = 40.0

        init(_ m: Molecule) {
            n = m.atoms.count
            let by = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0) })
            neighbors = [[Int]](repeating: [], count: n)
            var order: [[Int: Int]] = Array(repeating: [:], count: n)
            for b in m.bonds where b.a < n && b.b < n && b.a != b.b {
                if order[b.a][b.b] != nil { continue }
                neighbors[b.a].append(b.b); neighbors[b.b].append(b.a)
                order[b.a][b.b] = b.order; order[b.b][b.a] = b.order
            }
            var pi = [Int](repeating: 0, count: n)
            for i in 0..<n { pi[i] = order[i].values.reduce(0) { $0 + $1 - 1 } }
            func cov(_ i: Int) -> Double { by[m.atoms[i].symbol]?.radiusCovalent ?? 0.8 }
            func sym(_ i: Int) -> String { m.atoms[i].symbol }

            let aromatic = Field.aromaticBonds(neighbors, order, n)
            for i in 0..<n { for j in neighbors[i] where j > i {
                let o = order[i][j] ?? 1
                var factor = [1.0, 0.87, 0.78][min(max(o, 1), 3) - 1]
                if aromatic.contains(i * n + j) { factor = 0.91 }                                  // benzene-like ring: all bonds ≈ 1.40 Å
                else if o == 1, pi[i] > 0, pi[j] > 0, (order[i].values.contains { $0 >= 2 }), (order[j].values.contains { $0 >= 2 }) { factor = 0.955 }   // conjugated single bond
                bonds.append(Bond(i: i, j: j, r0: (cov(i) + cov(j)) * factor))
            } }

            // geometry class of every atom: steric number from valence bond theory, else from the bond count
            var steric = [Int](repeating: 4, count: n)
            for i in 0..<n {
                if let e = by[sym(i)], let h = Hybridization.makeAllowingCharge(e, sigma: neighbors[i].count, pi: pi[i]), h.hybridName != nil { steric[i] = h.steric }
                else { steric[i] = pi[i] >= 2 ? 2 : (pi[i] == 1 ? 3 : max(2, min(4, neighbors[i].count))) }
            }

            for c in 0..<n where neighbors[c].count >= 2 {
                let e = by[sym(c)]
                let deg = Embed3D.idealAngle(e, sigma: neighbors[c].count, pi: pi[c]) * .pi / 180
                let nb = neighbors[c]
                // hydrogens are light and soft; heavy atoms stiffer
                for a in 0..<nb.count { for b in (a + 1)..<nb.count {
                    let linear = deg > 3.0
                    let ka = (sym(nb[a]) == "H" || sym(nb[b]) == "H") ? 60.0 : 90.0
                    angles.append(Angle(i: nb[a], j: c, k: nb[b], cos0: cos(deg), linear: linear, ka: ka))
                } }
                if nb.count == 3 && (pi[c] > 0 || steric[c] == 3) { planars.append(Planar(c: c, a: nb[0], b: nb[1], d: nb[2])) }
            }

            // torsions around every bond whose two ends both have other neighbours
            for b in bonds {
                let j = b.i, k = b.j
                let left = neighbors[j].filter { $0 != k }, right = neighbors[k].filter { $0 != j }
                guard !left.isEmpty, !right.isEmpty else { continue }
                let o = order[j][k] ?? 1
                let count = Double(left.count * right.count)
                let sj = steric[j], sk = steric[k]
                for i in left { for l in right {
                    if o >= 2 {
                        torsions.append(Torsion(i: i, j: j, k: k, l: l, v: 40, n: 2, phase: .pi))              // double bond stays flat (cis or trans)
                    } else if sj == 3 && sk == 3 {
                        torsions.append(Torsion(i: i, j: j, k: k, l: l, v: 8, n: 2, phase: .pi))               // conjugated single bond prefers flat
                    } else if sj <= 3 && sk <= 3 {
                        continue                                                                              // sp–sp² etc.: no preference
                    } else if sj == 4 && sk == 4 {
                        let heavy = Set([sym(j), sym(k)])
                        let barrier = heavy == ["C"] ? 2.9 : (heavy.contains("O") ? 1.1 : 2.0)
                        torsions.append(Torsion(i: i, j: j, k: k, l: l, v: barrier / count, n: 3, phase: 0))     // staggered
                    } else {
                        torsions.append(Torsion(i: i, j: j, k: k, l: l, v: 1.0 / count, n: 3, phase: .pi))      // sp²–sp³: eclipsed with the double bond
                    }
                } }
            }

            // non-bonded pairs: three or more bonds apart
            var near = [Set<Int>](repeating: [], count: n)       // 1-2 and 1-3
            var oneFour = Set<Int>()
            for i in 0..<n { for j in neighbors[i] { near[i].insert(j); for k in neighbors[j] where k != i { near[i].insert(k) } } }
            for i in 0..<n { for j in neighbors[i] { for k in neighbors[j] where k != i { for l in neighbors[k] where l != j && l != i && !near[i].contains(l) { oneFour.insert(min(i, l) * n + max(i, l)) } } } }
            func eps(_ s: String) -> Double { ["H": 0.044, "C": 0.105, "N": 0.069, "O": 0.060, "F": 0.050, "S": 0.274, "Cl": 0.227, "P": 0.305, "Br": 0.251, "I": 0.339][s] ?? 0.1 }
            func rv(_ s: String) -> Double { min(2.2, by[s]?.radiusVDW ?? 1.7) }
            for i in 0..<n { for j in (i + 1)..<n where !near[i].contains(j) {
                let scale = oneFour.contains(i * n + j) ? 0.5 : 1.0
                pairs.append(Pair(i: i, j: j, r: rv(sym(i)) + rv(sym(j)), eps: scale * (eps(sym(i)) * eps(sym(j))).squareRoot()))
            } }

            rings = Field.findRings(neighbors, n)

            // rotatable bonds: single, not in a ring, both ends have another neighbour
            for b in bonds {
                guard (order[b.i][b.j] ?? 1) == 1, neighbors[b.i].count >= 2, neighbors[b.j].count >= 2 else { continue }
                if Field.reachable(from: b.i, to: b.j, avoiding: (b.i, b.j), neighbors) { continue }      // ring bond
                if steric[b.i] == 2 || steric[b.j] == 2 { continue }                                    // linear centre: rotation changes nothing
                rotors.append((b.i, b.j))
            }
        }

        /// Simple rings of 4 to 7 atoms, each listed once in cycle order.
        static func findRings(_ nb: [[Int]], _ n: Int) -> [[Int]] {
            var seen = Set<[Int]>(), out: [[Int]] = []
            func extend(_ path: [Int]) {
                if path.count >= 4, nb[path.last!].contains(path[0]) {
                    let key = path.sorted()
                    if seen.insert(key).inserted { out.append(path) }
                }
                guard path.count < 7 else { return }
                for y in nb[path.last!] where y > path[0] && !path.contains(y) { extend(path + [y]) }
            }
            for s in 0..<n where nb[s].count >= 2 { extend([s]) }
            return out
        }

        /// Bonds (as i·n+j with i<j) of six-membered rings whose bonds alternate single/double: the Kekulé drawing of an aromatic ring.
        static func aromaticBonds(_ nb: [[Int]], _ order: [[Int: Int]], _ n: Int) -> Set<Int> {
            var out = Set<Int>()
            func extend(_ path: [Int]) {
                if path.count == 6 {
                    guard nb[path[5]].contains(path[0]) else { return }
                    let ring = path
                    let orders = (0..<6).map { order[ring[$0]][ring[($0 + 1) % 6]] ?? 1 }
                    if orders == [1, 2, 1, 2, 1, 2] || orders == [2, 1, 2, 1, 2, 1] {
                        for k in 0..<6 { let a = ring[k], b = ring[(k + 1) % 6]; out.insert(min(a, b) * n + max(a, b)) }
                    }
                    return
                }
                for y in nb[path.last!] where y > path[0] && !path.contains(y) { extend(path + [y]) }
            }
            for s in 0..<n where nb[s].count >= 2 { extend([s]) }
            return out
        }

        static func reachable(from s: Int, to t: Int, avoiding e: (Int, Int), _ nb: [[Int]]) -> Bool {
            var seen: Set<Int> = [s], stack = [s]
            while let x = stack.popLast() {
                for y in nb[x] {
                    if (x == e.0 && y == e.1) || (x == e.1 && y == e.0) { continue }
                    if y == t { return true }
                    if seen.insert(y).inserted { stack.append(y) }
                }
            }
            return false
        }

        /// Atoms on `b`'s side of the bond a–b.
        func side(of b: Int, awayFrom a: Int) -> [Int] {
            var seen: Set<Int> = [a, b], stack = [b], out = [b]
            while let x = stack.popLast() { for y in neighbors[x] where seen.insert(y).inserted { stack.append(y); out.append(y) } }
            return out
        }

        // MARK: energy and gradient

        @inline(__always) private func p(_ x: [Double], _ i: Int) -> (Double, Double, Double) { (x[3 * i], x[3 * i + 1], x[3 * i + 2]) }

        func energy(_ x: [Double], gradient g: inout [Double]) -> Double {
            for i in 0..<g.count { g[i] = 0 }
            var e = 0.0
            func add(_ i: Int, _ dx: Double, _ dy: Double, _ dz: Double) { g[3 * i] += dx; g[3 * i + 1] += dy; g[3 * i + 2] += dz }

            for b in bonds {
                let (ax, ay, az) = p(x, b.i), (bx, by, bz) = p(x, b.j)
                let dx = ax - bx, dy = ay - by, dz = az - bz
                let r = max(1e-9, (dx * dx + dy * dy + dz * dz).squareRoot())
                e += 0.5 * Field.kBond * (r - b.r0) * (r - b.r0)
                let f = Field.kBond * (r - b.r0) / r
                add(b.i, f * dx, f * dy, f * dz); add(b.j, -f * dx, -f * dy, -f * dz)
            }

            for a in angles {
                let (ix, iy, iz) = p(x, a.i), (jx, jy, jz) = p(x, a.j), (kx, ky, kz) = p(x, a.k)
                let ux = ix - jx, uy = iy - jy, uz = iz - jz, vx = kx - jx, vy = ky - jy, vz = kz - jz
                let lu = max(1e-9, (ux * ux + uy * uy + uz * uz).squareRoot()), lv = max(1e-9, (vx * vx + vy * vy + vz * vz).squareRoot())
                let c = max(-1, min(1, (ux * vx + uy * vy + uz * vz) / (lu * lv)))
                let dEdc: Double
                if a.linear { e += a.ka * (1 + c); dEdc = a.ka }
                else {
                    let s2 = max(0.05, 1 - a.cos0 * a.cos0)
                    e += 0.5 * a.ka * (c - a.cos0) * (c - a.cos0) / s2
                    dEdc = a.ka * (c - a.cos0) / s2
                }
                // dc/dri = v/(|u||v|) − c·u/|u|², dc/drk = u/(|u||v|) − c·v/|v|²
                let gix = dEdc * (vx / (lu * lv) - c * ux / (lu * lu)), giy = dEdc * (vy / (lu * lv) - c * uy / (lu * lu)), giz = dEdc * (vz / (lu * lv) - c * uz / (lu * lu))
                let gkx = dEdc * (ux / (lu * lv) - c * vx / (lv * lv)), gky = dEdc * (uy / (lu * lv) - c * vy / (lv * lv)), gkz = dEdc * (uz / (lu * lv) - c * vz / (lv * lv))
                add(a.i, gix, giy, giz); add(a.k, gkx, gky, gkz); add(a.j, -gix - gkx, -giy - gky, -giz - gkz)
            }

            for t in torsions {
                let (ix, iy, iz) = p(x, t.i), (jx, jy, jz) = p(x, t.j), (kx, ky, kz) = p(x, t.k), (lx, ly, lz) = p(x, t.l)
                // F = ri − rj, G = rj − rk, H = rl − rk; A = F×G, B = H×G
                let fx = ix - jx, fy = iy - jy, fz = iz - jz, gx = jx - kx, gy = jy - ky, gz = jz - kz, hx = lx - kx, hy = ly - ky, hz = lz - kz
                let ax = fy * gz - fz * gy, ay = fz * gx - fx * gz, az = fx * gy - fy * gx
                let bx = hy * gz - hz * gy, by = hz * gx - hx * gz, bz = hx * gy - hy * gx
                let a2 = ax * ax + ay * ay + az * az, b2 = bx * bx + by * by + bz * bz
                let lg = (gx * gx + gy * gy + gz * gz).squareRoot()
                guard a2 > 1e-10, b2 > 1e-10, lg > 1e-6 else { continue }
                let cosphi = (ax * bx + ay * by + az * bz) / (a2 * b2).squareRoot()
                // sign from (A×B)·G
                let cx = ay * bz - az * by, cy = az * bx - ax * bz, cz = ax * by - ay * bx
                let sinphi = (cx * gx + cy * gy + cz * gz) / ((a2 * b2).squareRoot() * lg)
                let phi = atan2(sinphi, cosphi)
                e += 0.5 * t.v * (1 + cos(t.n * phi - t.phase))
                let dEdphi = 0.5 * t.v * t.n * sin(t.n * phi - t.phase)     // sign matches the dφ/dr formulas below
                let fg = fx * gx + fy * gy + fz * gz, hg = hx * gx + hy * gy + hz * gz
                // dφ/dri = −|G|/A² · A ; dφ/drl = |G|/B² · B ; dφ/drj, dφ/drk by the Blondel–Karplus formulas
                let dix = -lg / a2 * ax, diy = -lg / a2 * ay, diz = -lg / a2 * az
                let dlx = lg / b2 * bx, dly = lg / b2 * by, dlz = lg / b2 * bz
                let sA = fg / (a2 * lg), sB = hg / (b2 * lg)
                let djx = -dix + sA * ax - sB * bx, djy = -diy + sA * ay - sB * by, djz = -diz + sA * az - sB * bz
                let dkx = -dlx - sA * ax + sB * bx, dky = -dly - sA * ay + sB * by, dkz = -dlz - sA * az + sB * bz
                add(t.i, dEdphi * dix, dEdphi * diy, dEdphi * diz); add(t.j, dEdphi * djx, dEdphi * djy, dEdphi * djz)
                add(t.k, dEdphi * dkx, dEdphi * dky, dEdphi * dkz); add(t.l, dEdphi * dlx, dEdphi * dly, dEdphi * dlz)
            }

            for pl in planars {
                let (cx, cy, cz) = p(x, pl.c)
                let (ax, ay, az) = p(x, pl.a), (bx, by, bz) = p(x, pl.b), (dx, dy, dz) = p(x, pl.d)
                let ra = (ax - cx, ay - cy, az - cz), rb = (bx - cx, by - cy, bz - cz), rd = (dx - cx, dy - cy, dz - cz)
                func cross(_ u: (Double, Double, Double), _ v: (Double, Double, Double)) -> (Double, Double, Double) { (u.1 * v.2 - u.2 * v.1, u.2 * v.0 - u.0 * v.2, u.0 * v.1 - u.1 * v.0) }
                let cbd = cross(rb, rd), cda = cross(rd, ra), cab = cross(ra, rb)
                let vol = ra.0 * cbd.0 + ra.1 * cbd.1 + ra.2 * cbd.2
                e += 0.5 * Field.kPlanar * vol * vol
                let k = Field.kPlanar * vol
                add(pl.a, k * cbd.0, k * cbd.1, k * cbd.2); add(pl.b, k * cda.0, k * cda.1, k * cda.2); add(pl.d, k * cab.0, k * cab.1, k * cab.2)
                add(pl.c, -k * (cbd.0 + cda.0 + cab.0), -k * (cbd.1 + cda.1 + cab.1), -k * (cbd.2 + cda.2 + cab.2))
            }

            for q in pairs {
                let (ax, ay, az) = p(x, q.i), (bx, by, bz) = p(x, q.j)
                let dx = ax - bx, dy = ay - by, dz = az - bz
                let r2 = max(0.25, dx * dx + dy * dy + dz * dz)       // soft core: very close atoms push apart without blowing up
                let s2 = q.r * q.r / r2, s6 = s2 * s2 * s2
                e += q.eps * (s6 * s6 - 2 * s6)
                let f = q.eps * 12 * (s6 - s6 * s6) / r2           // −dE/dr · 1/r
                add(q.i, f * dx, f * dy, f * dz); add(q.j, -f * dx, -f * dy, -f * dz)
            }
            return e
        }

        func energy(_ x: [Double]) -> Double { var g = [Double](repeating: 0, count: x.count); return energy(x, gradient: &g) }
    }

    // MARK: minimiser (FIRE)

    static func minimize(_ field: Field, _ start: [Double], maxIterations: Int = 4000, tolerance: Double = 0.02) -> (x: [Double], energy: Double) {
        var x = start
        var g = [Double](repeating: 0, count: x.count)
        var v = [Double](repeating: 0, count: x.count)
        var dt = 0.01, alpha = 0.1, sinceNegative = 0
        let dtMax = 0.03, maxStep = 0.08
        var e = field.energy(x, gradient: &g)
        for _ in 0..<maxIterations {
            let gmax = g.reduce(0) { max($0, abs($1)) }
            if gmax < tolerance { break }
            let power = zip(g, v).reduce(0.0) { $0 - $1.0 * $1.1 }          // F·v with F = −g
            if power > 0 {
                let vn = v.reduce(0.0) { $0 + $1 * $1 }.squareRoot(), gn = g.reduce(0.0) { $0 + $1 * $1 }.squareRoot()
                if gn > 0 { for i in v.indices { v[i] = (1 - alpha) * v[i] - alpha * g[i] / gn * vn } }
                sinceNegative += 1
                if sinceNegative > 5 { dt = min(dt * 1.1, dtMax); alpha *= 0.99 }
            } else {
                v = [Double](repeating: 0, count: v.count); dt *= 0.5; alpha = 0.1; sinceNegative = 0
            }
            for i in v.indices { v[i] -= dt * g[i] }
            for i in x.indices { x[i] += max(-maxStep, min(maxStep, dt * v[i])) }
            e = field.energy(x, gradient: &g)
        }
        return (x, e)
    }

    // MARK: search for the lowest-energy conformer

    static func flatten(_ m: Molecule) -> [Double] { m.atoms.flatMap { [$0.x, $0.y, $0.z] } }

    static func optimize(_ m: Molecule, effort: Int = 24, seed: UInt64 = 2026) -> Result {
        let n = m.atoms.count
        guard n >= 2 else { return Result(molecule: m, energyBefore: 0, energyAfter: 0, starts: 0, rotors: 0) }
        let field = Field(m)
        let x0 = flatten(m)
        let before = field.energy(x0)

        var best = minimize(field, x0)
        var starts = 1
        var rng = SeededRNG(seed: seed)
        func rand(_ lo: Double, _ hi: Double) -> Double { Double.random(in: lo..<hi, using: &rng) }

        if n <= 120 {
            let hasRing = field.bonds.count >= field.n          // a connected molecule with n or more bonds contains a ring
            let tries = field.rotors.isEmpty && !m.bonds.isEmpty ? effort * 2 : (hasRing ? effort * 2 : effort)
            for t in 0..<tries {
                var x = t % 2 == 0 ? best.x : x0
                if !field.rings.isEmpty && t % 3 == 0 {
                    // pucker the rings: push their atoms up and down along the ring normal (alternating gives chairs, other patterns boats and twists)
                    for ring in field.rings {
                        let nrm = ringNormal(x, ring)
                        let alternating = t % 6 == 0
                        for (k, a) in ring.enumerated() {
                            let sign = alternating ? (k % 2 == 0 ? 1.0 : -1.0) : (rand(0, 1) < 0.5 ? 1.0 : -1.0)
                            let d = rand(0.25, 0.5) * sign
                            x[3 * a] += nrm.0 * d; x[3 * a + 1] += nrm.1 * d; x[3 * a + 2] += nrm.2 * d
                        }
                    }
                    for ring in field.rings { rebuildSubstituents(&x, ring: ring, field: field) }
                    for i in x.indices { x[i] += rand(-0.05, 0.05) }
                } else if field.rotors.isEmpty || t % 4 == 3 {
                    let amp = rand(0.2, 0.7)
                    for i in x.indices { x[i] += rand(-amp, amp) }                         // shake: lets rings pucker into other forms
                } else {
                    for r in field.rotors.shuffled(using: &rng) {
                        // spin everything on one side of the bond by a random angle
                        rotate(&x, atoms: field.side(of: r.b, awayFrom: r.a), axisFrom: r.a, axisTo: r.b, angle: rand(0, 2 * .pi))
                    }
                }
                let result = minimize(field, x)
                starts += 1
                if result.energy < best.energy - 1e-6 { best = result }
            }
        }

        // centre the result
        var out = m
        let cx = (0..<n).reduce(0.0) { $0 + best.x[3 * $1] } / Double(n), cy = (0..<n).reduce(0.0) { $0 + best.x[3 * $1 + 1] } / Double(n), cz = (0..<n).reduce(0.0) { $0 + best.x[3 * $1 + 2] } / Double(n)
        for i in 0..<n { out.atoms[i].x = best.x[3 * i] - cx; out.atoms[i].y = best.x[3 * i + 1] - cy; out.atoms[i].z = best.x[3 * i + 2] - cz }
        return Result(molecule: out, energyBefore: before, energyAfter: best.energy, starts: starts, rotors: field.rotors.count)
    }

    /// After puckering a ring, put the two substituents of every sp³ ring atom back at ideal tetrahedral positions
    /// (carrying their own branches along) so the minimiser starts from a sensible chair or boat rather than a tangle.
    static func rebuildSubstituents(_ x: inout [Double], ring: [Int], field: Field) {
        let inRing = Set(ring)
        func vec(_ a: Int, _ b: Int) -> (Double, Double, Double) { (x[3 * b] - x[3 * a], x[3 * b + 1] - x[3 * a + 1], x[3 * b + 2] - x[3 * a + 2]) }
        func norm(_ v: (Double, Double, Double)) -> (Double, Double, Double) { let l = max(1e-9, (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()); return (v.0 / l, v.1 / l, v.2 / l) }
        for c in ring {
            let ringNb = field.neighbors[c].filter { inRing.contains($0) }, subs = field.neighbors[c].filter { !inRing.contains($0) }
            guard ringNb.count == 2, subs.count == 2 else { continue }
            let ua = norm(vec(c, ringNb[0])), ub = norm(vec(c, ringNb[1]))
            let bis = norm((ua.0 + ub.0, ua.1 + ub.1, ua.2 + ub.2))
            let nrm = norm((ua.1 * ub.2 - ua.2 * ub.1, ua.2 * ub.0 - ua.0 * ub.2, ua.0 * ub.1 - ua.1 * ub.0))
            let phi = 54.75 * Double.pi / 180
            // keep each substituent on the side of the ring it started on
            let sides = subs.map { s -> Double in let v = vec(c, s); return v.0 * nrm.0 + v.1 * nrm.1 + v.2 * nrm.2 }
            let order = sides[0] >= sides[1] ? [0, 1] : [1, 0]
            for (rank, k) in order.enumerated() {
                let s = subs[k], sign = rank == 0 ? 1.0 : -1.0
                let old = vec(c, s), len = (old.0 * old.0 + old.1 * old.1 + old.2 * old.2).squareRoot()
                let d = (-bis.0 * cos(phi) + sign * nrm.0 * sin(phi), -bis.1 * cos(phi) + sign * nrm.1 * sin(phi), -bis.2 * cos(phi) + sign * nrm.2 * sin(phi))
                let target = (x[3 * c] + d.0 * len, x[3 * c + 1] + d.1 * len, x[3 * c + 2] + d.2 * len)
                let delta = (target.0 - x[3 * s], target.1 - x[3 * s + 1], target.2 - x[3 * s + 2])
                for a in field.side(of: s, awayFrom: c) { x[3 * a] += delta.0; x[3 * a + 1] += delta.1; x[3 * a + 2] += delta.2 }
            }
        }
    }

    /// Unit normal of a ring (Newell's method).
    static func ringNormal(_ x: [Double], _ ring: [Int]) -> (Double, Double, Double) {
        var nx = 0.0, ny = 0.0, nz = 0.0
        for k in 0..<ring.count {
            let a = ring[k], b = ring[(k + 1) % ring.count]
            let ax = x[3 * a], ay = x[3 * a + 1], az = x[3 * a + 2], bx = x[3 * b], by = x[3 * b + 1], bz = x[3 * b + 2]
            nx += (ay - by) * (az + bz); ny += (az - bz) * (ax + bx); nz += (ax - bx) * (ay + by)
        }
        let l = (nx * nx + ny * ny + nz * nz).squareRoot()
        return l > 1e-9 ? (nx / l, ny / l, nz / l) : (0, 0, 1)
    }

    static func rotate(_ x: inout [Double], atoms: [Int], axisFrom a: Int, axisTo b: Int, angle: Double) {
        let ox = x[3 * a], oy = x[3 * a + 1], oz = x[3 * a + 2]
        var kx = x[3 * b] - ox, ky = x[3 * b + 1] - oy, kz = x[3 * b + 2] - oz
        let l = (kx * kx + ky * ky + kz * kz).squareRoot(); guard l > 1e-9 else { return }
        kx /= l; ky /= l; kz /= l
        let c = cos(angle), s = sin(angle)
        for i in atoms {
            let px = x[3 * i] - ox, py = x[3 * i + 1] - oy, pz = x[3 * i + 2] - oz
            let d = kx * px + ky * py + kz * pz
            let cx = ky * pz - kz * py, cy = kz * px - kx * pz, cz = kx * py - ky * px
            x[3 * i] = ox + px * c + cx * s + kx * d * (1 - c)
            x[3 * i + 1] = oy + py * c + cy * s + ky * d * (1 - c)
            x[3 * i + 2] = oz + pz * c + cz * s + kz * d * (1 - c)
        }
    }

    /// Dihedral angle in degrees for atoms i-j-k-l.
    static func dihedral(_ m: Molecule, _ i: Int, _ j: Int, _ k: Int, _ l: Int) -> Double {
        func v(_ a: Int, _ b: Int) -> (Double, Double, Double) { (m.atoms[b].x - m.atoms[a].x, m.atoms[b].y - m.atoms[a].y, m.atoms[b].z - m.atoms[a].z) }
        func cross(_ u: (Double, Double, Double), _ w: (Double, Double, Double)) -> (Double, Double, Double) { (u.1 * w.2 - u.2 * w.1, u.2 * w.0 - u.0 * w.2, u.0 * w.1 - u.1 * w.0) }
        func dot(_ u: (Double, Double, Double), _ w: (Double, Double, Double)) -> Double { u.0 * w.0 + u.1 * w.1 + u.2 * w.2 }
        let b1 = v(i, j), b2 = v(j, k), b3 = v(k, l)
        let n1 = cross(b1, b2), n2 = cross(b2, b3)
        let m1 = cross(n1, (b2.0 / dot(b2, b2).squareRoot(), b2.1 / dot(b2, b2).squareRoot(), b2.2 / dot(b2, b2).squareRoot()))
        return atan2(dot(m1, n2), dot(n1, n2)) * 180 / .pi
    }
}

@MainActor enum OptimizerSelfTest {
    static func run() {
        func mol(_ name: String) -> Molecule { Embed3D.embed(SketchTemplates.make(name, cx: 0, cy: 0), name: name) }
        func library(_ name: String) -> Molecule? { MoleculeLibrary.bundled.first { $0.name == name } }

        // the analytic gradient must match finite differences, for a molecule that exercises every term
        let probe = Embed3D.embed(SketchTemplates.make("Acetic acid", cx: 0, cy: 0), name: "probe")
        var x = Optimizer.flatten(probe)
        var rng = SeededRNG(seed: 5)
        for i in x.indices { x[i] += Double.random(in: -0.2..<0.2, using: &rng) }
        let field = Optimizer.Field(probe)
        var g = [Double](repeating: 0, count: x.count)
        _ = field.energy(x, gradient: &g)
        var worst = 0.0
        for i in x.indices {
            var xp = x, xm = x; xp[i] += 1e-5; xm[i] -= 1e-5
            let num = (field.energy(xp) - field.energy(xm)) / 2e-5
            worst = max(worst, abs(num - g[i]) / max(1, abs(num)))
        }
        SelfTest.check(worst < 1e-4, "optimizer: analytic forces match finite differences (acetic acid, every energy term)", "worst relative error \(worst)")
        let benzene = Embed3D.embed(SketchTemplates.make("Benzene", cx: 0, cy: 0), name: "b")
        var xb = Optimizer.flatten(benzene); for i in xb.indices { xb[i] += Double.random(in: -0.15..<0.15, using: &rng) }
        let fb = Optimizer.Field(benzene); var gb = [Double](repeating: 0, count: xb.count); _ = fb.energy(xb, gradient: &gb)
        var worstB = 0.0
        for i in xb.indices { var xp = xb, xm = xb; xp[i] += 1e-5; xm[i] -= 1e-5; let num = (fb.energy(xp) - fb.energy(xm)) / 2e-5; worstB = max(worstB, abs(num - gb[i]) / max(1, abs(num))) }
        SelfTest.check(worstB < 1e-4, "optimizer: forces match finite differences for the flat-ring terms (benzene)", "\(worstB)")

        // the energy never goes up, and the result is repeatable
        let eth = mol("Ethanol")
        let r1 = Optimizer.optimize(eth), r2 = Optimizer.optimize(eth)
        SelfTest.check(r1.energyAfter <= r1.energyBefore + 1e-6 && r1.molecule.atoms.map(\.x) == r2.molecule.atoms.map(\.x), "optimizer: energy never rises and the same input gives the same shape", "\(r1.energyBefore) → \(r1.energyAfter)")

        // chemistry checks
        func torsions(_ m: Molecule, around a: Int, _ b: Int) -> [Double] {
            let left = m.bonds.compactMap { $0.a == a ? $0.b : ($0.b == a ? $0.a : nil) }.filter { $0 != b }
            let right = m.bonds.compactMap { $0.a == b ? $0.b : ($0.b == b ? $0.a : nil) }.filter { $0 != a }
            return left.flatMap { i in right.map { l in Optimizer.dihedral(m, i, a, b, l) } }
        }
        func near(_ v: Double, _ target: Double, _ tol: Double) -> Bool { var d = abs(v - target).truncatingRemainder(dividingBy: 360); if d > 180 { d = 360 - d }; return d <= tol }

        // ethane: staggered (every H–C–C–H torsion is ±60° or 180°)
        let ethane = Optimizer.optimize(Embed3D.embed(Sketch.ethane(), name: "ethane")).molecule
        let cs = ethane.atoms.indices.filter { ethane.atoms[$0].symbol == "C" }
        let tEthane = torsions(ethane, around: cs[0], cs[1])
        SelfTest.check(tEthane.count == 9 && tEthane.allSatisfy { near(abs($0), 60, 12) || near($0, 180, 12) }, "optimizer: ethane relaxes to the staggered shape", "\(tEthane.map { Int($0) })")

        // butane: the carbon chain is anti (180°)
        let butane = Optimizer.optimize(Embed3D.embed(Sketch.butane(), name: "butane"))
        let heavyBonds = butane.molecule.bonds.filter { butane.molecule.atoms[$0.a].symbol == "C" && butane.molecule.atoms[$0.b].symbol == "C" }
        let middle = heavyBonds.first { b in [b.a, b.b].allSatisfy { i in butane.molecule.bonds.filter { ($0.a == i || $0.b == i) && butane.molecule.atoms[$0.a].symbol == "C" && butane.molecule.atoms[$0.b].symbol == "C" }.count == 2 } }!
        let endA = heavyBonds.first { ($0.a == middle.a || $0.b == middle.a) && $0 != middle }!, endB = heavyBonds.first { ($0.a == middle.b || $0.b == middle.b) && $0 != middle }!
        let cA = endA.a == middle.a ? endA.b : endA.a, cB = endB.a == middle.b ? endB.b : endB.a
        let cc = Optimizer.dihedral(butane.molecule, cA, middle.a, middle.b, cB)
        SelfTest.check(near(abs(cc), 180, 10), "optimizer: butane settles into the anti conformer (C–C–C–C = 180°)", "\(cc)")

        // ring: cyclohexane becomes a puckered chair, lower in energy than the flat drawing
        let cyc = Optimizer.optimize(mol("Cyclohexane"))
        let ringC = cyc.molecule.atoms.indices.filter { cyc.molecule.atoms[$0].symbol == "C" }
        let ring = [ringC[0]] + { () -> [Int] in
            var order = [ringC[0]], seen: Set<Int> = [ringC[0]]
            while order.count < 6 { let last = order.last!; guard let nx = cyc.molecule.bonds.compactMap({ b -> Int? in let o = b.a == last ? b.b : (b.b == last ? b.a : nil); return o.flatMap { ringC.contains($0) && !seen.contains($0) ? $0 : nil } }).first else { break }; order.append(nx); seen.insert(nx) }
            return Array(order.dropFirst())
        }()
        var chairOK = false
        if ring.count == 6 {
            let t = (0..<6).map { Optimizer.dihedral(cyc.molecule, ring[$0], ring[($0 + 1) % 6], ring[($0 + 2) % 6], ring[($0 + 3) % 6]) }
            chairOK = t.allSatisfy { abs(abs($0) - 55) < 12 } && zip(t, t.dropFirst() + [t[0]]).allSatisfy { $0 * $1 < 0 }
        }
        SelfTest.check(chairOK && cyc.energyAfter < cyc.energyBefore, "optimizer: cyclohexane puckers into a chair (ring torsions alternate ±55°)", "ring \(ring.count) E \(cyc.energyBefore) → \(cyc.energyAfter)")

        // π systems stay flat; double bond keeps its geometry
        let ethene = Optimizer.optimize(mol("Ethene")).molecule
        let ec = ethene.atoms.indices.filter { ethene.atoms[$0].symbol == "C" }
        let tEthene = torsions(ethene, around: ec[0], ec[1])
        SelfTest.check(tEthene.count == 4 && tEthene.allSatisfy { near($0, 0, 8) || near($0, 180, 8) }, "optimizer: ethene stays planar (every H–C=C–H torsion is 0° or 180°)", "\(tEthene)")
        let ben = Optimizer.optimize(mol("Benzene")).molecule
        let flatness = ben.atoms.map { abs($0.z) }.max() ?? 1
        SelfTest.check(flatness < 0.1, "optimizer: benzene stays flat", "max |z| = \(flatness)")
        let cLen = ben.bonds.filter { ben.atoms[$0.a].symbol == "C" && ben.atoms[$0.b].symbol == "C" }.map { b -> Double in
            let p = ben.atoms[b.a], q = ben.atoms[b.b]; return sqrt(pow(p.x - q.x, 2) + pow(p.y - q.y, 2) + pow(p.z - q.z, 2)) }
        SelfTest.check(cLen.allSatisfy { $0 > 1.3 && $0 < 1.5 }, "optimizer: benzene C–C bonds come out near 1.4 Å", "\(cLen)")

        // textbook angles survive optimization
        func angle(_ m: Molecule, _ symbol: String) -> [Double] {
            let c = m.atoms.firstIndex { $0.symbol == symbol }!
            let nb = m.bonds.compactMap { $0.a == c ? $0.b : ($0.b == c ? $0.a : nil) }
            return VBT.angles(at: c, in: m, neighbors: nb)
        }
        let water = Optimizer.optimize(mol("Water")).molecule, co2 = Optimizer.optimize(mol("Carbon dioxide")).molecule, nh3 = Optimizer.optimize(mol("Ammonia")).molecule
        SelfTest.check(abs(angle(water, "O")[0] - 104.5) < 3 && abs(angle(co2, "C")[0] - 180) < 3 && angle(nh3, "N").allSatisfy { abs($0 - 107) < 4 },
                       "optimizer: water 104.5°, CO₂ linear, ammonia 107°", "\(angle(water, "O")) \(angle(co2, "C")) \(angle(nh3, "N"))")

        // the whole bundled library optimizes to finite, sensible molecules without breaking any bond
        var bad: [String] = []
        for m in MoleculeLibrary.bundled {
            let r = Optimizer.optimize(m, effort: 6)
            let ok = r.molecule.atoms.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite } && r.energyAfter <= r.energyBefore + 1e-6
            let lens = r.molecule.bonds.map { b -> Double in let p = r.molecule.atoms[b.a], q = r.molecule.atoms[b.b]; return sqrt(pow(p.x - q.x, 2) + pow(p.y - q.y, 2) + pow(p.z - q.z, 2)) }
            if !ok || lens.contains(where: { $0 < 0.8 || $0 > 2.2 }) { bad.append(m.name) }
        }
        SelfTest.check(bad.isEmpty, "optimizer: every bundled molecule optimizes cleanly (finite, bond lengths 0.8–2.2 Å, energy not higher)", "\(bad)")
        let lone = Molecule(name: "He", atoms: [MolAtom(symbol: "He", x: 0, y: 0, z: 0)], bonds: [])
        SelfTest.check(Optimizer.optimize(lone).molecule.atoms.count == 1 && Optimizer.optimize(Molecule(name: "", atoms: [], bonds: [])).molecule.atoms.isEmpty, "optimizer: one atom or an empty molecule is returned unchanged")
    }
}

extension Sketch {
    /// Test fixtures: two- and four-carbon chains.
    static func ethane() -> Sketch {
        var s = Sketch()
        let a = SketchAtom(symbol: "C", x: 0, y: 0), b = SketchAtom(symbol: "C", x: Sketch.bondLength, y: 0)
        s.atoms = [a, b]; s.bonds = [SketchBond(a: a.id, b: b.id, order: 1)]
        return s
    }
    static func butane() -> Sketch {
        var s = Sketch()
        let ids = (0..<4).map { k in SketchAtom(symbol: "C", x: Double(k) * Sketch.bondLength * 0.85, y: k % 2 == 0 ? 0 : Sketch.bondLength * 0.5) }
        s.atoms = ids
        s.bonds = (0..<3).map { SketchBond(a: ids[$0].id, b: ids[$0 + 1].id, order: 1) }
        return s
    }
}
