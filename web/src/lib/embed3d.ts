import { elementBySymbol } from './element'
import { Molecule } from './molecule'
import { Sketch, bondLength } from './sketch'
import { Hybridization } from './vbt'

/** Ideal angle (degrees) between two bonds at an atom, from its bonding and lone pairs. */
export function idealAngle(symbol: string, sigma: number, pi: number): number {
  const e = elementBySymbol.get(symbol)
  const h = e ? Hybridization.make(e, sigma, pi) : null
  if (h) {
    const { steric: st, lonePairs: lp } = h
    if (st === 2) return 180
    if (st === 3) return lp === 0 ? 120 : 117
    if (st === 4) return lp === 0 ? 109.5 : lp === 1 ? 107 : 104.5
    if (st === 5) return 105
    if (st === 6) return 90
  }
  switch (sigma) { case 2: return pi >= 2 ? 180 : 109.5; case 3: return 120; default: return 109.5 }
}

type P = { x: number; y: number; z: number }
const cross = (u: P, v: P): P => ({ x: u.y * v.z - u.z * v.y, y: u.z * v.x - u.x * v.z, z: u.x * v.y - u.y * v.x })

/** Turns a 2D sketch into plausible 3D coordinates. Not a force field: it relaxes bond lengths, ideal bond angles
 *  (from valence bond theory) and atom repulsion until the structure settles. */
export function embed3D(sketch: Sketch, name: string): Molecule {
  const s = sketch.addingHydrogens()
  const n = s.atoms.length
  if (n === 0) return { name, atoms: [], bonds: [] }
  const index = new Map(s.atoms.map((a, i) => [a.id, i]))
  const bonds = s.bonds.flatMap(b => { const i = index.get(b.a), j = index.get(b.b); return i != null && j != null ? [{ i, j, order: b.order }] : [] })
  const nbrs: number[][] = s.atoms.map(() => [])
  const pi = s.atoms.map(() => 0)
  for (const b of bonds) { nbrs[b.i].push(b.j); nbrs[b.j].push(b.i); pi[b.i] += b.order - 1; pi[b.j] += b.order - 1 }

  const cov = (i: number) => elementBySymbol.get(s.atoms[i].symbol)?.radiusCovalent ?? 0.8
  const r0 = (b: { i: number; j: number; order: number }) => (cov(b.i) + cov(b.j)) * [1.0, 0.87, 0.78][Math.min(Math.max(b.order, 1), 3) - 1]

  const bondLen: Map<number, number>[] = s.atoms.map(() => new Map())
  for (const b of bonds) { bondLen[b.i].set(b.j, r0(b)); bondLen[b.j].set(b.i, r0(b)) }
  const angleTargets: { i: number; j: number; d: number }[] = []
  const excluded = new Set<number>()
  for (const b of bonds) { excluded.add(b.i * n + b.j); excluded.add(b.j * n + b.i) }
  for (let c = 0; c < n; c++) {
    if (nbrs[c].length < 2) continue
    const theta = idealAngle(s.atoms[c].symbol, nbrs[c].length, pi[c]) * Math.PI / 180
    for (let a = 0; a < nbrs[c].length; a++) for (let b = a + 1; b < nbrs[c].length; b++) {
      const i = nbrs[c][a], j = nbrs[c][b]
      const ra = bondLen[c].get(i) ?? 1.5, rb = bondLen[c].get(j) ?? 1.5
      angleTargets.push({ i, j, d: Math.sqrt(Math.max(0.01, ra * ra + rb * rb - 2 * ra * rb * Math.cos(theta))) })
      excluded.add(i * n + j); excluded.add(j * n + i)
    }
  }

  // Start from the drawing; atoms in π systems stay flat, others get a small deterministic z kick.
  let seed = 12345n
  const rnd = () => { seed = (seed * 6364136223846793005n + 1442695040888963407n) & 0xFFFFFFFFFFFFFFFFn; return Number((seed >> 33n) % 2000n) / 1000 - 1 }
  const scale = 1.5 / bondLength
  const flat = s.atoms.map((_, i) => pi[i] > 0 || nbrs[i].some(j => pi[j] > 0))
  s.atoms.forEach((a, i) => { if (a.symbol === 'H') flat[i] = nbrs[i].length ? pi[nbrs[i][0]] > 0 : false })
  const p: P[] = s.atoms.map((a, i) => ({ x: a.x * scale, y: -a.y * scale, z: flat[i] ? 0 : rnd() * 0.35 }))

  let step = 0.12
  for (let iter = 0; iter < 900; iter++) {
    const g: P[] = p.map(() => ({ x: 0, y: 0, z: 0 }))
    const spring = (i: number, j: number, d0: number, k: number) => {
      const dx = p[i].x - p[j].x, dy = p[i].y - p[j].y, dz = p[i].z - p[j].z
      const d = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy + dz * dz))
      const f = k * (d - d0) / d
      g[i].x += f * dx; g[i].y += f * dy; g[i].z += f * dz
      g[j].x -= f * dx; g[j].y -= f * dy; g[j].z -= f * dz
    }
    for (const b of bonds) spring(b.i, b.j, r0(b), 1.0)
    for (const a of angleTargets) spring(a.i, a.j, a.d, 0.6)
    for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) {
      if (excluded.has(i * n + j)) continue
      const dmin = (s.atoms[i].symbol === 'H' || s.atoms[j].symbol === 'H') ? 2.0 : 2.6
      const dx = p[i].x - p[j].x, dy = p[i].y - p[j].y, dz = p[i].z - p[j].z
      const d = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy + dz * dz))
      if (d < dmin) spring(i, j, dmin, 0.25)
    }
    // keep three-coordinate π centres flat: penalise the volume spanned by their three bonds
    for (let c = 0; c < n; c++) {
      if (!(pi[c] > 0 && nbrs[c].length === 3)) continue
      const [a, b, d] = nbrs[c]
      const rel = (i: number): P => ({ x: p[i].x - p[c].x, y: p[i].y - p[c].y, z: p[i].z - p[c].z })
      const ra = rel(a), rb = rel(b), rd = rel(d)
      const cb = cross(rb, rd)
      const vol = ra.x * cb.x + ra.y * cb.y + ra.z * cb.z
      const k = 0.15 * vol
      for (const [i, grad] of [[a, cb], [b, cross(rd, ra)], [d, cross(ra, rb)]] as [number, P][]) {
        g[i].x += k * grad.x; g[i].y += k * grad.y; g[i].z += k * grad.z
        g[c].x -= k * grad.x; g[c].y -= k * grad.y; g[c].z -= k * grad.z
      }
    }
    if (iter % 150 === 149) step *= 0.7
    for (let i = 0; i < n; i++) { p[i].x -= step * g[i].x; p[i].y -= step * g[i].y; p[i].z -= step * g[i].z }
  }
  const cx = p.reduce((t, q) => t + q.x, 0) / n, cy = p.reduce((t, q) => t + q.y, 0) / n, cz = p.reduce((t, q) => t + q.z, 0) / n
  return {
    name,
    atoms: p.map((q, i) => ({ symbol: s.atoms[i].symbol, x: q.x - cx, y: q.y - cy, z: q.z - cz })),
    bonds: bonds.map(b => ({ a: b.i, b: b.j, order: b.order })),
  }
}
