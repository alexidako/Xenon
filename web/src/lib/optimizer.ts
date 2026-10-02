import { elementBySymbol } from './element'
import { Molecule } from './molecule'
import { Hybridization } from './vbt'
import { idealAngle } from './embed3d'
import { RNG } from './quiz'

/** Finds the lowest-energy 3D shape of a molecule with a small molecular-mechanics force field.
 *
 *  Energy terms (kcal/mol, Å, radians): bond stretching, bond-angle bending toward the VSEPR/valence-bond ideal, torsion
 *  (staggered sp³–sp³, flat double bonds and conjugated bonds), out-of-plane bending for flat sp² centres and Lennard-Jones
 *  repulsion/attraction between atoms three or more bonds apart. A simple classical model, not quantum chemistry.
 *
 *  "Most stable" is a search: many starting shapes (every rotatable bond spun, rings puckered or shaken) are each relaxed
 *  to a minimum, and the lowest wins. */
export interface OptimizeResult { molecule: Molecule; energyBefore: number; energyAfter: number; starts: number; rotors: number }

interface Bond { i: number; j: number; r0: number }
interface Angle { i: number; j: number; k: number; cos0: number; linear: boolean; ka: number }
interface Torsion { i: number; j: number; k: number; l: number; v: number; n: number; phase: number }   // E = ½V(1 + cos(nφ − phase))
interface Planar { c: number; a: number; b: number; d: number }
interface Pair { i: number; j: number; r: number; eps: number }

const kBond = 600, kPlanar = 40
const EPS: Record<string, number> = { H: 0.044, C: 0.105, N: 0.069, O: 0.060, F: 0.050, S: 0.274, Cl: 0.227, P: 0.305, Br: 0.251, I: 0.339 }

export class Field {
  n: number
  bonds: Bond[] = []; angles: Angle[] = []; torsions: Torsion[] = []; planars: Planar[] = []; pairs: Pair[] = []
  neighbors: number[][] = []; rotors: [number, number][] = []; rings: number[][] = []

  constructor(m: Molecule) {
    const n = this.n = m.atoms.length
    this.neighbors = m.atoms.map(() => [])
    const order: Map<number, number>[] = m.atoms.map(() => new Map())
    for (const b of m.bonds) {
      if (b.a >= n || b.b >= n || b.a === b.b || order[b.a].has(b.b)) continue
      this.neighbors[b.a].push(b.b); this.neighbors[b.b].push(b.a); order[b.a].set(b.b, b.order); order[b.b].set(b.a, b.order)
    }
    const nb = this.neighbors
    const pi = order.map(o => [...o.values()].reduce((s, v) => s + v - 1, 0))
    const sym = (i: number) => m.atoms[i].symbol
    const cov = (i: number) => elementBySymbol.get(sym(i))?.radiusCovalent ?? 0.8

    const aromatic = aromaticBonds(nb, order, n)
    for (let i = 0; i < n; i++) for (const j of nb[i]) {
      if (j <= i) continue
      const o = order[i].get(j) ?? 1
      let factor = [1.0, 0.87, 0.78][Math.min(Math.max(o, 1), 3) - 1]
      if (aromatic.has(i * n + j)) factor = 0.91
      else if (o === 1 && pi[i] > 0 && pi[j] > 0 && [...order[i].values()].some(v => v >= 2) && [...order[j].values()].some(v => v >= 2)) factor = 0.955
      this.bonds.push({ i, j, r0: (cov(i) + cov(j)) * factor })
    }

    const steric = m.atoms.map((a, i) => {
      const e = elementBySymbol.get(a.symbol), h = e ? Hybridization.makeAllowingCharge(e, nb[i].length, pi[i]) : null
      if (h && h.hybridName != null) return h.steric
      return pi[i] >= 2 ? 2 : pi[i] === 1 ? 3 : Math.max(2, Math.min(4, nb[i].length))
    })

    for (let c = 0; c < n; c++) {
      if (nb[c].length < 2) continue
      const deg = idealAngle(sym(c), nb[c].length, pi[c]) * Math.PI / 180
      for (let a = 0; a < nb[c].length; a++) for (let b = a + 1; b < nb[c].length; b++) {
        const ka = (sym(nb[c][a]) === 'H' || sym(nb[c][b]) === 'H') ? 60 : 90
        this.angles.push({ i: nb[c][a], j: c, k: nb[c][b], cos0: Math.cos(deg), linear: deg > 3.0, ka })
      }
      if (nb[c].length === 3 && (pi[c] > 0 || steric[c] === 3)) this.planars.push({ c, a: nb[c][0], b: nb[c][1], d: nb[c][2] })
    }

    for (const b of this.bonds) {
      const j = b.i, k = b.j
      const left = nb[j].filter(x => x !== k), right = nb[k].filter(x => x !== j)
      if (!left.length || !right.length) continue
      const o = order[j].get(k) ?? 1, count = left.length * right.length, sj = steric[j], sk = steric[k]
      for (const i of left) for (const l of right) {
        if (o >= 2) this.torsions.push({ i, j, k, l, v: 40, n: 2, phase: Math.PI })
        else if (sj === 3 && sk === 3) this.torsions.push({ i, j, k, l, v: 8, n: 2, phase: Math.PI })
        else if (sj <= 3 && sk <= 3) continue
        else if (sj === 4 && sk === 4) {
          const s = new Set([sym(j), sym(k)])
          const barrier = s.size === 1 && s.has('C') ? 2.9 : s.has('O') ? 1.1 : 2.0
          this.torsions.push({ i, j, k, l, v: barrier / count, n: 3, phase: 0 })
        } else this.torsions.push({ i, j, k, l, v: 1.0 / count, n: 3, phase: Math.PI })
      }
    }

    const near: Set<number>[] = m.atoms.map(() => new Set()), oneFour = new Set<number>()
    for (let i = 0; i < n; i++) for (const j of nb[i]) { near[i].add(j); for (const k of nb[j]) if (k !== i) near[i].add(k) }
    for (let i = 0; i < n; i++) for (const j of nb[i]) for (const k of nb[j]) { if (k === i) continue; for (const l of nb[k]) if (l !== j && l !== i && !near[i].has(l)) oneFour.add(Math.min(i, l) * n + Math.max(i, l)) }
    const rv = (s: string) => Math.min(2.2, elementBySymbol.get(s)?.radiusVDW ?? 1.7)
    for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) {
      if (near[i].has(j)) continue
      const scale = oneFour.has(i * n + j) ? 0.5 : 1
      this.pairs.push({ i, j, r: rv(sym(i)) + rv(sym(j)), eps: scale * Math.sqrt((EPS[sym(i)] ?? 0.1) * (EPS[sym(j)] ?? 0.1)) })
    }

