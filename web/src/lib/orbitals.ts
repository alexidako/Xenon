export type V3 = [number, number, number]
export const dot = (a: V3, b: V3) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
export const len = (a: V3) => Math.hypot(a[0], a[1], a[2])
export const normalize = (a: V3): V3 => { const l = len(a) || 1; return [a[0] / l, a[1] / l, a[2] / l] }
export const sub = (a: V3, b: V3): V3 => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
export const add = (a: V3, b: V3): V3 => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
export const scale = (a: V3, k: number): V3 => [a[0] * k, a[1] * k, a[2] * k]
export const cross = (a: V3, b: V3): V3 => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

export type Fn = (v: V3) => number

/** Angular parts of atomic orbitals and hybrids, evaluated at a unit vector. Surfaces are drawn at r = ψ². */
const ys = 0.28209479, yp = 0.48860251, yd = 0.31539157, yd2 = 1.09254843, yd3 = 0.54627422
export const Y = { ys, yp }

export interface AtomicOrbital { id: string; label: string; kind: string }
export const atomicOrbitals: AtomicOrbital[] = [
  { id: 's', label: 's', kind: '1 lobe, no node' },
  { id: 'px', label: 'pₓ', kind: '2 lobes, node plane yz' },
  { id: 'py', label: 'p_y', kind: '2 lobes, node plane xz' },
  { id: 'pz', label: 'p_z', kind: '2 lobes, node plane xy' },
  { id: 'dz2', label: 'd_z²', kind: '2 lobes and a ring' },
  { id: 'dxz', label: 'd_xz', kind: '4 lobes' },
  { id: 'dyz', label: 'd_yz', kind: '4 lobes' },
  { id: 'dxy', label: 'd_xy', kind: '4 lobes' },
  { id: 'dx2y2', label: 'd_x²−y²', kind: '4 lobes on the axes' },
]

export function atomicFunction(id: string): Fn {
  switch (id) {
    case 's': return () => ys
    case 'px': return v => yp * v[0]
    case 'py': return v => yp * v[1]
    case 'pz': return v => yp * v[2]
    case 'dz2': return v => yd * (3 * v[2] * v[2] - 1)
    case 'dxz': return v => yd2 * v[0] * v[2]
    case 'dyz': return v => yd2 * v[1] * v[2]
    case 'dxy': return v => yd2 * v[0] * v[1]
    case 'dx2y2': return v => yd3 * (v[0] * v[0] - v[1] * v[1])
    default: return () => 0
  }
}
export const pAlong = (axis: V3): Fn => { const a = normalize(axis); return v => yp * dot(v, a) }

export interface HybridKind { id: string; name: string; cs: number; cp: number; directions: V3[]; note: string }
const unit = (x: number, y: number, z: number) => normalize([x, y, z])
const tet: V3[] = [unit(1, 1, 1), unit(1, -1, -1), unit(-1, 1, -1), unit(-1, -1, 1)]
const trig: V3[] = [0, 1, 2].map(k => { const t = k * 2 * Math.PI / 3; return [Math.cos(t), Math.sin(t), 0] as V3 })
export const hybridKinds: HybridKind[] = [
  { id: 'sp', name: 'sp', cs: Math.sqrt(0.5), cp: Math.sqrt(0.5), directions: [[0, 0, 1], [0, 0, -1]],
    note: 'One s and one p orbital mix into two hybrids 180° apart. Two p orbitals are left over for π bonds.' },
  { id: 'sp2', name: 'sp²', cs: Math.sqrt(1 / 3), cp: Math.sqrt(2 / 3), directions: trig,
    note: 'One s and two p orbitals give three hybrids at 120° in a plane. The leftover p orbital stands perpendicular to that plane.' },
  { id: 'sp3', name: 'sp³', cs: 0.5, cp: Math.sqrt(0.75), directions: tet,
    note: 'One s and three p orbitals give four hybrids pointing to the corners of a tetrahedron (109.5°).' },
  { id: 'sp3d', name: 'sp³d (schematic)', cs: 0.5, cp: Math.sqrt(0.75), directions: [...trig, [0, 0, 1], [0, 0, -1]],
    note: 'Five hybrids: three in a plane at 120° and two axial. Drawn with the sp³ lobe shape; the d contribution is not rendered.' },
  { id: 'sp3d2', name: 'sp³d² (schematic)', cs: 0.5, cp: Math.sqrt(0.75), directions: [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]],
    note: 'Six hybrids to the corners of an octahedron (90°). Drawn with the sp³ lobe shape; the d contribution is not rendered.' },
]
export function hybridKindNamed(n: string | null | undefined): HybridKind | undefined {
  if (!n) return undefined
  const key = ({ sp: 'sp', 'sp²': 'sp2', 'sp³': 'sp3', 'sp³d': 'sp3d', 'sp³d²': 'sp3d2' } as Record<string, string>)[n] ?? n
  return hybridKinds.find(h => h.id === key)
}
/** One hybrid lobe pointing along `d`: cs·s + cp·p_d. */
export const hybridLobe = (cs: number, cp: number, d: V3): Fn => { const n = normalize(d); return v => cs * ys + cp * yp * dot(v, n) }

/** ∫ f·g dΩ over the unit sphere (midpoint rule). */
export function overlapIntegral(f: Fn, g: Fn, nLat = 120, nLon = 240): number {
  let sum = 0
  const dt = Math.PI / nLat, dp = 2 * Math.PI / nLon
  for (let i = 0; i < nLat; i++) {
    const th = (i + 0.5) * dt, w = Math.sin(th) * dt * dp
    for (let j = 0; j < nLon; j++) {
      const ph = (j + 0.5) * dp
      const u: V3 = [Math.sin(th) * Math.cos(ph), Math.sin(th) * Math.sin(ph), Math.cos(th)]
      sum += f(u) * g(u) * w
    }
  }
  return sum
}
export function perpendicularTo(v: V3): V3 {
  const u = normalize(v)
  const ref: V3 = Math.abs(u[0]) < 0.9 ? [1, 0, 0] : [0, 1, 0]
  return normalize(sub(ref, scale(u, dot(ref, u))))
}
