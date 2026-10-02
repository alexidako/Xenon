import SwiftUI
import SceneKit

/// Explore orbital shapes: atomic orbitals, hybrid sets, and how two orbitals overlap to form a bond.
struct OrbitalView: View {
    enum Mode: String, CaseIterable, Identifiable { case atomic = "Atomic", hybrid = "Hybrid", bonding = "Bonding"; var id: String { rawValue } }

    @State private var resetToken = 0
    @State private var mode: Mode = Mode(rawValue: ProcessInfo.processInfo.environment["XENON_ORBITAL_MODE"] ?? "") ?? .atomic
    @State private var atomic = ProcessInfo.processInfo.environment["XENON_ORBITAL"] ?? "pz"
    @State private var hybrid = ProcessInfo.processInfo.environment["XENON_HYBRID"] ?? "sp3"
    @State private var interaction = Interaction(rawValue: ProcessInfo.processInfo.environment["XENON_INTERACTION"] ?? "") ?? .sigmaPP
    @State private var antibonding = ProcessInfo.processInfo.environment["XENON_ANTI"] != nil
    @State private var distance = Double(ProcessInfo.processInfo.environment["XENON_DISTANCE"] ?? "") ?? 1.6

    enum Interaction: String, CaseIterable, Identifiable {
        case sigmaSS = "σ  s + s", sigmaSP = "σ  s + p", sigmaPP = "σ  p + p (end-on)", piPP = "π  p + p (side-on)"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 300)
                Button { resetToken += 1 } label: { Label("Reset view", systemImage: "arrow.counterclockwise") }
                    .help("Drag to rotate · scroll or pinch to zoom · double-click to reset")
                Spacer()
                legend
            }.padding(10)
            Divider()
            HSplitView {
                FixedSceneView(scene: scene, distance: mode == .bonding ? 8 : 6.5, tilt: (x: 0.32, y: 0.6), resetToken: resetToken,
                               sceneKey: "\(mode.rawValue)\(atomic)\(hybrid)\(interaction.rawValue)\(antibonding)\(distance)")   // tilted so lobes read as 3D
                    .id(mode.rawValue)          // new view only when the base camera distance changes
                    .frame(minWidth: 460)
                    .background(Color(white: 0.1))
                controls.frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            }
        }
        .navigationTitle("Orbitals")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            Label("positive phase (+)", systemImage: "circle.fill").foregroundStyle(Color(nsColor: OrbitalMesh.positive))
            Label("negative phase (−)", systemImage: "circle.fill").foregroundStyle(Color(nsColor: OrbitalMesh.negative))
        }.font(.caption)
    }

    // MARK: controls

    @ViewBuilder private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch mode {
                case .atomic:
                    Text("Atomic orbital").font(.headline)
                    Picker("", selection: $atomic) { ForEach(OrbitalMath.atomic) { Text($0.label).tag($0.id) } }.labelsHidden().pickerStyle(.radioGroup)
                    if let a = OrbitalMath.atomic.first(where: { $0.id == atomic }) { Text(a.kind).foregroundStyle(.secondary) }
                    Text("The two colors are the two signs of the wave function. Surfaces show the angular probability |ψ|². Where the sign changes the surface closes up: that is a node, a place the electron is never found.")
                        .font(.callout).foregroundStyle(.secondary)
                case .hybrid:
                    Text("Hybrid set").font(.headline)
                    Picker("", selection: $hybrid) { ForEach(OrbitalMath.hybrids) { Text($0.name).tag($0.id) } }.labelsHidden().pickerStyle(.radioGroup)
                    if let h = OrbitalMath.hybrids.first(where: { $0.id == hybrid }) {
                        Text(h.note).font(.callout).foregroundStyle(.secondary)
                        Text("Each lobe: ψ = \(coef(h.cs))·s + \(coef(h.cp))·p").font(.callout.monospaced())
                        Text("Each lobe has a small opposite-phase lobe on the far side (barely visible here).").font(.caption).foregroundStyle(.secondary)
                    }
                case .bonding:
                    Text("Overlap").font(.headline)
                    Picker("", selection: $interaction) { ForEach(Interaction.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().pickerStyle(.radioGroup)
                    Picker("", selection: $antibonding) { Text("Bonding (in phase)").tag(false); Text("Antibonding (out of phase)").tag(true) }
                        .pickerStyle(.segmented).labelsHidden()
                    LabeledContent("Distance") {
                        Slider(value: $distance, in: 0.6...4.0).frame(width: 150)
                    }
                    Text(overlapText).font(.callout).foregroundStyle(.secondary)
                    if antibonding {
                        Text("Out of phase, the lobes cancel between the nuclei and a node plane appears there (shown as a gray disc).").font(.callout)
                    } else {
                        Text("In phase, the lobes add up between the nuclei, which is what holds the atoms together.").font(.callout)
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func coef(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(3))) }

    private var overlapText: String {
        switch distance {
        case ..<1.0: return "Too close: the nuclei would repel each other."
        case ..<2.4: return "Good overlap: a strong bond forms at this distance."
        case ..<3.2: return "Weak overlap."
        default: return "Almost no overlap: no bond."
        }
    }

    // MARK: scenes

    private var scene: SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor(white: 0.1, alpha: 1)
        let root = scene.rootNode
        switch mode {
        case .atomic:
            root.addChildNode(OrbitalMesh.node(OrbitalMath.atomicFunction(atomic), scale: 1.6))
            addAxes(to: root, length: 2.2)
        case .hybrid:
            guard let h = OrbitalMath.hybrids.first(where: { $0.id == hybrid }) else { break }
            for d in h.directions {
                let n = SCNNode(geometry: LobeCache.hybrid(h, scale: 1.5, positive: OrbitalMesh.positive, negative: OrbitalMesh.negative, alpha: 0.7))
                orient(n, toward: d); root.addChildNode(n)
            }
            let nucleus = SCNNode(geometry: SCNSphere(radius: 0.07)); nucleus.geometry?.firstMaterial?.diffuse.contents = NSColor.white
            root.addChildNode(nucleus)
        case .bonding:
            buildBonding(root)
            addAxes(to: root, length: 0, drawAxis: false)
        }
        return scene
    }

    private func addAxes(to root: SCNNode, length: Double, drawAxis: Bool = true) {
        guard drawAxis else { return }
        for (axis, color) in [(V3(1, 0, 0), NSColor.systemRed), (V3(0, 1, 0), NSColor.systemGreen), (V3(0, 0, 1), NSColor.systemBlue)] {
            let c = SCNCylinder(radius: 0.012, height: CGFloat(length * 2)); c.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.55)
            let n = SCNNode(geometry: c)
            // cylinders are drawn along y
            n.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(Float(axis.x), Float(axis.y), Float(axis.z)))
            root.addChildNode(n)
        }
    }

    private func buildBonding(_ root: SCNNode) {
        let a = V3(-distance / 2, 0, 0), b = V3(distance / 2, 0, 0)
        let s = OrbitalMath.atomicFunction("s"), px = OrbitalMath.atomicFunction("px"), pz = OrbitalMath.atomicFunction("pz")
        let flip: Double = antibonding ? -1 : 1
        let fa: (V3) -> Double, fb: (V3) -> Double
        switch interaction {
        case .sigmaSS: fa = s; fb = { flip * s($0) }
        case .sigmaSP: fa = s; fb = { -flip * px($0) }                 // the + lobe of p faces the s orbital for in-phase overlap
        case .sigmaPP: fa = px; fb = { -flip * px($0) }                // each + lobe faces the other atom
        case .piPP: fa = pz; fb = { flip * pz($0) }                    // side by side, same sign above the bond axis
        }
        for (f, p) in [(fa, a), (fb, b)] {
            root.addChildNode(OrbitalMesh.node(f, scale: 1.25, at: p, alpha: 0.62))
            let nucleus = SCNNode(geometry: SCNSphere(radius: 0.07)); nucleus.geometry?.firstMaterial?.diffuse.contents = NSColor.white
            nucleus.simdPosition = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)); root.addChildNode(nucleus)
        }
        if antibonding {
            let plane = SCNCylinder(radius: 1.3, height: 0.01)
            plane.firstMaterial?.diffuse.contents = NSColor(white: 0.7, alpha: 1); plane.firstMaterial?.transparency = 0.22; plane.firstMaterial?.isDoubleSided = true
            let n = SCNNode(geometry: plane)
            n.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)         // disc facing the bond axis (x)
            root.addChildNode(n)
        }
    }
}