    this.rings = findRings(nb, n)
    for (const b of this.bonds) {
      if ((order[b.i].get(b.j) ?? 1) !== 1 || nb[b.i].length < 2 || nb[b.j].length < 2) continue
      if (reachable(b.i, b.j, [b.i, b.j], nb)) continue           // ring bond
      if (steric[b.i] === 2 || steric[b.j] === 2) continue         // linear centre
      this.rotors.push([b.i, b.j])
    }
  }

  /** Atoms on `b`'s side of the bond a–b. */
  side(b: number, a: number): number[] {
    const seen = new Set([a, b]), stack = [b], out = [b]
    for (let x = stack.pop(); x !== undefined; x = stack.pop()) for (const y of this.neighbors[x]) if (!seen.has(y)) { seen.add(y); stack.push(y); out.push(y) }
    return out
  }

  energy(x: number[], g?: number[]): number {
    const grad = g ?? new Array(x.length).fill(0)
    grad.fill(0)
    let e = 0
    const add = (i: number, dx: number, dy: number, dz: number) => { grad[3 * i] += dx; grad[3 * i + 1] += dy; grad[3 * i + 2] += dz }

    for (const b of this.bonds) {
      const dx = x[3 * b.i] - x[3 * b.j], dy = x[3 * b.i + 1] - x[3 * b.j + 1], dz = x[3 * b.i + 2] - x[3 * b.j + 2]
      const r = Math.max(1e-9, Math.sqrt(dx * dx + dy * dy + dz * dz))
      e += 0.5 * kBond * (r - b.r0) ** 2
      const f = kBond * (r - b.r0) / r
      add(b.i, f * dx, f * dy, f * dz); add(b.j, -f * dx, -f * dy, -f * dz)
    }
    for (const a of this.angles) {
      const ux = x[3 * a.i] - x[3 * a.j], uy = x[3 * a.i + 1] - x[3 * a.j + 1], uz = x[3 * a.i + 2] - x[3 * a.j + 2]
      const vx = x[3 * a.k] - x[3 * a.j], vy = x[3 * a.k + 1] - x[3 * a.j + 1], vz = x[3 * a.k + 2] - x[3 * a.j + 2]
      const lu = Math.max(1e-9, Math.hypot(ux, uy, uz)), lv = Math.max(1e-9, Math.hypot(vx, vy, vz))
      const c = Math.max(-1, Math.min(1, (ux * vx + uy * vy + uz * vz) / (lu * lv)))
      let dEdc: number
      if (a.linear) { e += a.ka * (1 + c); dEdc = a.ka }
      else { const s2 = Math.max(0.05, 1 - a.cos0 * a.cos0); e += 0.5 * a.ka * (c - a.cos0) ** 2 / s2; dEdc = a.ka * (c - a.cos0) / s2 }
      const gix = dEdc * (vx / (lu * lv) - c * ux / (lu * lu)), giy = dEdc * (vy / (lu * lv) - c * uy / (lu * lu)), giz = dEdc * (vz / (lu * lv) - c * uz / (lu * lu))
      const gkx = dEdc * (ux / (lu * lv) - c * vx / (lv * lv)), gky = dEdc * (uy / (lu * lv) - c * vy / (lv * lv)), gkz = dEdc * (uz / (lu * lv) - c * vz / (lv * lv))
      add(a.i, gix, giy, giz); add(a.k, gkx, gky, gkz); add(a.j, -gix - gkx, -giy - gky, -giz - gkz)
    }
    for (const t of this.torsions) {
      const fx = x[3 * t.i] - x[3 * t.j], fy = x[3 * t.i + 1] - x[3 * t.j + 1], fz = x[3 * t.i + 2] - x[3 * t.j + 2]
      const gx = x[3 * t.j] - x[3 * t.k], gy = x[3 * t.j + 1] - x[3 * t.k + 1], gz = x[3 * t.j + 2] - x[3 * t.k + 2]
      const hx = x[3 * t.l] - x[3 * t.k], hy = x[3 * t.l + 1] - x[3 * t.k + 1], hz = x[3 * t.l + 2] - x[3 * t.k + 2]
      const ax = fy * gz - fz * gy, ay = fz * gx - fx * gz, az = fx * gy - fy * gx
      const bx = hy * gz - hz * gy, by = hz * gx - hx * gz, bz = hx * gy - hy * gx
      const a2 = ax * ax + ay * ay + az * az, b2 = bx * bx + by * by + bz * bz, lg = Math.hypot(gx, gy, gz)
      if (!(a2 > 1e-10 && b2 > 1e-10 && lg > 1e-6)) continue
      const cosphi = (ax * bx + ay * by + az * bz) / Math.sqrt(a2 * b2)
      const cx = ay * bz - az * by, cy = az * bx - ax * bz, cz = ax * by - ay * bx
      const sinphi = (cx * gx + cy * gy + cz * gz) / (Math.sqrt(a2 * b2) * lg)
      const phi = Math.atan2(sinphi, cosphi)
      e += 0.5 * t.v * (1 + Math.cos(t.n * phi - t.phase))
      const dEdphi = 0.5 * t.v * t.n * Math.sin(t.n * phi - t.phase)
      const fg = fx * gx + fy * gy + fz * gz, hg = hx * gx + hy * gy + hz * gz
      const dix = -lg / a2 * ax, diy = -lg / a2 * ay, diz = -lg / a2 * az, dlx = lg / b2 * bx, dly = lg / b2 * by, dlz = lg / b2 * bz
      const sA = fg / (a2 * lg), sB = hg / (b2 * lg)
      const djx = -dix + sA * ax - sB * bx, djy = -diy + sA * ay - sB * by, djz = -diz + sA * az - sB * bz
      const dkx = -dlx - sA * ax + sB * bx, dky = -dly - sA * ay + sB * by, dkz = -dlz - sA * az + sB * bz
      add(t.i, dEdphi * dix, dEdphi * diy, dEdphi * diz); add(t.j, dEdphi * djx, dEdphi * djy, dEdphi * djz)
      add(t.k, dEdphi * dkx, dEdphi * dky, dEdphi * dkz); add(t.l, dEdphi * dlx, dEdphi * dly, dEdphi * dlz)
    }
    for (const pl of this.planars) {
      const cx = x[3 * pl.c], cy = x[3 * pl.c + 1], cz = x[3 * pl.c + 2]
      const ra = [x[3 * pl.a] - cx, x[3 * pl.a + 1] - cy, x[3 * pl.a + 2] - cz], rb = [x[3 * pl.b] - cx, x[3 * pl.b + 1] - cy, x[3 * pl.b + 2] - cz], rd = [x[3 * pl.d] - cx, x[3 * pl.d + 1] - cy, x[3 * pl.d + 2] - cz]
      const cross = (u: number[], v: number[]) => [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
      const cbd = cross(rb, rd), cda = cross(rd, ra), cab = cross(ra, rb)
      const vol = ra[0] * cbd[0] + ra[1] * cbd[1] + ra[2] * cbd[2]
      e += 0.5 * kPlanar * vol * vol
      const k = kPlanar * vol
      add(pl.a, k * cbd[0], k * cbd[1], k * cbd[2]); add(pl.b, k * cda[0], k * cda[1], k * cda[2]); add(pl.d, k * cab[0], k * cab[1], k * cab[2])
      add(pl.c, -k * (cbd[0] + cda[0] + cab[0]), -k * (cbd[1] + cda[1] + cab[1]), -k * (cbd[2] + cda[2] + cab[2]))
    }
    for (const q of this.pairs) {
      const dx = x[3 * q.i] - x[3 * q.j], dy = x[3 * q.i + 1] - x[3 * q.j + 1], dz = x[3 * q.i + 2] - x[3 * q.j + 2]
      const r2 = Math.max(0.25, dx * dx + dy * dy + dz * dz)       // soft core
      const s2 = q.r * q.r / r2, s6 = s2 * s2 * s2
      e += q.eps * (s6 * s6 - 2 * s6)
      const f = q.eps * 12 * (s6 - s6 * s6) / r2
      add(q.i, f * dx, f * dy, f * dz); add(q.j, -f * dx, -f * dy, -f * dz)
    }
    return e
  }
}

