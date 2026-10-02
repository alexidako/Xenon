import SwiftUI

/// Draw a molecule: click to place atoms, drag to bond them. Hydrogens fill in automatically.
struct EditorView: View {
    /// Shared so the drawing survives switching to another screen and back.
    @ObservedObject private var model = EditorView.sharedModel

    private static let sharedModel: EditorModel = {
        let m = EditorModel()
        if let t = ProcessInfo.processInfo.environment["XENON_EDITOR"], SketchTemplates.names.contains(t) { m.load(template: t) }
        return m
    }()

    private let quick = ["C", "H", "N", "O", "S", "P", "F", "Cl", "Br", "I"]
    private let more = ElementStore.all.filter { Sketch.valences[$0.symbol] != nil }.map(\.symbol)

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar.padding(10)
                Divider()
                SketchCanvas(model: model)
            }
            Divider()
            inspector.frame(width: 300)
        }
        .navigationTitle("Molecule Editor")
        .onAppear {
            // Visual tests need every scenario to start from a known drawing.
            guard VRT.isActive else { return }
            model.clear()
            if let t = ProcessInfo.processInfo.environment["XENON_EDITOR"], SketchTemplates.names.contains(t) { model.load(template: t) }
        }
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            Picker("Tool", selection: $model.tool) {
                ForEach(EditorModel.Tool.allCases) { Label(tr($0.rawValue), systemImage: $0.icon).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 230)

            HStack(spacing: 4) {
                ForEach(quick, id: \.self) { s in
                    Button(s) { model.element = s; model.tool = .draw }
                        .buttonStyle(.bordered).tint(model.element == s ? .accentColor : .gray)
                        .controlSize(.small)
                }
                Menu("More") { ForEach(more, id: \.self) { s in Button(s) { model.element = s; model.tool = .draw } } }.fixedSize().controlSize(.small)
            }

            Picker("Bond", selection: $model.bondOrder) {
                Text("—").tag(1); Text("=").tag(2); Text("≡").tag(3)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 100).help("Order of newly drawn bonds. Click an existing bond to cycle it.")
            Spacer()
        }
    }

    // MARK: inspector

    private var inspector: some View {
        let s = model.sketch
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Name", text: $model.customName, prompt: Text(model.name)).textFieldStyle(.roundedBorder)

                if s.atoms.isEmpty {
                    Text("Click the canvas to place an atom, then drag from it to draw a bond. Pick a template to start from a common molecule.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Markup.attributed(formulaMarkup(s.formula))).font(.system(size: 30, weight: .bold))
                        Text("\(formatNumber(s.mass)) u").font(.title3).foregroundStyle(.secondary)
                        Text(tr("{atoms} atoms, {bonds} bonds", ["atoms": s.atoms.count, "bonds": s.bonds.count])).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(Array(s.problems.enumerated()), id: \.offset) { _, p in
                        Label(p.message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                    }
                }

                GroupBox("Edit") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(!model.canUndo)
                                .keyboardShortcut("z", modifiers: .command)
                            Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(!model.canRedo)
                                .keyboardShortcut("z", modifiers: [.command, .shift])
                        }
                        HStack {
                            Button("Add hydrogens") { model.addHydrogens() }.disabled(s.atoms.isEmpty)
                            Button("Clear", role: .destructive) { model.clear() }.disabled(s.atoms.isEmpty)
                        }
                        Menu("Start from a template") {
                            ForEach(SketchTemplates.names, id: \.self) { t in Button(tr(t)) { model.load(template: t) } }
                        }
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Use this molecule") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { send(to: .molecules) } label: { Label("View in 3D", systemImage: "cube") }
                        Button { send(to: .vbt) } label: { Label("Analyze with valence bond theory", systemImage: "link") }
                        Menu {
                            ForEach(MoleculeIO.Format.allCases, id: \.self) { f in Button(tr("Save as .{ext}", ["ext": f.rawValue])) { save(f) } }
                        } label: { Label("Save…", systemImage: "square.and.arrow.down") }
                    }
                    .disabled(s.atoms.isEmpty).padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("3D coordinates are generated from your drawing, so angles and lengths are estimates.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    /// "C2H6O" -> "C[sub]2[/sub]H[sub]6[/sub]O" so the shared markup renderer draws real subscripts.
    private func formulaMarkup(_ f: String) -> String {
        var out = "", digits = ""
        for ch in f {
            if ch.isNumber { digits.append(ch) } else {
                if !digits.isEmpty { out += "[sub]\(digits)[/sub]"; digits = "" }
                out.append(ch)
            }
        }
        if !digits.isEmpty { out += "[sub]\(digits)[/sub]" }
        return out
    }

    private func send(to screen: Screen) {
        UserMolecules.shared.add(model.molecule3D())
        Navigation.shared.target = screen
    }

    private func save(_ f: MoleculeIO.Format) {
        let m = model.molecule3D()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.name.replacingOccurrences(of: " ", with: "_") + "." + f.rawValue
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? MoleculeIO.export(m, as: f).write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: canvas

struct SketchCanvas: View {
    @ObservedObject var model: EditorModel

    @State private var dragStartAtom: SketchAtom?
    @State private var dragStartBond: SketchBond?
    @State private var dragStart: CGPoint = .zero
    @State private var dragNow: CGPoint = .zero
    @State private var dragging = false
    @State private var grab: CGSize = .zero

    var body: some View {
        Canvas { ctx, size in
            draw(ctx, size)
        }
        .background(Color(white: 0.11))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in changed(v) }
            .onEnded { v in ended(v) })
        .help("Click to place an atom, drag from an atom to make a bond, click a bond to change its order")
    }

    // MARK: drawing

    private static func labelColor(_ symbol: String) -> Color {
        if symbol == "C" { return Color(white: 0.88) }
        guard let e = ElementStore.all.first(where: { $0.symbol == symbol }), e.color.count == 3 else { return .white }
        return Color(red: max(0.3, e.color[0]), green: max(0.3, e.color[1]), blue: max(0.3, e.color[2]))
    }

    private func label(_ a: SketchAtom) -> String {
        let h = model.sketch.implicitHydrogens(a.id) ?? 0
        let hs = h == 0 ? "" : h == 1 ? "H" : "H" + Markup.plain("[sub]\(h)[/sub]")
        return a.symbol + (a.symbol == "H" ? "" : hs)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let s = model.sketch
        let bad = Set(s.problems.map(\.atom.id))

        for b in s.bonds {
            guard let a = s.atom(b.a), let c = s.atom(b.b) else { continue }
            let dx = c.x - a.x, dy = c.y - a.y, len = max(1, hypot(dx, dy))
            let ux = dx / len, uy = dy / len, px = -uy, py = ux
            let trim = min(11.0, len / 2 - 1)
            let offsets: [Double] = b.order == 1 ? [0] : b.order == 2 ? [-3.5, 3.5] : [-5, 0, 5]
            for o in offsets {
                var p = Path()
                p.move(to: CGPoint(x: a.x + ux * trim + px * o, y: a.y + uy * trim + py * o))
                p.addLine(to: CGPoint(x: c.x - ux * trim + px * o, y: c.y - uy * trim + py * o))
                ctx.stroke(p, with: .color(Color(white: 0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }

        for a in s.atoms {
            let pt = CGPoint(x: a.x, y: a.y)
            if bad.contains(a.id) {
                ctx.fill(Path(ellipseIn: CGRect(x: a.x - 15, y: a.y - 15, width: 30, height: 30)), with: .color(.red.opacity(0.35)))
            }
            ctx.draw(Text(label(a)).font(.system(size: 17, weight: .semibold)).foregroundColor(Self.labelColor(a.symbol)), at: pt, anchor: .center)
        }

        // rubber band while drawing a bond
        if dragging, model.tool == .draw {
            let from = dragStartAtom.map { CGPoint(x: $0.x, y: $0.y) } ?? dragStart
            var p = Path(); p.move(to: from); p.addLine(to: dragNow)
            ctx.stroke(p, with: .color(.accentColor.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
        }
        if model.tool == .erase {
            ctx.draw(Text("Click an atom or bond to delete it").font(.caption).foregroundColor(.secondary), at: CGPoint(x: size.width / 2, y: size.height - 14))
        }
    }

    // MARK: gestures

    private func changed(_ v: DragGesture.Value) {
        dragNow = v.location
        if !dragging {
            dragging = true
            dragStart = v.startLocation
            dragStartAtom = model.atom(at: v.startLocation)
            dragStartBond = dragStartAtom == nil ? model.bond(at: v.startLocation) : nil
            if model.tool == .move, let a = dragStartAtom {
                model.snapshot()
                grab = CGSize(width: a.x - v.startLocation.x, height: a.y - v.startLocation.y)
            }
        }
        if model.tool == .move, let a = dragStartAtom {
            model.move(a.id, to: CGPoint(x: v.location.x + grab.width, y: v.location.y + grab.height))
        }
    }

    private func ended(_ v: DragGesture.Value) {
        defer { dragging = false; dragStartAtom = nil; dragStartBond = nil }
        let moved = hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
        let end = v.location

        switch model.tool {
        case .move: break
        case .erase:
            if let a = dragStartAtom { model.snapshot(); model.removeAtom(a.id) }
            else if let b = dragStartBond { model.snapshot(); model.removeBond(b.id) }
        case .draw:
            if let a = dragStartAtom {
                if moved < 6 {
                    if a.symbol != model.element { model.snapshot(); model.setElement(a.id, model.element) }
                } else if let other = model.atom(at: end), other.id != a.id {
                    model.snapshot(); model.connect(a.id, other.id, order: model.bondOrder)
                } else {
                    model.snapshot()
                    let spot = model.snapped(from: a, toward: end)
                    let target = model.atom(at: spot)?.id ?? model.addAtom(model.element, at: spot)
                    model.connect(a.id, target, order: model.bondOrder)
                }
            } else if let b = dragStartBond, moved < 6 {
                model.snapshot(); model.cycle(b.id)
            } else if moved < 6 {
                model.snapshot(); model.addAtom(model.element, at: v.startLocation)
            } else {
                model.snapshot()
                let first = model.addAtom(model.element, at: v.startLocation)
                let startAtom = model.sketch.atom(first)!
                let spot = model.snapped(from: startAtom, toward: end)
                let second = model.atom(at: spot)?.id ?? model.addAtom(model.element, at: spot)
                model.connect(first, second, order: model.bondOrder)
            }
        }
    }
}
