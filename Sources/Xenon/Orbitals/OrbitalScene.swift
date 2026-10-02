import SwiftUI
import SceneKit
import simd

/// Turns an angular function into a SceneKit surface: each direction is pushed out to |f|², and the surface is split
/// into a positive-phase part and a negative-phase part so the two can have different colors.
enum OrbitalMesh {
    static let positive = NSColor(red: 0.25, green: 0.52, blue: 1.0, alpha: 1)
    static let negative = NSColor(red: 1.0, green: 0.45, blue: 0.25, alpha: 1)

    static func geometry(_ f: (V3) -> Double, scale: Double, positive: NSColor = OrbitalMesh.positive, negative: NSColor = OrbitalMesh.negative,
                         alpha: CGFloat = 0.7, nLat: Int = 40, nLon: Int = 80) -> SCNGeometry {
        var pts: [V3] = [], vals: [Double] = []
        var ref = 0.0
        for i in 0...nLat {
            let th = Double.pi * Double(i) / Double(nLat)
            for j in 0...nLon {
                let ph = 2 * Double.pi * Double(j) / Double(nLon)
                let u = V3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th))
                let v = f(u)
                let r = v * v                                   // angular probability |ψ|², colored by the sign of ψ
                vals.append(v); pts.append(u * r); ref = max(ref, r)
            }
        }
        let k = ref > 0 ? scale / ref : 0
        pts = pts.map { $0 * k }

        var normals = [V3](repeating: V3(0, 0, 0), count: pts.count)
        var posIdx: [Int32] = [], negIdx: [Int32] = []
        let w = nLon + 1
        for i in 0..<nLat {
            for j in 0..<nLon {
                let a = i * w + j, b = a + 1, c = a + w, d = c + 1
                for tri in [(a, c, b), (b, c, d)] {
                    let (p, q, r) = tri
                    var n = simd_cross(pts[q] - pts[p], pts[r] - pts[p])
                    if simd_length(n) < 1e-12 { continue }                       // collapsed at a node
                    if simd_dot(n, pts[p] + pts[q] + pts[r]) < 0 { n = -n }      // face outward
                    for v in [p, q, r] { normals[v] += n }
                    let sign = vals[p] + vals[q] + vals[r]
                    if sign >= 0 { posIdx += [Int32(p), Int32(q), Int32(r)] } else { negIdx += [Int32(p), Int32(q), Int32(r)] }
                }
            }
        }
        func vec(_ v: V3) -> SCNVector3 { SCNVector3(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z)) }
        let vSource = SCNGeometrySource(vertices: pts.map(vec))
        let nSource = SCNGeometrySource(normals: normals.map { simd_length($0) > 0 ? vec(normalize($0)) : SCNVector3(0, 0, 1) })
        var elements: [SCNGeometryElement] = [], materials: [SCNMaterial] = []
        func material(_ color: NSColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.specular.contents = NSColor(white: 1, alpha: 1)
            m.shininess = 0.35
            m.transparency = alpha
            m.isDoubleSided = true
            m.lightingModel = .blinn
            return m
        }
        if !posIdx.isEmpty { elements.append(SCNGeometryElement(indices: posIdx, primitiveType: .triangles)); materials.append(material(positive)) }
        if !negIdx.isEmpty { elements.append(SCNGeometryElement(indices: negIdx, primitiveType: .triangles)); materials.append(material(negative)) }
        let g = SCNGeometry(sources: [vSource, nSource], elements: elements)
        g.materials = materials
        return g
    }

    static func node(_ f: (V3) -> Double, scale: Double, at p: V3 = V3(0, 0, 0), positive: NSColor = OrbitalMesh.positive,
                     negative: NSColor = OrbitalMesh.negative, alpha: CGFloat = 0.7) -> SCNNode {
        let n = SCNNode(geometry: geometry(f, scale: scale, positive: positive, negative: negative, alpha: alpha))
        n.simdPosition = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
        return n
    }
}

/// Lobe shapes built once along +z, then rotated into place.
enum LobeCache {
    private static var cache: [String: SCNGeometry] = [:]

    static func hybrid(_ kind: OrbitalMath.HybridKind, scale: Double, positive: NSColor, negative: NSColor, alpha: CGFloat) -> SCNGeometry {
        let key = "h\(kind.id)\(scale)\(positive.hashValue)\(alpha)"
        if let g = cache[key] { return g }
        let g = OrbitalMesh.geometry(OrbitalMath.hybridLobe(cs: kind.cs, cp: kind.cp, direction: V3(0, 0, 1)), scale: scale,
                                     positive: positive, negative: negative, alpha: alpha)
        cache[key] = g; return g
    }