/** Simple rings of 4 to 7 atoms, each listed once in cycle order. */
export function findRings(nb: number[][], n: number): number[][] {
  const seen = new Set<string>(), out: number[][] = []
  const extend = (path: number[]) => {
    if (path.length >= 4 && nb[path[path.length - 1]].includes(path[0])) { const key = [...path].sort((a, b) => a - b).join(','); if (!seen.has(key)) { seen.add(key); out.push(path) } }
    if (path.length >= 7) return
    for (const y of nb[path[path.length - 1]]) if (y > path[0] && !path.includes(y)) extend([...path, y])
  }
  for (let s = 0; s < n; s++) if (nb[s].length >= 2) extend([s])
  return out
}
/** Bonds (i·n+j, i<j) of six-membered rings whose bonds alternate single/double: the Kekulé drawing of an aromatic ring. */
function aromaticBonds(nb: number[][], order: Map<number, number>[], n: number): Set<number> {
  const out = new Set<number>()
  const extend = (path: number[]) => {
    if (path.length === 6) {
      if (!nb[path[5]].includes(path[0])) return
      const o = path.map((_, k) => order[path[k]].get(path[(k + 1) % 6]) ?? 1).join('')
      if (o === '121212' || o === '212121') for (let k = 0; k < 6; k++) { const a = path[k], b = path[(k + 1) % 6]; out.add(Math.min(a, b) * n + Math.max(a, b)) }
      return
    }
    for (const y of nb[path[path.length - 1]]) if (y > path[0] && !path.includes(y)) extend([...path, y])
  }
  for (let s = 0; s < n; s++) if (nb[s].length >= 2) extend([s])
  return out
}
function reachable(s: number, t: number, e: [number, number], nb: number[][]): boolean {
  const seen = new Set([s]), stack = [s]
  for (let x = stack.pop(); x !== undefined; x = stack.pop()) for (const y of nb[x]) {
    if ((x === e[0] && y === e[1]) || (x === e[1] && y === e[0])) continue
    if (y === t) return true
    if (!seen.has(y)) { seen.add(y); stack.push(y) }
  }
  return false
}

