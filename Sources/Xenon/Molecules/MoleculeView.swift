import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct MoleculeView: View {
    enum Style: String, CaseIterable, Identifiable { case ballStick = "Ball & stick", spaceFilling = "Space filling", sticks = "Sticks"; var id: String { rawValue } }

    @ObservedObject private var user = UserMolecules.shared
    @State private var imported: [Molecule] = []
    private var molecules: [Molecule] { (user.items + imported + MoleculeLibrary.bundled).map { optimized[$0.id] ?? $0 } }
    @State private var optimized: [Molecule.ID: Molecule] = [:]      // shapes found by "Optimize geometry", by molecule
    @State private var optimizing = false
    @State private var showAngles = ProcessInfo.processInfo.environment["XENON_ANGLES"] != nil
    @State private var selection: Molecule.ID?
    @State private var style: Style = Style(rawValue: ProcessInfo.processInfo.environment["XENON_MOL_STYLE"] ?? "") ?? .ballStick
    @State private var importing = false
    @State private var resetToken = 0
    @State private var shownAtoms: Set<Int> = []        // empty = every atom
    @State private var orbitals = OrbitalOverlay.Mode(rawValue: ProcessInfo.processInfo.environment["XENON_ORBITALS"] ?? "") ?? .off
    @State private var message = ""
    @State private var pendingDelete: Molecule?

    /// Molecules you made in the editor or opened from a file can be deleted; the bundled ones cannot.
    private func isCustom(_ m: Molecule) -> Bool { user.items.contains { $0.id == m.id } || imported.contains { $0.id == m.id } }

    private var current: Molecule? {
        molecules.first { $0.id == selection }
            ?? molecules.first { $0.name.lowercased() == (ProcessInfo.processInfo.environment["XENON_MOL"] ?? "\u{0}").lowercased() }
            ?? molecules.first { $0.name.lowercased().contains((ProcessInfo.processInfo.environment["XENON_MOL"] ?? "\u{0}").lowercased()) } ?? molecules.first
    }

    var body: some View {
        HSplitView {
            List(molecules, selection: $selection) { m in
                HStack {
                    Text(m.name)
                    if isCustom(m) { Spacer(); Image(systemName: "person.crop.circle").foregroundStyle(.secondary).help("Made by you") }
                }
                .tag(m.id)
                .contextMenu { if isCustom(m) { Button("Delete “\(m.name)”…", role: .destructive) { pendingDelete = m } } }
            }
            .frame(minWidth: 190, idealWidth: 220, maxWidth: 300)
            .onDeleteCommand { if let m = current, isCustom(m) { pendingDelete = m } }
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        Picker("Style", selection: $style) { ForEach(Style.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).frame(maxWidth: 320)
                        Picker("Orbitals", selection: $orbitals) { ForEach(OrbitalOverlay.Mode.allCases) { Text($0.rawValue).tag($0) } }
                            .frame(maxWidth: 300).help("Show the σ bonds, lone pairs and π bonds as orbital lobes")
                        Toggle("Bond angles", isOn: $showAngles).toggleStyle(.checkbox).fixedSize()
                            .help("Draw an arc and the angle in degrees at every pair of bonds")
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        Button { resetToken += 1 } label: { Label("Reset view", systemImage: "arrow.counterclockwise") }
                            .help("Drag to rotate · scroll or pinch to zoom · double-click to reset")
                        if let m = current { optimizeControls(m) }
                        if let m = current, isCustom(m) {
                            Button(role: .destructive) { pendingDelete = m } label: { Label("Delete", systemImage: "trash") }
                                .help("Delete this molecule from the list. Molecules you made yourself can be deleted; the built-in ones cannot.")
                        }
                        Spacer()
                        Button("Open file…") { importing = true }
                        Menu("Convert…") {
                            ForEach(MoleculeIO.Format.allCases, id: \.self) { f in
                                Button("Save as .\(f.rawValue)") { if let m = current { save(m, f) } }
                            }
                        }
                        .disabled(current == nil).fixedSize()
                    }
                }
                .padding(10)
                Divider()
                if let m = current {
                    if orbitals != .off || showAngles { atomFilter(m) }
                    MoleculeScene(molecule: m, style: style, orbitals: orbitals, atoms: shownAtoms, angles: showAngles, resetToken: resetToken)
                        .id("\(m.id)-\(style.rawValue)-\(orbitals.rawValue)-\(shownAtoms.sorted())-\(showAngles)-\(optimized[m.id] != nil)")
                    Divider()
                    HStack(spacing: 18) {
                        Text(m.name).font(.headline)
                        Text(Markup.formulaText(m.formula)).font(.body.monospaced())
                        Text("\(formatNumber(m.mass)) u")
                        Text("\(m.atoms.count) atoms, \(m.bonds.count) bonds").foregroundStyle(.secondary)
                        Spacer()
                        if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(10)
                } else {
                    Text("No molecule loaded").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: ["cml", "mol", "sdf", "xyz"].compactMap { UTType(filenameExtension: $0) } + [.data],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let m = MoleculeIO.load(url: url) { imported.append(m); selection = m.id; message = "" }
            else { message = "Could not read \(url.lastPathComponent)" }
        }
        .confirmationDialog(pendingDelete.map { "Delete “\($0.name)”?" } ?? "Delete molecule?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let m = pendingDelete { delete(m) }; pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("It disappears from the Molecules and Valence Bond lists and can't be brought back. Use Convert… first if you want a file copy.")
        }
        .onAppear { if let f = user.focus { selection = f } }
        .onChange(of: user.focus) { _, f in if let f { selection = f } }
        .navigationTitle("Molecules")
    }

    /// Removes a custom molecule and moves the selection to its neighbour in the list.
    private func delete(_ m: Molecule) {
        guard isCustom(m) else { return }
        let list = molecules
        let neighbour = list.firstIndex { $0.id == m.id }.flatMap { i in list.indices.contains(i + 1) ? list[i + 1].id : (i > 0 ? list[i - 1].id : nil) }
        user.remove(m.id)
        imported.removeAll { $0.id == m.id }
        optimized[m.id] = nil
        if selection == m.id || selection == nil { selection = neighbour }
        shownAtoms = []
        message = "Deleted “\(m.name)”"
    }

    /// Chips for choosing which atoms show their orbitals.
    @ViewBuilder private func atomFilter(_ m: Molecule) -> some View {
        let heavy = VBT.analyze(m).atoms.filter { $0.element?.symbol != "H" }
        let preset = (ProcessInfo.processInfo.environment["XENON_ORBITAL_ATOMS"] ?? "").split(separator: ",").map(String.init)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(orbitals != .off && showAngles ? "Show orbitals and angles of" : showAngles ? "Show angles of" : "Show orbitals of").font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                chip("All", on: shownAtoms.isEmpty) { shownAtoms = [] }
                ForEach(heavy) { a in
                    chip(a.label, on: shownAtoms.contains(a.index)) {
                        if shownAtoms.contains(a.index) { shownAtoms.remove(a.index) } else { shownAtoms.insert(a.index) }
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .onAppear { if shownAtoms.isEmpty { shownAtoms = Set(heavy.filter { preset.contains($0.label) }.map(\.index)) } }
        Divider()
    }

    /// "Optimize geometry" finds the lowest-energy shape; "Revert" brings back the original coordinates.
    @ViewBuilder private func optimizeControls(_ m: Molecule) -> some View {
        if optimized[m.id] != nil {
            Button("Revert") { optimized[m.id] = nil; message = "Original geometry restored" }
                .help("Go back to the geometry the file came with")
        }
        Button {
            let id = m.id, input = m
            optimizing = true; message = "Searching for the lowest-energy shape…"
            Task {
                let r = await Task.detached(priority: .userInitiated) { Optimizer.optimize(input) }.value
                optimized[id] = r.molecule; optimizing = false; resetToken += 1
                message = String(format: "Lowest-energy shape: %.1f → %.1f kcal/mol (%d starting shapes tried)", r.energyBefore, r.energyAfter, r.starts)
            }
        } label: {
            if optimizing { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Optimizing…") } }
            else { Label("Optimize geometry", systemImage: "wand.and.stars") }
        }
        .disabled(optimizing || m.atoms.count < 2)
        .help("Rearrange the atoms into the most stable 3D shape: it tries many starting shapes (every rotatable bond, ring puckers) and keeps the lowest-energy one. Uses a simplified force field, not quantum chemistry.")
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.callout.weight(.medium))
                .padding(.horizontal, 9).padding(.vertical, 2)
                .background(on ? Color.accentColor : Color.secondary.opacity(0.22), in: Capsule())
                .foregroundStyle(on ? Color.white : Color.primary)
        }.buttonStyle(.plain)
    }

    private func save(_ m: Molecule, _ f: MoleculeIO.Format) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = m.name.replacingOccurrences(of: " ", with: "_") + "." + f.rawValue
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try MoleculeIO.export(m, as: f).write(to: url, atomically: true, encoding: .utf8); message = "Saved \(url.lastPathComponent)" }
        catch { message = "Save failed: \(error.localizedDescription)" }
    }
}

