import { elementBySymbol } from './element'
import { Molecule } from './molecule'

export interface SketchAtom { id: number; symbol: string; x: number; y: number }
export interface SketchBond { id: number; a: number; b: number; order: number }

let nextId = 1
export const newId = () => nextId++

export const bondLength = 46

export const valences: Record<string, number[]> = {
  H: [1], B: [3], C: [4], N: [3, 5], O: [2], F: [1], Si: [4], P: [3, 5], S: [2, 4, 6], Cl: [1], Se: [2, 4, 6], Br: [1], I: [1, 3, 5],
}

/** A 2D drawing of a molecule. Hydrogens on heavy atoms are implicit (filled from valence) until "Add hydrogens". */
export class Sketch {
  constructor(public atoms: SketchAtom[] = [], public bonds: SketchBond[] = []) {}
  clone(): Sketch { return new Sketch(this.atoms.map(a => ({ ...a })), this.bonds.map(b => ({ ...b }))) }

  atom(id: number) { return this.atoms.find(a => a.id === id) }
  bondsOf(id: number) { return this.bonds.filter(b => b.a === id || b.b === id) }
  neighbors(id: number) { return this.bondsOf(id).map(b => b.a === id ? b.b : b.a) }
  bondOrderSum(id: number) { return this.bondsOf(id).reduce((s, b) => s + b.order, 0) }

  /** Hydrogens needed to complete the atom's valence. null means the atom has too many bonds. */
  implicitHydrogens(id: number): number | null {
    const a = this.atom(id)
    const options = a ? valences[a.symbol] : undefined
    if (!a || !options) return 0              // metals etc.: no guessing
    const s = this.bondOrderSum(id)
    const v = options.find(o => o >= s)
    return v == null ? null : v - s
  }

  get problems(): { atom: SketchAtom; message: string }[] {
    return this.atoms.filter(a => this.implicitHydrogens(a.id) == null)
      .map(atom => ({ atom, message: `${atom.symbol} has ${this.bondOrderSum(atom.id)} bonds; at most ${Math.max(...(valences[atom.symbol] ?? [0]))} are allowed.` }))
  }

  /** Element counts including implicit hydrogens. */
  get counts(): Record<string, number> {
    const c: Record<string, number> = {}
    for (const a of this.atoms) { c[a.symbol] = (c[a.symbol] ?? 0) + 1; c.H = (c.H ?? 0) + (this.implicitHydrogens(a.id) ?? 0) }
    return Object.fromEntries(Object.entries(c).filter(([, v]) => v > 0))
  }

  /** Hill order: C, H, then alphabetical. */
  get formula(): string {
    const c = this.counts
    const part = (s: string) => c[s] == null ? '' : c[s] === 1 ? s : `${s}${c[s]}`
    let out = c.C != null ? part('C') + part('H') : ''
    for (const s of Object.keys(c).sort()) if (!(c.C != null && (s === 'C' || s === 'H'))) out += part(s)
    return out
  }
  get mass(): number { return Object.entries(this.counts).reduce((s, [k, v]) => s + (elementBySymbol.get(k)?.mass ?? 0) * v, 0) }

  /** A copy with every implicit hydrogen drawn as its own atom, placed in the biggest free angle around its parent. */
  addingHydrogens(): Sketch {
    const s = this.clone()
    for (const a of this.atoms) {
      const n = this.implicitHydrogens(a.id)
      if (!n || n <= 0) continue
      const angles = this.neighbors(a.id).flatMap(id => { const o = s.atom(id); return o ? [Math.atan2(o.y - a.y, o.x - a.x)] : [] })
      for (let k = 0; k < n; k++) {
        const dir = largestGapMiddle(angles); angles.push(dir)
        const h: SketchAtom = { id: newId(), symbol: 'H', x: a.x + Math.cos(dir) * bondLength * 0.75, y: a.y + Math.sin(dir) * bondLength * 0.75 }
        s.atoms.push(h); s.bonds.push({ id: newId(), a: a.id, b: h.id, order: 1 })
      }
    }
    return s
  }