/** FIRE minimiser. */
export function minimize(field: Field, start: number[], maxIterations = 4000, tolerance = 0.02): { x: number[]; energy: number } {
  const x = start.slice(), g = new Array(x.length).fill(0), v = new Array(x.length).fill(0)
  let dt = 0.01, alpha = 0.1, sinceNegative = 0
  const dtMax = 0.03, maxStep = 0.08
  let e = field.energy(x, g)
  for (let it = 0; it < maxIterations; it++) {
    let gmax = 0; for (const q of g) gmax = Math.max(gmax, Math.abs(q))
    if (gmax < tolerance) break
    let power = 0, vn = 0, gn = 0
    for (let i = 0; i < x.length; i++) { power -= g[i] * v[i]; vn += v[i] * v[i]; gn += g[i] * g[i] }
    vn = Math.sqrt(vn); gn = Math.sqrt(gn)
    if (power > 0) {
      if (gn > 0) for (let i = 0; i < v.length; i++) v[i] = (1 - alpha) * v[i] - alpha * g[i] / gn * vn
      sinceNegative++
      if (sinceNegative > 5) { dt = Math.min(dt * 1.1, dtMax); alpha *= 0.99 }
    } else { v.fill(0); dt *= 0.5; alpha = 0.1; sinceNegative = 0 }
    for (let i = 0; i < v.length; i++) v[i] -= dt * g[i]
    for (let i = 0; i < x.length; i++) x[i] += Math.max(-maxStep, Math.min(maxStep, dt * v[i]))
    e = field.energy(x, g)
  }
  return { x, energy: e }
}

