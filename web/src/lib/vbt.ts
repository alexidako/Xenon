import { Element, elementBySymbol, gridPosition } from './element'
import { Molecule } from './molecule'

/** Valence bond theory for a single atom: lone pairs, hybridization, VSEPR geometry and orbital boxes. */
export type BoxKind = 's' | 'p' | 'd' | 'hybridLonePair' | 'hybridBond' | 'piP' | 'piD'
export interface Box { label: string; electrons: number; kind: BoxKind }

export class Hybridization {
  constructor(readonly element: Element, readonly valence: number, readonly charge: number, readonly sigma: number, readonly pi: number, readonly lonePairs: number) {}

  /** Valence electrons of a main-group element; null for transition metals and f-block. */
  static valenceElectrons(e: Element): number | null {
    if (e.z === 2) return 2
    const p = gridPosition(e.z)
    if (p.row >= 8) return null
    if (p.col === 0 || p.col === 1) return p.col + 1
    if (p.col >= 12 && p.col <= 17) return p.col - 9
    return null
  }

  get shell() { return gridPosition(this.element.z).row + 1 }

  /** null when the bonding does not fit (an ion, a dative bond, or an impossible count). */
  static make(e: Element, sigma: number, pi: number, charge = 0): Hybridization | null {
    const v = Hybridization.valenceElectrons(e)
    if (v == null || sigma < 0 || pi < 0) return null
    const have = v - charge
    const rest = have - sigma - pi
    if (rest < 0 || rest % 2 !== 0) return null
    const around = rest + 2 * (sigma + pi)
    if (around > (gridPosition(e.z).row <= 1 ? 8 : 12)) return null
    return new Hybridization(e, have, charge, sigma, pi, rest / 2)
  }

  /** Like `make`, but tries formal charges 0, −1, +1, −2, +2 (carbon monoxide's C⁻ and O⁺, ammonium's N⁺ …). */
  static makeAllowingCharge(e: Element, sigma: number, pi: number): Hybridization | null {
    const options = [0, -1, 1, -2, 2].map(c => Hybridization.make(e, sigma, pi, c)).filter((h): h is Hybridization => h != null)
    const gap = (h: Hybridization) => { const around = 2 * h.lonePairs + 2 * (h.sigma + h.pi); return around >= 8 ? 0 : 8 - around }
    let best: Hybridization | null = null
    for (const o of options) if (!best || gap(o) < gap(best) || (gap(o) === gap(best) && Math.abs(o.charge) < Math.abs(best.charge))) best = o
    return best
  }

  get steric() { return this.sigma + this.lonePairs }
  get hybridName(): string | null { return ({ 2: 'sp', 3: 'sp²', 4: 'sp³', 5: 'sp³d', 6: 'sp³d²', 7: 'sp³d³' } as Record<number, string>)[this.steric] ?? null }
  /** (s, p, d) orbitals mixed into the hybrid set. */
  get mix(): { s: number; p: number; d: number } {
    switch (this.steric) {
      case 2: return { s: 1, p: 1, d: 0 }
      case 3: return { s: 1, p: 2, d: 0 }
      case 4: return { s: 1, p: 3, d: 0 }
      case 5: return { s: 1, p: 3, d: 1 }
      case 6: return { s: 1, p: 3, d: 2 }
      case 7: return { s: 1, p: 3, d: 3 }
      default: return { s: 1, p: 0, d: 0 }
    }
  }
  get electronGeometry(): string | null {
    return ['linear', 'trigonal planar', 'tetrahedral', 'trigonal bipyramidal', 'octahedral', 'pentagonal bipyramidal'][this.steric - 2] ?? null
  }

  /** Molecular shape and the ideal bond angle for this combination of bonds and lone pairs. */
  get shape(): { name: string; angle: string } | null {
    const k = `${this.steric},${this.lonePairs}`
    const t: Record<string, [string, string]> = {
      '2,0': ['linear', '180°'], '2,1': ['terminal atom (one neighbour)', '—'], '3,2': ['terminal atom (one neighbour)', '—'],
      '3,0': ['trigonal planar', '120°'], '3,1': ['bent', '<120°'], '4,0': ['tetrahedral', '109.5°'],
      '4,1': ['trigonal pyramidal', '<109.5° (≈107°)'], '4,2': ['bent', '<109.5° (≈104.5°)'], '4,3': ['linear (two atoms)', '—'],
      '5,0': ['trigonal bipyramidal', '90° and 120°'], '5,1': ['seesaw', '<90° and <120°'], '5,2': ['T-shaped', '<90°'], '5,3': ['linear', '180°'],
      '6,0': ['octahedral', '90°'], '6,1': ['square pyramidal', '<90°'], '6,2': ['square planar', '90°'], '7,0': ['pentagonal bipyramidal', '72° and 90°'],
    }
    const v = t[k]; return v ? { name: v[0], angle: v[1] } : null
  }

  /** Valence orbitals of the free atom, filled by Hund's rule. Empty d boxes appear when d orbitals take part. */
  get groundState(): Box[] {
    const n = this.shell
    const boxes: Box[] = [{ label: `${n}s`, electrons: Math.min(2, this.valence), kind: 's' }]
    let left = Math.max(0, this.valence - 2)
    const p = [0, 0, 0]
    for (let i = 0; i < 3 && left > 0; i++) { p[i] = 1; left-- }
    for (let i = 0; i < 3 && left > 0; i++) { p[i]++; left-- }
    for (const c of p) boxes.push({ label: `${n}p`, electrons: c, kind: 'p' })
    for (let i = 0; i < this.mix.d; i++) boxes.push({ label: `${n}d`, electrons: 0, kind: 'd' })
    return boxes
  }

