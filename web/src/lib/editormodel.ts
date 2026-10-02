import { Sketch, SketchAtom, SketchBond, newId, bondLength, makeTemplate } from './sketch'
import { embed3D } from './embed3d'
import { Molecule } from './molecule'

export type Tool = 'Draw' | 'Move' | 'Erase'
export const atomRadius = 16

/** The molecule editor's state: the drawing, the selected tool and element, and undo history. */
export class EditorModel {
  sketch = new Sketch()
  tool: Tool = 'Draw'
  element = 'C'
  bondOrder = 1
  /** Only set when the user types a name. Otherwise the name follows the drawing. */
  customName = ''
  private templateName = ''
  private templateFormula = ''
  private undoStack: Sketch[] = []
  private redoStack: Sketch[] = []

  get name(): string {
    if (this.customName.trim()) return this.customName
    if (!this.sketch.atoms.length) return 'My molecule'
    return this.templateName && this.sketch.formula === this.templateFormula ? this.templateName : this.sketch.formula
  }
  get canUndo() { return this.undoStack.length > 0 }
  get canRedo() { return this.redoStack.length > 0 }

  snapshot() { this.undoStack.push(this.sketch.clone()); this.redoStack = []; if (this.undoStack.length > 100) this.undoStack.shift() }
  undo() { const s = this.undoStack.pop(); if (!s) return; this.redoStack.push(this.sketch); this.sketch = s }
  redo() { const s = this.redoStack.pop(); if (!s) return; this.undoStack.push(this.sketch); this.sketch = s }

  atomAt(x: number, y: number): SketchAtom | undefined {
    let best: SketchAtom | undefined, bd = Infinity
    for (const a of this.sketch.atoms) { const d = Math.hypot(a.x - x, a.y - y); if (d <= atomRadius && d < bd) { bd = d; best = a } }
    return best
  }
  bondAt(x: number, y: number): SketchBond | undefined {
    return this.sketch.bonds.find(b => { const a = this.sketch.atom(b.a), c = this.sketch.atom(b.b); return !!a && !!c && distanceToSegment(x, y, a.x, a.y, c.x, c.y) <= 7 })
  }
  /** Where a new bonded atom lands: one bond length away, snapped to the nearest 30°. */
  snapped(from: SketchAtom, x: number, y: number): { x: number; y: number } {
    const ang = Math.atan2(y - from.y, x - from.x), s = Math.round(ang / (Math.PI / 6)) * (Math.PI / 6)
    return { x: from.x + Math.cos(s) * bondLength, y: from.y + Math.sin(s) * bondLength }
  }

  addAtom(symbol: string, x: number, y: number): number { const a = { id: newId(), symbol, x, y }; this.sketch.atoms.push(a); return a.id }
  /** Joins two atoms; if they are already bonded the bond order cycles instead. */
  connect(a: number, b: number, order: number) {
    if (a === b) return
    const ex = this.sketch.bonds.find(x => (x.a === a && x.b === b) || (x.a === b && x.b === a))
    if (ex) ex.order = ex.order % 3 + 1; else this.sketch.bonds.push({ id: newId(), a, b, order })
  }
  cycle(bond: number) { const b = this.sketch.bonds.find(x => x.id === bond); if (b) b.order = b.order % 3 + 1 }
  setElement(id: number, symbol: string) { const a = this.sketch.atom(id); if (a) a.symbol = symbol }
  removeAtom(id: number) { this.sketch.atoms = this.sketch.atoms.filter(a => a.id !== id); this.sketch.bonds = this.sketch.bonds.filter(b => b.a !== id && b.b !== id) }
  removeBond(id: number) { this.sketch.bonds = this.sketch.bonds.filter(b => b.id !== id) }
  move(id: number, x: number, y: number) { const a = this.sketch.atom(id); if (a) { a.x = x; a.y = y } }
  clear() { this.snapshot(); this.sketch = new Sketch(); this.templateName = ''; this.customName = '' }
  addHydrogens() { this.snapshot(); this.sketch = this.sketch.addingHydrogens() }
  load(template: string, cx = 380, cy = 280) {
    this.snapshot(); this.sketch = makeTemplate(template, cx, cy); this.templateName = template; this.templateFormula = this.sketch.formula; this.customName = ''
  }
  molecule3D(): Molecule { return embed3D(this.sketch, this.name) }
}

export function distanceToSegment(px: number, py: number, ax: number, ay: number, bx: number, by: number): number {
  const dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy
  const t = l2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy))
}
