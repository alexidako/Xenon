import { Unit, Units, toBase, fromBase } from './format'
import { Expr, parseExpr, evalExpr } from './expr'

// MARK: gas (van der Waals; a = b = 0 is the ideal gas law)
export const R_GAS = 0.082057366   // L·atm/(mol·K)
export type GasSolve = 'Volume' | 'Pressure' | 'Temperature' | 'Amount'
export interface GasInput { P: number; V: number; T: number; n: number; a: number; b: number }   // base units: atm, L, K, mol, L²atm/mol², L/mol

function newton(f: (x: number) => number, x0: number): number | null {
  let x = x0
  for (let i = 0; i < 80; i++) {
    const h = Math.max(Math.abs(x) * 1e-6, 1e-9), fx = f(x), d = (f(x + h) - f(x - h)) / (2 * h)
    if (d === 0 || !Number.isFinite(d)) return null
    const nx = x - fx / d
    if (Math.abs(nx - x) < 1e-12 * Math.max(1, Math.abs(x))) return nx
    x = nx
  }
  return x
}
export function solveGas(solve: GasSolve, g: GasInput): number | null {
  const { P, V, T, n, a, b } = g
  switch (solve) {
    case 'Pressure': return V - n * b > 0 ? n * R_GAS * T / (V - n * b) - a * n * n / (V * V) : null
    case 'Temperature': return n > 0 ? (P + a * n * n / (V * V)) * (V - n * b) / (n * R_GAS) : null
    case 'Volume': return P > 0 ? newton(v => (P + a * n * n / (v * v)) * (v - n * b) - n * R_GAS * T, n * R_GAS * T / P + n * b) : null
    case 'Amount': return T > 0 ? newton(m => (P + a * m * m / (V * V)) * (V - m * b) - m * R_GAS * T, P * V / (R_GAS * T)) : null
  }
}

// MARK: concentration
export type SoluteKind = 'Mass (g)' | 'Volume (L)' | 'Moles'
export type SolventKind = 'Volume (L)' | 'Mass (g)' | 'Moles'
export const concKinds = ['Molarity (mol/L)', 'Normality (eq/L)', 'Molality (mol/kg)', '% (mass)', '% (volume)', '% (moles)'] as const
export type ConcKind = typeof concKinds[number]
export interface Solution { molarMass: number; eqMass: number; soluteDensity: number; solventKind: SolventKind; solventAmount: number; solventMolarMass: number; solventDensity: number }

export function solventMass(s: Solution) {
  switch (s.solventKind) { case 'Mass (g)': return s.solventAmount; case 'Volume (L)': return s.solventAmount * s.solventDensity * 1000; case 'Moles': return s.solventAmount * s.solventMolarMass }
}
export function soluteMassFrom(v: number, kind: SoluteKind, s: Solution) {
  switch (kind) { case 'Mass (g)': return v; case 'Volume (L)': return v * 1000 * s.soluteDensity; case 'Moles': return v * s.molarMass }
}
export function concentrations(soluteG: number, s: Solution): [ConcKind, number][] {
  const sm = solventMass(s), sv = sm / (s.solventDensity * 1000), smol = sm / s.solventMolarMass
  const mol = soluteG / s.molarMass, eq = soluteG / s.eqMass, vol = soluteG / (s.soluteDensity * 1000)
  return [['Molarity (mol/L)', mol / sv], ['Normality (eq/L)', eq / sv], ['Molality (mol/kg)', mol * 1000 / sm], ['% (mass)', soluteG / (soluteG + sm) * 100],
    ['% (volume)', vol / (vol + sv) * 100], ['% (moles)', mol / (mol + smol) * 100]]
}
/** Grams of solute that give the target concentration with the given solvent. */
export function requiredSolute(kind: ConcKind, c: number, s: Solution): number | null {
  const sm = solventMass(s), sv = sm / (s.solventDensity * 1000), smol = sm / s.solventMolarMass
  switch (kind) {
    case 'Molarity (mol/L)': return c * sv * s.molarMass
    case 'Normality (eq/L)': return c * sv * s.eqMass
    case 'Molality (mol/kg)': return c * sm / 1000 * s.molarMass
    case '% (mass)': return c < 100 ? c / (100 - c) * sm : null
    case '% (volume)': return c < 100 ? c / (100 - c) * sv * s.soluteDensity * 1000 : null
    case '% (moles)': return c < 100 ? c / (100 - c) * smol * s.molarMass : null
  }
}

// MARK: nuclear decay N = N0 · 2^(−t/T½)
export type DecaySolve = 'Final amount' | 'Initial amount' | 'Time'
/** All amounts in grams, times in seconds. */
export function solveDecay(solve: DecaySolve, halfLife: number, initial: number, final: number, t: number): number | null {
  if (!(halfLife > 0)) return null
  switch (solve) {
    case 'Final amount': return initial / Math.pow(2, t / halfLife)
    case 'Initial amount': return final * Math.pow(2, t / halfLife)
    case 'Time': return initial > 0 && final > 0 && final <= initial ? Math.log2(initial / final) * halfLife : null
  }
}
/** The largest time unit in which `seconds` is at least 1. */
export function bestTimeUnit(seconds: number): number { const i = Units.time.findIndex(u => seconds >= u.factor); return i < 0 ? Units.time.length - 1 : i }

// MARK: titration
export interface Fit { a: number; b: number; c: number; d: number; equivalence: number }
export function fitTitration(pts: { x: number; y: number }[]): Fit | null {
  if (pts.length < 3) return null
  const first = pts[0], last = pts[pts.length - 1]
  if (last.x === first.x) return null
  const a = last.y - first.y; if (a === 0) return null
  const b = 4 / (last.x - first.x), d = a > 0 ? first.y + a / 2 : last.y - a / 2
  let sum = 0, count = 0
  for (const p of pts.slice(1, -1)) {
    const r = (p.y - d) / a; if (Math.abs(r) >= 1) continue
    const ci = 0.5 * Math.log((1 + r) / (1 - r)) / b - p.x
    if (Number.isFinite(ci)) { sum += ci; count++ }
  }
  if (!count) return null
  const c = sum / count
  return { a, b, c, d, equivalence: -c }
}
export function theoryCurve(equations: { name: string; text: string }[], xVar: string, yVar: string, xMin: number, xMax: number): { samples: { x: number; y: number }[]; formula: string } | null {
  if (!xVar || !yVar) return null
  const table = new Map<string, string>(); for (const e of equations) if (e.name && e.text && !table.has(e.name)) table.set(e.name, e.text)
  if (!table.has(yVar)) return null
  const parsed = new Map<string, Expr>()
  for (const [k, v] of table) { const e = parseExpr(v); if (!e) return null; parsed.set(k, e) }
  const value = (name: string, x: number, depth: number): number => {
    if (name === xVar) return x
    if (depth >= 50) throw new Error('too deep')
    const e = parsed.get(name); if (!e) throw new Error('unknown ' + name)
    return evalExpr(e, n => value(n, x, depth + 1))
  }
  const out: { x: number; y: number }[] = []
  for (let i = 0; i <= 240; i++) { const x = xMin + (xMax - xMin) * i / 240; try { const y = value(yVar, x, 0); if (Number.isFinite(y)) out.push({ x, y }) } catch { /* skip */ } }
  return out.length ? { samples: out, formula: `${yVar} = ${table.get(yVar)}` } : null
}
export { Units, toBase, fromBase }
export type { Unit }
