import { Element, elementBySymbol } from './element'
import { Hybridization } from './vbt'
import { gridPosition } from './element'

export interface ResonanceInput {
  name: string; formula: string
  atoms: { symbol: string; x: number; y: number }[]
  bonds: [number, number][]
  charge: number
}
export interface LewisStructure { orders: number[]; lonePairs: number[]; charges: number[]; cost: number }

const valence = (e: Element) => Hybridization.valenceElectrons(e)

/** All lowest-cost Lewis structures, or null if the electrons cannot be arranged or the molecule is too big. */
export function resonanceStructures(input: ResonanceInput, maxBonds = 9): LewisStructure[] | null {
  const atoms = input.atoms.map(a => elementBySymbol.get(a.symbol)).filter((e): e is Element => !!e)
  if (atoms.length !== input.atoms.length || atoms.some(a => valence(a) == null)) return null
  const n = atoms.length
  const isH = atoms.map(a => a.symbol === 'H')
  const flexible = input.bonds.map((_, i) => i).filter(i => !(isH[input.bonds[i][0]] || isH[input.bonds[i][1]]))
  if (flexible.length > maxBonds) return null
  const totalValence = atoms.reduce((s, a) => s + valence(a)!, 0) - input.charge

  let best = Infinity
  let kept: LewisStructure[] = []
  const combos = Math.max(3 ** flexible.length, 1)
  for (let code = 0; code < combos; code++) {
    const orders = input.bonds.map(() => 1)
    let c = code
    for (const i of flexible) { orders[i] = c % 3 + 1; c = Math.floor(c / 3) }
    const s = Array(n).fill(0)
    input.bonds.forEach((b, i) => { s[b[0]] += orders[i]; s[b[1]] += orders[i] })
    const lpTotal2 = totalValence - s.reduce((a, b) => a + b, 0)
    if (lpTotal2 < 0 || lpTotal2 % 2 !== 0) continue
    const lpTotal = lpTotal2 / 2

    const choices: { lp: number; cost: number }[][] = []
    let feasible = true
    for (let a = 0; a < n; a++) {
      const e = atoms[a], v = valence(e)!, period = gridPosition(e.z).row
      const opts: { lp: number; cost: number }[] = []
      if (isH[a]) { if (s[a] === 1) opts.push({ lp: 0, cost: 0 }) }
      else {
        const maxElectrons = period >= 2 ? 12 : 8
        for (let lp = 0; lp <= 6; lp++) {
          if (2 * lp + 2 * s[a] > maxElectrons) continue
          const fc = v - 2 * lp - s[a], electrons = 2 * lp + 2 * s[a]
          let cost = Math.abs(fc) + 0.05 * fc * (e.electronegativity ?? 2)
          if (electrons < 8) cost += ['B', 'Be', 'Al'].includes(e.symbol) ? 0.2 : 3.0 * Math.floor((8 - electrons) / 2)
          if (electrons > 8) cost += 0.02 * Math.floor((electrons - 8) / 2)
          opts.push({ lp, cost })
        }
      }
      if (!opts.length) { feasible = false; break }
      choices.push(opts)
    }
    if (!feasible) continue

    // distribute exactly lpTotal lone pairs over the atoms at minimum cost
    const dp = Array.from({ length: n + 1 }, () => Array<number>(lpTotal + 1).fill(Infinity))
    const pick = Array.from({ length: n + 1 }, () => Array<number>(lpTotal + 1).fill(-1))
    dp[0][0] = 0
    for (let a = 0; a < n; a++) for (let used = 0; used <= lpTotal; used++) {
      if (!Number.isFinite(dp[a][used])) continue
      choices[a].forEach((o, k) => {
        if (used + o.lp > lpTotal) return
        const v = dp[a][used] + o.cost
        if (v < dp[a + 1][used + o.lp] - 1e-12) { dp[a + 1][used + o.lp] = v; pick[a + 1][used + o.lp] = k }
      })
    }
    const cost = dp[n][lpTotal]
    if (!Number.isFinite(cost) || cost > best + 1e-9) continue
    const lps = Array<number>(n).fill(0); let used = lpTotal
    for (let a = n; a > 0; a--) { const o = choices[a - 1][pick[a][used]]; lps[a - 1] = o.lp; used -= o.lp }
    const charges = atoms.map((e, i) => valence(e)! - 2 * lps[i] - s[i])
    if (cost < best - 1e-9) { best = cost; kept = [] }
    kept.push({ orders, lonePairs: lps, charges, cost })
  }
  return kept.length ? kept : null
}

