import { Molecule } from './molecule'
import { analyzeMolecule, AtomAnalysis, Hybridization } from './vbt'
import { V3, add, sub, scale, normalize, cross, dot, len, perpendicularTo, hybridKindNamed } from './orbitals'

/** Works out where each atom's orbitals point: σ lobes toward bonded atoms, lone pairs in the remaining space, and π p axes. */
export interface Lobe { atom: number; direction: V3; hybrid: string }
export interface PiBond { a: number; b: number; axis: V3 }
export interface OrbitalResult { sigma: Lobe[]; lonePairs: Lobe[]; pi: PiBond[]; hydrogens: number[] }

export function analyzeOrbitals(m: Molecule): OrbitalResult {
  const info = analyzeMolecule(m).atoms
  const pos = (i: number): V3 => [m.atoms[i].x, m.atoms[i].y, m.atoms[i].z]
  const dir = (i: number, j: number) => normalize(sub(pos(j), pos(i)))
  const res: OrbitalResult = { sigma: [], lonePairs: [], pi: [], hydrogens: [] }
  const piAxes = new Map<number, V3[]>()
  const sp2Doubles = new Map<number, number>()
  const pushAxes = (i: number, ax: V3) => piAxes.set(i, [...(piAxes.get(i) ?? []), ax])

  for (const b of m.bonds) {
    if (b.order < 2 || b.a >= m.atoms.length || b.b >= m.atoms.length) continue
    const ha = info[b.a].hybrid, hb = info[b.b].hybrid
    if (ha?.hybridName == null && hb?.hybridName == null) continue
    const spAtom = ha?.steric === 2 ? b.a : hb?.steric === 2 ? b.b : null
    let axes: V3[]
    if (spAtom != null) {
      const other = spAtom === b.a ? b.b : b.a
      const u = dir(spAtom, other)
      const a1 = perpendicularTo(u), a2 = normalize(cross(u, a1))
      if (b.order >= 3) axes = [a1, a2]
      else { const k = sp2Doubles.get(spAtom) ?? 0; sp2Doubles.set(spAtom, k + 1); axes = [k % 2 === 0 ? a1 : a2] }
    } else {
      axes = [planeNormal(info[b.a].neighbors.length >= info[b.b].neighbors.length ? b.a : b.b, info, pos)]
      if (b.order === 3) axes.push(normalize(cross(dir(b.a, b.b), axes[0])))
    }
    for (const ax of axes) { res.pi.push({ a: b.a, b: b.b, axis: ax }); pushAxes(b.a, ax); pushAxes(b.b, ax) }
  }

  info.forEach((a, i) => {
    if (a.element?.symbol === 'H') { res.hydrogens.push(i); return }
    const h = a.hybrid, name = h?.hybridName
    if (!h || !name) return
    const nb = a.neighbors.map(j => dir(i, j))
    for (const u of nb) res.sigma.push({ atom: i, direction: u, hybrid: name })
    for (const u of lonePairDirections(h, nb, piAxes.get(i)?.[0] ?? null)) res.lonePairs.push({ atom: i, direction: u, hybrid: name })
  })
  return res
}

/** Normal of the plane an sp² atom sits in. */
export function planeNormal(i: number, info: AtomAnalysis[], pos: (i: number) => V3): V3 {
  const normal = (c: number, nbrs: number[]): V3 | null => {
    if (nbrs.length < 2) return null
    const n = cross(sub(pos(nbrs[0]), pos(c)), sub(pos(nbrs[1]), pos(c)))
    return len(n) > 1e-3 ? normalize(n) : null
  }
  const n = normal(i, info[i].neighbors); if (n) return n
  const first = info[i].neighbors[0]
  if (first !== undefined) { const n2 = normal(first, info[first].neighbors); return n2 ?? perpendicularTo(sub(pos(first), pos(i))) }
  return [0, 0, 1]
}

