import * as THREE from 'three'
import { Fn, V3, hybridKinds, hybridLobe, HybridKind, pAlong } from './orbitals'

export const POSITIVE = '#4085ff', NEGATIVE = '#ff7340'

/** Turns an angular function into a surface: each direction is pushed out to |f|², and the surface is split into a
 *  positive-phase part and a negative-phase part so the two can have different colors. */
export function orbitalGeometry(f: Fn, scale: number, nLat = 40, nLon = 80): THREE.BufferGeometry {
  const n = (nLat + 1) * (nLon + 1), pts = new Float32Array(3 * n), vals = new Float64Array(n)
  const raw: number[] = []; let ref = 0, idx = 0
  for (let i = 0; i <= nLat; i++) {
    const th = Math.PI * i / nLat
    for (let j = 0; j <= nLon; j++) {
      const ph = 2 * Math.PI * j / nLon, u: V3 = [Math.sin(th) * Math.cos(ph), Math.sin(th) * Math.sin(ph), Math.cos(th)], v = f(u), r = v * v
      vals[idx] = v; raw.push(u[0] * r, u[1] * r, u[2] * r); ref = Math.max(ref, r); idx++
    }
  }
  const k = ref > 0 ? scale / ref : 0
  for (let i = 0; i < n * 3; i++) pts[i] = raw[i] * k
  const normals = new Float32Array(3 * n), pos: number[] = [], neg: number[] = [], w = nLon + 1
  for (let i = 0; i < nLat; i++) for (let j = 0; j < nLon; j++) {
    const a = i * w + j, b = a + 1, c = a + w, d = c + 1
    for (const [p, q, r] of [[a, c, b], [b, c, d]]) {
      const ux = pts[3 * q] - pts[3 * p], uy = pts[3 * q + 1] - pts[3 * p + 1], uz = pts[3 * q + 2] - pts[3 * p + 2], vx = pts[3 * r] - pts[3 * p], vy = pts[3 * r + 1] - pts[3 * p + 1], vz = pts[3 * r + 2] - pts[3 * p + 2]
      let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
      if (Math.hypot(nx, ny, nz) < 1e-12) continue                                     // collapsed at a node
      const cx = pts[3 * p] + pts[3 * q] + pts[3 * r], cy = pts[3 * p + 1] + pts[3 * q + 1] + pts[3 * r + 1], cz = pts[3 * p + 2] + pts[3 * q + 2] + pts[3 * r + 2]
      if (nx * cx + ny * cy + nz * cz < 0) { nx = -nx; ny = -ny; nz = -nz }              // face outward
      for (const t of [p, q, r]) { normals[3 * t] += nx; normals[3 * t + 1] += ny; normals[3 * t + 2] += nz }
      ;(vals[p] + vals[q] + vals[r] >= 0 ? pos : neg).push(p, q, r)
    }
  }
  for (let i = 0; i < n; i++) { const l = Math.hypot(normals[3 * i], normals[3 * i + 1], normals[3 * i + 2]); if (l > 0) { normals[3 * i] /= l; normals[3 * i + 1] /= l; normals[3 * i + 2] /= l } else normals[3 * i + 2] = 1 }
  const g = new THREE.BufferGeometry()
  g.setAttribute('position', new THREE.BufferAttribute(pts, 3)); g.setAttribute('normal', new THREE.BufferAttribute(normals, 3))
  g.setIndex([...pos, ...neg]); g.addGroup(0, pos.length, 0); g.addGroup(pos.length, neg.length, 1)
  return g
}

export const phaseMaterial = (color: string, alpha: number) => new THREE.MeshPhongMaterial({ color, specular: 0x444444, shininess: 35, transparent: true, opacity: alpha, side: THREE.DoubleSide, depthWrite: false })

export function orbitalMesh(f: Fn, scale: number, opts: { at?: V3; positive?: string; negative?: string; alpha?: number } = {}): THREE.Mesh {
  const m = new THREE.Mesh(orbitalGeometry(f, scale), [phaseMaterial(opts.positive ?? POSITIVE, opts.alpha ?? 0.7), phaseMaterial(opts.negative ?? NEGATIVE, opts.alpha ?? 0.7)])
  if (opts.at) m.position.set(...opts.at)
  return m
}

/** Lobe shapes built once along +z, then rotated into place. */
const cache = new Map<string, THREE.BufferGeometry>()
export function hybridLobeGeometry(kind: HybridKind, scale: number): THREE.BufferGeometry {
  const key = `h${kind.id}${scale}`; let g = cache.get(key)
  if (!g) { g = orbitalGeometry(hybridLobe(kind.cs, kind.cp, [0, 0, 1]), scale); cache.set(key, g) }
  return g
}
export function pLobeGeometry(scale: number): THREE.BufferGeometry {
  const key = `p${scale}`; let g = cache.get(key)
  if (!g) { g = orbitalGeometry(pAlong([0, 0, 1]), scale); cache.set(key, g) }
  return g
}
/** Rotate +z onto `d`. */
export function orient(obj: THREE.Object3D, d: V3) {
  const v = new THREE.Vector3(...d); if (v.lengthSq() === 0) return
  obj.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), v.normalize())
}
export const hybridById = (id: string) => hybridKinds.find(h => h.id === id)