  /** Flat (z = 0) molecule at about 1.5 Å per bond; used for export of the 2D drawing. */
  toMolecule(name: string): Molecule {
    const full = this.addingHydrogens()
    const index = new Map(full.atoms.map((a, i) => [a.id, i]))
    const k = 1.5 / bondLength
    return {
      name, atoms: full.atoms.map(a => ({ symbol: a.symbol, x: a.x * k, y: -a.y * k, z: 0 })),
      bonds: full.bonds.flatMap(b => { const i = index.get(b.a), j = index.get(b.b); return i != null && j != null ? [{ a: i, b: j, order: b.order }] : [] }),
    }
  }
}

export function largestGapMiddle(angles: number[]): number {
  if (!angles.length) return -Math.PI / 2
  const sorted = angles.map(a => { let x = a % (2 * Math.PI); if (x < 0) x += 2 * Math.PI; return x }).sort((p, q) => p - q)
  let best = { gap: -1, mid: 0 }
  for (let i = 0; i < sorted.length; i++) {
    const next = i + 1 < sorted.length ? sorted[i + 1] : sorted[0] + 2 * Math.PI
    const gap = next - sorted[i]
    if (gap > best.gap) best = { gap, mid: sorted[i] + gap / 2 }
  }
  return best.mid
}

export const templateNames = ['Water', 'Methane', 'Ammonia', 'Ethanol', 'Propane', 'Acetone', 'Acetic acid', 'Ethene', 'Ethyne', 'Carbon dioxide', 'Benzene', 'Cyclohexane']

/** Template centred on (cx, cy). */
export function makeTemplate(name: string, cx: number, cy: number): Sketch {
  const s = new Sketch(); const L = bondLength
  const add = (symbol: string, x: number, y: number) => { const a = { id: newId(), symbol, x: cx + x, y: cy + y }; s.atoms.push(a); return a.id }
  const bond = (a: number, b: number, order = 1) => s.bonds.push({ id: newId(), a, b, order })
  const dx = L * Math.cos(Math.PI / 6), dy = L * Math.sin(Math.PI / 6)
  switch (name) {
    case 'Water': add('O', 0, 0); break
    case 'Methane': add('C', 0, 0); break
    case 'Ammonia': add('N', 0, 0); break
    case 'Ethanol': case 'Propane': {
      const a = add('C', -dx, dy / 2), b = add('C', 0, -dy / 2), c = add(name === 'Ethanol' ? 'O' : 'C', dx, dy / 2)
      bond(a, b); bond(b, c); break
    }
    case 'Acetone': {
      const a = add('C', -dx, dy / 2), b = add('C', 0, -dy / 2), c = add('C', dx, dy / 2), o = add('O', 0, -dy / 2 - L)
      bond(a, b); bond(b, c); bond(b, o, 2); break
    }
    case 'Acetic acid': {
      const a = add('C', -dx, dy / 2), b = add('C', 0, -dy / 2), o1 = add('O', 0, -dy / 2 - L), o2 = add('O', dx, dy / 2)
      bond(a, b); bond(b, o1, 2); bond(b, o2); break
    }
    case 'Ethene': { const a = add('C', -L / 2, 0), b = add('C', L / 2, 0); bond(a, b, 2); break }
    case 'Ethyne': { const a = add('C', -L / 2, 0), b = add('C', L / 2, 0); bond(a, b, 3); break }
    case 'Carbon dioxide': { const o1 = add('O', -L, 0), c = add('C', 0, 0), o2 = add('O', L, 0); bond(o1, c, 2); bond(c, o2, 2); break }
    case 'Benzene': case 'Cyclohexane': {
      const r = L / (2 * Math.sin(Math.PI / 6))
      const ids = Array.from({ length: 6 }, (_, k) => { const t = -Math.PI / 2 + k * Math.PI / 3; return add('C', r * Math.cos(t), r * Math.sin(t)) })
      for (let k = 0; k < 6; k++) bond(ids[k], ids[(k + 1) % 6], name === 'Benzene' && k % 2 === 0 ? 2 : 1)
      break
    }
  }
  return s
}