struct MoleculeScene: View {
    let molecule: Molecule
    let style: MoleculeView.Style
    var orbitals: OrbitalOverlay.Mode = .off
    var atoms: Set<Int> = []
    var angles = false
    var resetToken = 0

    var body: some View {
        let (scene, distance) = buildScene()
        FixedSceneView(scene: scene, distance: distance, resetToken: resetToken)
            .background(Color(white: 0.1))
            .overlay(alignment: .bottomLeading) {
                Text("Drag to rotate · scroll to zoom · double-click to reset").font(.caption).foregroundStyle(.white.opacity(0.55)).padding(8)
            }
    }

    private func buildScene() -> (SCNScene, CGFloat) {
        let scene = SCNScene()
        scene.background.contents = NSColor(white: 0.1, alpha: 1)
        let info = Dictionary(uniqueKeysWithValues: ElementStore.all.map { ($0.symbol, $0) })
        let n = Double(molecule.atoms.count)
        let c = (x: molecule.atoms.reduce(0) { $0 + $1.x } / n, y: molecule.atoms.reduce(0) { $0 + $1.y } / n,
                 z: molecule.atoms.reduce(0) { $0 + $1.z } / n)
        let pts = molecule.atoms.map { SCNVector3($0.x - c.x, $0.y - c.y, $0.z - c.z) }
        let extent = pts.map { sqrt(Double($0.x * $0.x + $0.y * $0.y + $0.z * $0.z)) }.max() ?? 1

        func radius(_ a: MolAtom) -> Double {
            let e = info[a.symbol]
            switch style {
            case .ballStick: return 0.32 * max(0.6, e?.radiusCovalent ?? 0.8) + 0.08
            case .spaceFilling: return (e?.radiusVDW ?? 1.6) * 0.95
            case .sticks: return 0.11
            }
        }
        func color(_ a: MolAtom) -> NSColor {
            let c = (info[a.symbol]?.color ?? [0.6, 0.6, 0.6]) + [0.6, 0.6, 0.6]
            // Open Babel marks hydrogen white; keep it visible on the dark background.
            return NSColor(red: c[0], green: c[1], blue: c[2], alpha: 1)
        }

        for (i, a) in molecule.atoms.enumerated() {
            let s = SCNSphere(radius: radius(a))
            s.segmentCount = 32
            let m = SCNMaterial(); m.diffuse.contents = color(a); m.specular.contents = NSColor.white; m.shininess = 0.6
            s.materials = [m]
            let node = SCNNode(geometry: s); node.position = pts[i]; scene.rootNode.addChildNode(node)
        }

        if style != .spaceFilling {
            for b in molecule.bonds where b.a < pts.count && b.b < pts.count {
                let p = pts[b.a], q = pts[b.b]
                let dx = Double(q.x - p.x), dy = Double(q.y - p.y), dz = Double(q.z - p.z)
                let len = sqrt(dx * dx + dy * dy + dz * dz)
                guard len > 0 else { continue }
                // perpendicular offset for double/triple bonds
                var perp = SCNVector3(-dy, dx, 0)
                if abs(dx) < 1e-6 && abs(dy) < 1e-6 { perp = SCNVector3(1, 0, 0) }
                let pl = sqrt(Double(perp.x * perp.x + perp.y * perp.y + perp.z * perp.z))
                let unit = SCNVector3(Double(perp.x) / pl, Double(perp.y) / pl, Double(perp.z) / pl)
                let offsets: [Double] = b.order == 1 ? [0] : b.order == 2 ? [-0.1, 0.1] : [-0.18, 0, 0.18]
                for o in offsets {
                    let cyl = SCNCylinder(radius: style == .sticks ? 0.11 : (b.order == 1 ? 0.08 : 0.05), height: len)
                    let m = SCNMaterial(); m.diffuse.contents = NSColor(white: 0.75, alpha: 1); cyl.materials = [m]
                    let node = SCNNode(geometry: cyl)
                    node.position = SCNVector3((p.x + q.x) / 2 + unit.x * o, (p.y + q.y) / 2 + unit.y * o, (p.z + q.z) / 2 + unit.z * o)
                    node.look(at: SCNVector3(q.x + unit.x * o, q.y + unit.y * o, q.z + unit.z * o), up: scene.rootNode.worldUp,
                              localFront: SCNVector3(0, 1, 0))
                    scene.rootNode.addChildNode(node)
                }
            }
        }

        for n in OrbitalOverlay.nodes(for: molecule, pts: pts, mode: orbitals, atoms: atoms) { scene.rootNode.addChildNode(n) }
        if angles {
            for n in AngleOverlay.nodes(for: molecule, pts: pts, atoms: atoms, atomRadius: { radius(molecule.atoms[$0]) }) { scene.rootNode.addChildNode(n) }
        }

        return (scene, CGFloat(extent * 2.6 + 4))
    }
}