/** Directions of an atom's lone pairs from its bonds (VSEPR positions). */
export function lonePairDirections(h: Hybridization, nb: V3[], piAxis: V3 | null): V3[] {
  const lp = h.lonePairs
  if (lp <= 0) return []
  const sum = () => nb.reduce((s, v) => add(s, v), [0, 0, 0] as V3)
  const neg = (v: V3): V3 => [-v[0], -v[1], -v[2]]
  const key = `${h.steric},${nb.length}`
  switch (key) {
    case '2,1': return [neg(nb[0])]
    case '3,2': return [neg(normalize(sum()))]
    case '3,1': {
      const ax = piAxis ?? perpendicularTo(nb[0])
      const t = normalize(cross(ax, nb[0])), c = Math.cos(2 * Math.PI / 3), s = Math.sin(2 * Math.PI / 3)
      return [add(scale(nb[0], c), scale(t, s)), sub(scale(nb[0], c), scale(t, s))]
    }
    case '4,3': return [neg(normalize(sum()))]
    case '4,2': {
      const b = normalize(add(nb[0], nb[1])), n = normalize(cross(nb[0], nb[1])), phi = 54.75 * Math.PI / 180
      return [add(scale(b, -Math.cos(phi)), scale(n, Math.sin(phi))), sub(scale(b, -Math.cos(phi)), scale(n, Math.sin(phi)))]
    }
    case '4,1': {
      const p1 = perpendicularTo(nb[0]), p2 = normalize(cross(nb[0], p1)), th = 109.5 * Math.PI / 180
      return [0, 1, 2].map(k => { const a = k * 2 * Math.PI / 3; return add(scale(nb[0], Math.cos(th)), scale(add(scale(p1, Math.cos(a)), scale(p2, Math.sin(a))), Math.sin(th))) })
    }
    default: return farthestDirections(lp, nb)
  }
}

/** Fallback for crowded atoms (sp³d, sp³d²): pick directions as far from everything else as possible. */
export function farthestDirections(count: number, fixed: V3[]): V3[] {
  const n = 200, golden = Math.PI * (3 - Math.sqrt(5))
  const cands: V3[] = Array.from({ length: n }, (_, i) => { const y = 1 - 2 * (i + 0.5) / n, r = Math.sqrt(1 - y * y), t = golden * i; return [r * Math.cos(t), y, r * Math.sin(t)] })
  const chosen = [...fixed]; const out: V3[] = []
  const closeness = (v: V3) => chosen.length ? Math.max(...chosen.map(c => dot(v, c))) : -1
  for (let k = 0; k < count; k++) {
    let best = cands[0], bestV = Infinity
    for (const c of cands) { const v = closeness(c); if (v < bestV) { bestV = v; best = c } }
    out.push(best); chosen.push(best)
  }
  return out
}

export type OverlayMode = 'Off' | 'σ bonds & lone pairs' | 'σ, lone pairs & π'
export const overlayModes: OverlayMode[] = ['Off', 'σ bonds & lone pairs', 'σ, lone pairs & π']

/** Which orbital shapes to draw, honouring a per-atom filter (empty/null = all atoms). */
export interface OverlayItem { kind: 'sigma' | 'lone' | 'pi' | 's'; atom: number; direction?: V3; hybrid?: string }
export function overlayItems(m: Molecule, mode: OverlayMode, atoms: Set<number> | null = null): OverlayItem[] {
  if (mode === 'Off') return []
  const res = analyzeOrbitals(m)
  if (atoms && atoms.size) {
    const near = new Set(atoms)
    for (const b of m.bonds) if (atoms.has(b.a) || atoms.has(b.b)) { near.add(b.a); near.add(b.b) }
    res.sigma = res.sigma.filter(l => atoms.has(l.atom))
    res.lonePairs = res.lonePairs.filter(l => atoms.has(l.atom))
    res.pi = res.pi.filter(p => atoms.has(p.a) || atoms.has(p.b))
    res.hydrogens = res.hydrogens.filter(h => near.has(h))
  }
  const out: OverlayItem[] = []
  for (const l of res.sigma) if (hybridKindNamed(l.hybrid)) out.push({ kind: 'sigma', atom: l.atom, direction: l.direction, hybrid: l.hybrid })
  for (const l of res.lonePairs) if (hybridKindNamed(l.hybrid)) out.push({ kind: 'lone', atom: l.atom, direction: l.direction, hybrid: l.hybrid })
  for (const h of res.hydrogens) out.push({ kind: 's', atom: h })
  if (mode === 'σ, lone pairs & π') for (const b of res.pi) for (const atom of [b.a, b.b]) out.push({ kind: 'pi', atom, direction: b.axis })
  return out
}