  /** After mixing: hybrids hold the lone pairs and σ bonds; leftover p (or d) orbitals hold the π bonds. */
  get hybridized(): Box[] {
    const name = this.hybridName
    if (!name) return this.groundState
    const boxes: Box[] = []
    for (let i = 0; i < this.lonePairs; i++) boxes.push({ label: name, electrons: 2, kind: 'hybridLonePair' })
    for (let i = 0; i < this.sigma; i++) boxes.push({ label: name, electrons: 1, kind: 'hybridBond' })
    const pFree = Math.max(0, 3 - this.mix.p)
    let piLeft = this.pi
    for (let i = 0; i < pFree; i++) { boxes.push({ label: `${this.shell}p`, electrons: piLeft > 0 ? 1 : 0, kind: 'piP' }); piLeft-- }
    while (piLeft > 0) { boxes.push({ label: `${this.shell}d`, electrons: 1, kind: 'piD' }); piLeft-- }
    return boxes
  }

  /** True when the ground-state electrons must be rearranged (promotion) to form the bonds. */
  get needsPromotion(): boolean {
    const unpaired = (b: Box[]) => b.filter(x => x.electrons === 1).length
    return unpaired(this.groundState) !== unpaired(this.hybridized) || this.mix.d > 0
  }
  get summary() { return `${this.element.symbol}${chargeText(this.charge)}: ${this.sigma} σ, ${this.pi} π, ${this.lonePairs} lone pair${this.lonePairs === 1 ? '' : 's'}` }
}

export const chargeText = (c: number) => c === 0 ? '' : (Math.abs(c) === 1 ? '' : String(Math.abs(c))) + (c > 0 ? '⁺' : '⁻')

// MARK: whole molecules

export interface AtomAnalysis {
  index: number; label: string; element: Element | undefined; neighbors: number[]
  hybrid: Hybridization | null; note: string | null; measuredAngles: number[]
}
export interface BondAnalysis { id: number; label: string; detail: string }

export function analyzeMolecule(m: Molecule): { atoms: AtomAnalysis[]; bonds: BondAnalysis[] } {
  const neighbors: number[][] = m.atoms.map(() => [])
  const pi = m.atoms.map(() => 0)
  for (const b of m.bonds) {
    if (b.a >= m.atoms.length || b.b >= m.atoms.length) continue
    neighbors[b.a].push(b.b); neighbors[b.b].push(b.a)
    pi[b.a] += b.order - 1; pi[b.b] += b.order - 1
  }
  const counts = new Map<string, number>()
  const labels = m.atoms.map(a => { const n = (counts.get(a.symbol) ?? 0) + 1; counts.set(a.symbol, n); return `${a.symbol}${n}` })
  const atoms = m.atoms.map((a, i): AtomAnalysis => {
    const e = elementBySymbol.get(a.symbol)
    let hyb: Hybridization | null = null, note: string | null = null
    if (e && e.symbol !== 'H') {
      hyb = Hybridization.makeAllowingCharge(e, neighbors[i].length, pi[i])
      if (!hyb) note = 'These bonds cannot be explained for a main-group atom, even with a formal charge.'
      else if (hyb.charge !== 0) note = `Formal charge ${hyb.charge > 0 ? '+' : '−'}${Math.abs(hyb.charge)}.`
      else if (hyb.hybridName == null) note = 'Too few electron domains to hybridize.'
    }
    return { index: i, label: labels[i], element: e, neighbors: neighbors[i], hybrid: hyb, note, measuredAngles: bondAngles(i, m, neighbors[i]) }
  })
  const orbital = (i: number) => m.atoms[i].symbol === 'H' ? '1s' : atoms[i].hybrid?.hybridName ?? '?'
  const bonds: BondAnalysis[] = []
  m.bonds.forEach((b, k) => {
    if (b.a >= m.atoms.length || b.b >= m.atoms.length) return
    const parts = [`σ (${orbital(b.a)} + ${orbital(b.b)})`]
    if (b.order >= 2) {
      const na = atoms[b.a].hybrid ? `${atoms[b.a].hybrid!.shell}p` : 'p', nb = atoms[b.b].hybrid ? `${atoms[b.b].hybrid!.shell}p` : 'p'
      for (let i = 1; i < b.order; i++) parts.push(`π (${na} + ${nb})`)
    }
    bonds.push({ id: k, label: `${labels[b.a]} – ${labels[b.b]}`, detail: parts.join(', ') })
  })
  return { atoms, bonds }
}

export function bondAngles(i: number, m: Molecule, neighbors: number[]): number[] {
  if (neighbors.length < 2) return []
  const c = m.atoms[i]
  const vec = (j: number) => [m.atoms[j].x - c.x, m.atoms[j].y - c.y, m.atoms[j].z - c.z]
  const out: number[] = []
  for (let a = 0; a < neighbors.length; a++) for (let b = a + 1; b < neighbors.length; b++) {
    const u = vec(neighbors[a]), v = vec(neighbors[b])
    const dot = u[0] * v[0] + u[1] * v[1] + u[2] * v[2]
    const lu = Math.hypot(u[0], u[1], u[2]), lv = Math.hypot(v[0], v[1], v[2])
    if (lu > 0 && lv > 0) out.push(Math.acos(Math.max(-1, Math.min(1, dot / (lu * lv)))) * 180 / Math.PI)
  }
  return out
}