    static func p(scale: Double, positive: NSColor, negative: NSColor, alpha: CGFloat) -> SCNGeometry {
        let key = "p\(scale)\(positive.hashValue)\(alpha)"
        if let g = cache[key] { return g }
        let g = OrbitalMesh.geometry(OrbitalMath.p(axis: V3(0, 0, 1)), scale: scale, positive: positive, negative: negative, alpha: alpha)
        cache[key] = g; return g
    }
}

func orient(_ node: SCNNode, toward d: V3) {
    node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: SIMD3<Float>(Float(d.x), Float(d.y), Float(d.z)).normalizedSafe)
}

extension SIMD3 where Scalar == Float {
    var normalizedSafe: SIMD3<Float> { simd_length(self) > 0 ? simd_normalize(self) : SIMD3<Float>(0, 0, 1) }
}

// MARK: overlay for the molecule viewer

enum OrbitalOverlay {
    enum Mode: String, CaseIterable, Identifiable {
        case off = "Off", bonds = "σ bonds & lone pairs", all = "σ, lone pairs & π"
        var id: String { rawValue }
    }

    static let sigmaColor = NSColor(red: 0.30, green: 0.55, blue: 1.0, alpha: 1)
    static let lonePairColor = NSColor(red: 0.72, green: 0.38, blue: 0.95, alpha: 1)

    /// Nodes to add to a molecule scene. `pts` are the (already centred) atom positions.
    /// `atoms`: show only these atoms' orbitals (nil = all). A π bond is shown if either end is selected, and a hydrogen's
    /// 1s orbital if it is selected or bonded to a selected atom.
    static func nodes(for m: Molecule, pts: [SCNVector3], mode: Mode, atoms: Set<Int>? = nil) -> [SCNNode] {
        guard mode != .off else { return [] }
        var res = MolecularOrbitals.analyze(m)
        if let keep = atoms, !keep.isEmpty {
            var near = keep
            for b in m.bonds where keep.contains(b.a) || keep.contains(b.b) { near.insert(b.a); near.insert(b.b) }
            res.sigma = res.sigma.filter { keep.contains($0.atom) }
            res.lonePairs = res.lonePairs.filter { keep.contains($0.atom) }
            res.pi = res.pi.filter { keep.contains($0.a) || keep.contains($0.b) }
            res.hydrogens = res.hydrogens.filter { near.contains($0) }
        }
        func at(_ i: Int) -> V3 { V3(Double(pts[i].x), Double(pts[i].y), Double(pts[i].z)) }
        func shift(_ i: Int) -> SIMD3<Float> { SIMD3<Float>(Float(pts[i].x), Float(pts[i].y), Float(pts[i].z)) }
        var out: [SCNNode] = []

        for l in res.sigma {
            guard let kind = OrbitalMath.hybridKind(named: l.hybrid) else { continue }
            let n = SCNNode(geometry: LobeCache.hybrid(kind, scale: 0.95, positive: sigmaColor, negative: sigmaColor.withAlphaComponent(0.5), alpha: 0.55))
            n.simdPosition = shift(l.atom); orient(n, toward: l.direction); out.append(n)
        }
        for l in res.lonePairs {
            guard let kind = OrbitalMath.hybridKind(named: l.hybrid) else { continue }
            let n = SCNNode(geometry: LobeCache.hybrid(kind, scale: 0.85, positive: lonePairColor, negative: lonePairColor.withAlphaComponent(0.5), alpha: 0.55))
            n.simdPosition = shift(l.atom); orient(n, toward: l.direction); out.append(n)
        }
        for h in res.hydrogens {
            // a hydrogen contributes its 1s orbital: a small sphere that overlaps the σ lobe aimed at it
            let s = SCNSphere(radius: 0.5); s.segmentCount = 28
            let mat = SCNMaterial(); mat.diffuse.contents = sigmaColor; mat.transparency = 0.35; mat.isDoubleSided = true
            s.materials = [mat]
            let n = SCNNode(geometry: s); n.simdPosition = shift(h); out.append(n)
        }
        if mode == .all {
            let piPos = NSColor(red: 1.0, green: 0.62, blue: 0.15, alpha: 1), piNeg = NSColor(red: 0.2, green: 0.8, blue: 0.75, alpha: 1)
            let shapeKind = OrbitalMath.hybrids[0]
            _ = shapeKind
            for bond in res.pi {
                for atom in [bond.a, bond.b] {
                    let n = SCNNode(geometry: LobeCache.p(scale: 0.8, positive: piPos, negative: piNeg, alpha: 0.6))
                    n.simdPosition = shift(atom); orient(n, toward: bond.axis); out.append(n)
                }
            }
        }
        _ = at
        return out
    }
}