/** Average bond order over the structures, e.g. 1.33 for each N–O bond in nitrate. */
export const hybridOrders = (ss: LewisStructure[]): number[] =>
  ss.length ? ss[0].orders.map((_, i) => ss.reduce((s, x) => s + x.orders[i], 0) / ss.length) : []
export const averageCharges = (ss: LewisStructure[]): number[] =>
  ss.length ? ss[0].charges.map((_, i) => ss.reduce((s, x) => s + x.charges[i], 0) / ss.length) : []

const ring = (n: number, radius: number, offset = -90): [number, number][] =>
  Array.from({ length: n }, (_, k) => { const t = (offset + k * 360 / n) * Math.PI / 180; return [radius * Math.cos(t), radius * Math.sin(t)] })

function buildPresets(): ResonanceInput[] {
  const a = (symbol: string, p: [number, number]) => ({ symbol, x: p[0], y: p[1] })
  const star = (centre: string, outer: string[], charge: number, name: string, formula: string): ResonanceInput => {
    const pts = ring(outer.length, 1)
    return { name, formula, atoms: [a(centre, [0, 0]), ...outer.map((s, i) => a(s, pts[i]))], bonds: outer.map((_, i) => [0, i + 1] as [number, number]), charge }
  }
  const benz = ring(6, 1), benzH = ring(6, 1.9)
  return [
    { name: 'Ozone', formula: 'O₃', atoms: [a('O', [-1, 0.55]), a('O', [0, 0]), a('O', [1, 0.55])], bonds: [[0, 1], [1, 2]], charge: 0 },
    star('N', ['O', 'O', 'O'], -1, 'Nitrate', 'NO₃⁻'),
    star('C', ['O', 'O', 'O'], -2, 'Carbonate', 'CO₃²⁻'),
    { name: 'Nitrite', formula: 'NO₂⁻', atoms: [a('O', [-1, 0.55]), a('N', [0, 0]), a('O', [1, 0.55])], bonds: [[0, 1], [1, 2]], charge: -1 },
    { name: 'Sulfur dioxide', formula: 'SO₂', atoms: [a('O', [-1, 0.55]), a('S', [0, 0]), a('O', [1, 0.55])], bonds: [[0, 1], [1, 2]], charge: 0 },
    { name: 'Carbon monoxide', formula: 'CO', atoms: [a('C', [-0.6, 0]), a('O', [0.6, 0])], bonds: [[0, 1]], charge: 0 },
    { name: 'Formate', formula: 'HCO₂⁻', atoms: [a('C', [0, 0]), a('O', [-1, 0.8]), a('O', [1, 0.8]), a('H', [0, -1])], bonds: [[0, 1], [0, 2], [0, 3]], charge: -1 },
    { name: 'Acetate', formula: 'CH₃CO₂⁻',
      atoms: [a('C', [0, 0]), a('O', [-1, 0.8]), a('O', [1, 0.8]), a('C', [0, -1.1]), a('H', [-0.9, -1.6]), a('H', [0, -2.1]), a('H', [0.9, -1.6])],
      bonds: [[0, 1], [0, 2], [0, 3], [3, 4], [3, 5], [3, 6]], charge: -1 },
    star('S', ['O', 'O', 'O', 'O'], -2, 'Sulfate', 'SO₄²⁻'),
    { name: 'Benzene', formula: 'C₆H₆', atoms: [...benz.map(p => a('C', p)), ...benzH.map(p => a('H', p))],
      bonds: [...Array.from({ length: 6 }, (_, i) => [i, (i + 1) % 6] as [number, number]), ...Array.from({ length: 6 }, (_, i) => [i, i + 6] as [number, number])], charge: 0 },
    { name: 'Ammonium', formula: 'NH₄⁺', atoms: [a('N', [0, 0]), ...ring(4, 1).map(p => a('H', p))], bonds: [[0, 1], [0, 2], [0, 3], [0, 4]], charge: 1 },
    { name: 'Hydronium', formula: 'H₃O⁺', atoms: [a('O', [0, 0]), ...ring(3, 1).map(p => a('H', p))], bonds: [[0, 1], [0, 2], [0, 3]], charge: 1 },
  ]
}
export const resonancePresets = buildPresets()
