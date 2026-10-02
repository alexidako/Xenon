import SwiftUI

/// Molecules handed over from the editor, and a way for one screen to ask the app to switch to another.
final class UserMolecules: ObservableObject {
    static let shared = UserMolecules()
    @Published var items: [Molecule] = []
    @Published var focus: Molecule.ID?

    func add(_ m: Molecule) {
        items.removeAll { $0.name == m.name }
        items.insert(m, at: 0)
        focus = m.id
    }

    func remove(_ id: Molecule.ID) {
        items.removeAll { $0.id == id }
        if focus == id { focus = nil }
    }
}

final class Navigation: ObservableObject {
    static let shared = Navigation()
    @Published var target: Screen?
}

@MainActor
final class EditorModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case draw = "Draw", move = "Move", erase = "Erase"
        var id: String { rawValue }
        var icon: String { self == .draw ? "pencil" : self == .move ? "arrow.up.and.down.and.arrow.left.and.right" : "eraser" }
    }

    @Published var sketch = Sketch()
    @Published var tool: Tool = .draw
    @Published var element = "C"
    @Published var bondOrder = 1
    /// Only set when the user types a name. Otherwise the name follows the drawing.
    @Published var customName = ""
    private var templateName = ""
    private var templateFormula = ""

    var name: String {
        if !customName.trimmingCharacters(in: .whitespaces).isEmpty { return customName }
        if sketch.atoms.isEmpty { return "My molecule" }
        return !templateName.isEmpty && sketch.formula == templateFormula ? templateName : sketch.formula
    }

    private var undoStack: [Sketch] = []
    private var redoStack: [Sketch] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    static let atomRadius = 16.0

    // MARK: history

    func snapshot() {
        undoStack.append(sketch); redoStack.removeAll()
        if undoStack.count > 100 { undoStack.removeFirst() }
    }
    func undo() { guard let s = undoStack.popLast() else { return }; redoStack.append(sketch); sketch = s }
    func redo() { guard let s = redoStack.popLast() else { return }; undoStack.append(sketch); sketch = s }

    // MARK: hit testing

    func atom(at p: CGPoint) -> SketchAtom? {
        sketch.atoms.filter { hypot($0.x - p.x, $0.y - p.y) <= Self.atomRadius }
            .min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }
    }

    func bond(at p: CGPoint) -> SketchBond? {
        sketch.bonds.first { b in
            guard let a = sketch.atom(b.a), let c = sketch.atom(b.b) else { return false }
            return Self.distance(from: p, toSegment: (CGPoint(x: a.x, y: a.y), CGPoint(x: c.x, y: c.y))) <= 7
        }
    }

    static func distance(from p: CGPoint, toSegment s: (CGPoint, CGPoint)) -> Double {
        let dx = s.1.x - s.0.x, dy = s.1.y - s.0.y
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - s.0.x) * dx + (p.y - s.0.y) * dy) / len2))
        return hypot(p.x - (s.0.x + t * dx), p.y - (s.0.y + t * dy))
    }

    /// Where a new bonded atom lands: one bond length away, snapped to the nearest 30°.
    func snapped(from a: SketchAtom, toward p: CGPoint) -> CGPoint {
        let ang = atan2(p.y - a.y, p.x - a.x)
        let snappedAngle = (ang / (.pi / 6)).rounded() * (.pi / 6)
        return CGPoint(x: a.x + cos(snappedAngle) * Sketch.bondLength, y: a.y + sin(snappedAngle) * Sketch.bondLength)
    }

    // MARK: edits (callers take the snapshot)

    @discardableResult func addAtom(_ symbol: String, at p: CGPoint) -> UUID {
        let a = SketchAtom(symbol: symbol, x: p.x, y: p.y)
        sketch.atoms.append(a)
        return a.id
    }

    /// Joins two atoms; if they are already bonded the bond order cycles instead.
    func connect(_ a: UUID, _ b: UUID, order: Int) {
        guard a != b else { return }
        if let i = sketch.bonds.firstIndex(where: { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) }) {
            sketch.bonds[i].order = sketch.bonds[i].order % 3 + 1
        } else {
            sketch.bonds.append(SketchBond(a: a, b: b, order: order))
        }
    }

    func cycle(_ bond: UUID) {
        if let i = sketch.bonds.firstIndex(where: { $0.id == bond }) { sketch.bonds[i].order = sketch.bonds[i].order % 3 + 1 }
    }

    func setElement(_ id: UUID, _ symbol: String) {
        if let i = sketch.atoms.firstIndex(where: { $0.id == id }) { sketch.atoms[i].symbol = symbol }
    }

    func removeAtom(_ id: UUID) {
        sketch.atoms.removeAll { $0.id == id }
        sketch.bonds.removeAll { $0.a == id || $0.b == id }
    }

    func removeBond(_ id: UUID) { sketch.bonds.removeAll { $0.id == id } }

    func move(_ id: UUID, to p: CGPoint) {
        if let i = sketch.atoms.firstIndex(where: { $0.id == id }) { sketch.atoms[i].x = p.x; sketch.atoms[i].y = p.y }
    }

    func clear() { snapshot(); sketch = Sketch(); templateName = ""; customName = "" }

    func addHydrogens() { snapshot(); sketch = sketch.addingHydrogens() }

    func load(template: String, center: CGPoint = CGPoint(x: 380, y: 280)) {
        snapshot()
        sketch = SketchTemplates.make(template, cx: center.x, cy: center.y)
        templateName = template; templateFormula = sketch.formula; customName = ""
    }

    // MARK: hand-off

    func molecule3D() -> Molecule { Embed3D.embed(sketch, name: name) }
}
