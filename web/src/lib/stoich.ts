import { Balanced } from './solver'
import { formatNumber } from './format'

export interface Species { id: number; formula: string; coefficient: number; molarMass: number; isReactant: boolean }
export interface Line { species: Species; moles: number; grams: number; note: string }
export interface Outcome { limiting: Species | null; reactants: Line[]; excess: Line[]; products: Line[]; steps: string[] }
export type QUnit = 'g' | 'mg' | 'kg' | 'mol' | 'mmol'
export const qunits: QUnit[] = ['g', 'mg', 'kg', 'mol', 'mmol']

export function toMoles(u: QUnit, v: number, m: number): number {
  switch (u) { case 'g': return v / m; case 'mg': return v / 1000 / m; case 'kg': return v * 1000 / m; case 'mol': return v; case 'mmol': return v / 1000 }
}

export function speciesFrom(b: Balanced, mass: (sym: string) => number | undefined): Species[] {
  return [...b.left, ...b.right].map((e, i) => {
    let m = 0; for (const [sym, n] of e.term.atoms) m += (mass(sym) ?? 0) * n
    return { id: i, formula: e.term.text, coefficient: e.coefficient, molarMass: m, isReactant: i < b.left.length }
  })
}

/** `amounts` maps species id → [value, unit] for reactants. Reactants left out are assumed to be in excess. */
export function solveStoich(all: Species[], amounts: Map<number, [number, QUnit]>): Outcome | null {
  const reactants = all.filter(s => s.isReactant), products = all.filter(s => !s.isReactant)
  const ratios: [Species, number, number][] = []
  const steps: string[] = []
  const fmt = formatNumber
  for (const r of reactants) {
    const a = amounts.get(r.id)
    if (!a || !(a[0] > 0) || !(r.molarMass > 0)) continue
    const [v, u] = a
    const n = toMoles(u, v, r.molarMass)
    ratios.push([r, n, n / r.coefficient])
    if (u === 'mol' || u === 'mmol') steps.push(`${r.formula}: ${fmt(v)} ${u} = ${fmt(n)} mol; ${fmt(n)} ÷ ${r.coefficient} = ${fmt(n / r.coefficient)}`)
    else steps.push(`${r.formula}: ${fmt(v)} ${u} ÷ ${fmt(r.molarMass)} g/mol = ${fmt(n)} mol; ÷ ${r.coefficient} = ${fmt(n / r.coefficient)}`)
  }
  if (!ratios.length) return null
  const limit = ratios.reduce((a, b) => (b[2] < a[2] ? b : a))
  const extent = limit[2]
  steps.push(`Limiting reagent: ${limit[0].formula} (smallest moles ÷ coefficient = ${fmt(extent)})`)
  const line = (s: Species, n: number, note: string): Line => ({ species: s, moles: n, grams: n * s.molarMass, note })
  const used = ratios.map(r => line(r[0], extent * r[0].coefficient, 'consumed'))
  const excess = ratios.filter(r => r[0].id !== limit[0].id).map(r => line(r[0], r[1] - extent * r[0].coefficient, 'left over'))
  const prod = products.map(p => line(p, extent * p.coefficient, 'theoretical'))
  for (const p of prod) steps.push(`${p.species.formula}: ${fmt(extent)} × ${p.species.coefficient} = ${fmt(p.moles)} mol × ${fmt(p.species.molarMass)} g/mol = ${fmt(p.grams)} g`)
  return { limiting: limit[0], reactants: used, excess, products: prod, steps }
}