export const flatten = (m: Molecule) => m.atoms.flatMap(a => [a.x, a.y, a.z])

export function optimizeMolecule(m: Molecule, effort = 24, seed = 2026): OptimizeResult {
  const n = m.atoms.length
  if (n < 2) return { molecule: m, energyBefore: 0, energyAfter: 0, starts: 0, rotors: 0 }
  const field = new Field(m), x0 = flatten(m), before = field.energy(x0)
  let best = minimize(field, x0), starts = 1
  const rng = new RNG(seed), rand = (lo: number, hi: number) => lo + rng.next() * (hi - lo)
  if (n <= 120) {
    const hasRing = field.bonds.length >= field.n
    const tries = field.rotors.length === 0 && m.bonds.length > 0 ? effort * 2 : hasRing ? effort * 2 : effort
    for (let t = 0; t < tries; t++) {
      let x = t % 2 === 0 ? best.x.slice() : x0.slice()
      if (field.rings.length && t % 3 === 0) {
        for (const ring of field.rings) {
          const nrm = ringNormal(x, ring), alternating = t % 6 === 0
          ring.forEach((a, k) => { const sign = alternating ? (k % 2 === 0 ? 1 : -1) : (rand(0, 1) < 0.5 ? 1 : -1), d = rand(0.25, 0.5) * sign; x[3 * a] += nrm[0] * d; x[3 * a + 1] += nrm[1] * d; x[3 * a + 2] += nrm[2] * d })
        }
        for (const ring of field.rings) rebuildSubstituents(x, ring, field)
        for (let i = 0; i < x.length; i++) x[i] += rand(-0.05, 0.05)
      } else if (field.rotors.length === 0 || t % 4 === 3) {
        const amp = rand(0.2, 0.7); for (let i = 0; i < x.length; i++) x[i] += rand(-amp, amp)
      } else {
        for (const r of rng.shuffle(field.rotors)) rotateAbout(x, field.side(r[1], r[0]), r[0], r[1], rand(0, 2 * Math.PI))
      }
      const res = minimize(field, x); starts++
      if (res.energy < best.energy - 1e-6) best = res
    }
  }
  const out: Molecule = { ...m, atoms: m.atoms.map(a => ({ ...a })) }
  let cx = 0, cy = 0, cz = 0; for (let i = 0; i < n; i++) { cx += best.x[3 * i]; cy += best.x[3 * i + 1]; cz += best.x[3 * i + 2] }
  cx /= n; cy /= n; cz /= n
  for (let i = 0; i < n; i++) { out.atoms[i].x = best.x[3 * i] - cx; out.atoms[i].y = best.x[3 * i + 1] - cy; out.atoms[i].z = best.x[3 * i + 2] - cz }
  return { molecule: out, energyBefore: before, energyAfter: best.energy, starts, rotors: field.rotors.length }
}

type V = [number, number, number]
const norm3 = (v: V): V => { const l = Math.max(1e-9, Math.hypot(v[0], v[1], v[2])); return [v[0] / l, v[1] / l, v[2] / l] }
/** After puckering a ring, put the two substituents of every sp³ ring atom back at ideal tetrahedral positions (carrying their branches). */
function rebuildSubstituents(x: number[], ring: number[], field: Field) {
  const inRing = new Set(ring), vec = (a: number, b: number): V => [x[3 * b] - x[3 * a], x[3 * b + 1] - x[3 * a + 1], x[3 * b + 2] - x[3 * a + 2]]
  for (const c of ring) {
    const ringNb = field.neighbors[c].filter(y => inRing.has(y)), subs = field.neighbors[c].filter(y => !inRing.has(y))
    if (ringNb.length !== 2 || subs.length !== 2) continue
    const ua = norm3(vec(c, ringNb[0])), ub = norm3(vec(c, ringNb[1]))
    const bis = norm3([ua[0] + ub[0], ua[1] + ub[1], ua[2] + ub[2]]), nrm = norm3([ua[1] * ub[2] - ua[2] * ub[1], ua[2] * ub[0] - ua[0] * ub[2], ua[0] * ub[1] - ua[1] * ub[0]])
    const phi = 54.75 * Math.PI / 180
    const sides = subs.map(s => { const v = vec(c, s); return v[0] * nrm[0] + v[1] * nrm[1] + v[2] * nrm[2] })
    const ord = sides[0] >= sides[1] ? [0, 1] : [1, 0]
    ord.forEach((k, rank) => {
      const s = subs[k], sign = rank === 0 ? 1 : -1, old = vec(c, s), len = Math.hypot(old[0], old[1], old[2])
      const d = [0, 1, 2].map(i => -bis[i] * Math.cos(phi) + sign * nrm[i] * Math.sin(phi))
      const delta = [0, 1, 2].map(i => x[3 * c + i] + d[i] * len - x[3 * s + i])
      for (const a of field.side(s, c)) { x[3 * a] += delta[0]; x[3 * a + 1] += delta[1]; x[3 * a + 2] += delta[2] }
    })
  }
}
export function ringNormal(x: number[], ring: number[]): V {
  let nx = 0, ny = 0, nz = 0
  for (let k = 0; k < ring.length; k++) {
    const a = ring[k], b = ring[(k + 1) % ring.length]
    nx += (x[3 * a + 1] - x[3 * b + 1]) * (x[3 * a + 2] + x[3 * b + 2]); ny += (x[3 * a + 2] - x[3 * b + 2]) * (x[3 * a] + x[3 * b]); nz += (x[3 * a] - x[3 * b]) * (x[3 * a + 1] + x[3 * b + 1])
  }
  const l = Math.hypot(nx, ny, nz); return l > 1e-9 ? [nx / l, ny / l, nz / l] : [0, 0, 1]
}
function rotateAbout(x: number[], atoms: number[], a: number, b: number, angle: number) {
  const ox = x[3 * a], oy = x[3 * a + 1], oz = x[3 * a + 2]
  let kx = x[3 * b] - ox, ky = x[3 * b + 1] - oy, kz = x[3 * b + 2] - oz
  const l = Math.hypot(kx, ky, kz); if (l <= 1e-9) return
  kx /= l; ky /= l; kz /= l
  const c = Math.cos(angle), s = Math.sin(angle)
  for (const i of atoms) {
    const px = x[3 * i] - ox, py = x[3 * i + 1] - oy, pz = x[3 * i + 2] - oz, d = kx * px + ky * py + kz * pz
    const cx = ky * pz - kz * py, cy = kz * px - kx * pz, cz = kx * py - ky * px
    x[3 * i] = ox + px * c + cx * s + kx * d * (1 - c); x[3 * i + 1] = oy + py * c + cy * s + ky * d * (1 - c); x[3 * i + 2] = oz + pz * c + cz * s + kz * d * (1 - c)
  }
}

/** Dihedral angle in degrees for atoms i-j-k-l. */
export function dihedral(m: Molecule, i: number, j: number, k: number, l: number): number {
  const v = (a: number, b: number): V => [m.atoms[b].x - m.atoms[a].x, m.atoms[b].y - m.atoms[a].y, m.atoms[b].z - m.atoms[a].z]
  const cross = (u: V, w: V): V => [u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]]
  const dot = (u: V, w: V) => u[0] * w[0] + u[1] * w[1] + u[2] * w[2]
  const b1 = v(i, j), b2 = v(j, k), b3 = v(k, l), n1 = cross(b1, b2), n2 = cross(b2, b3)
  const l2 = Math.sqrt(dot(b2, b2)), m1 = cross(n1, [b2[0] / l2, b2[1] / l2, b2[2] / l2])
  return Math.atan2(dot(m1, n2), dot(n1, n2)) * 180 / Math.PI
}
