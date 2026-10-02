import * as THREE from 'three'
import { Molecule } from './molecule'
import { elementBySymbol } from './element'
import { OverlayMode, overlayItems } from './molorb'
import { hybridKindNamed, V3 } from './orbitals'
import { hybridLobeGeometry, pLobeGeometry, phaseMaterial, orient } from './orbmesh'
import { bondAngleItems } from './angles'

export const molStyles = ['Ball & stick', 'Space filling', 'Sticks'] as const
export type MolStyle = typeof molStyles[number]

const sigmaColor = '#4d8cff', lonePairColor = '#b861f2', arcColor = '#ffd140'

function atomRadius(symbol: string, style: MolStyle): number {
  const e = elementBySymbol.get(symbol)
  switch (style) { case 'Ball & stick': return 0.32 * Math.max(0.6, e?.radiusCovalent ?? 0.8) + 0.08; case 'Space filling': return (e?.radiusVDW ?? 1.6) * 0.95; case 'Sticks': return 0.11 }
}

function labelSprite(text: string, color = arcColor): THREE.Sprite {
  const c = document.createElement('canvas'); c.width = 160; c.height = 64
  const g = c.getContext('2d')!; g.font = '600 38px system-ui, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle'
  g.lineWidth = 6; g.strokeStyle = 'rgba(0,0,0,.65)'; g.strokeText(text, 80, 34); g.fillStyle = color; g.fillText(text, 80, 34)
  const tex = new THREE.CanvasTexture(c); tex.colorSpace = THREE.SRGBColorSpace
  const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false, depthWrite: false, transparent: true }))
  sp.scale.set(0.75, 0.3, 1); sp.renderOrder = 100; return sp
}

const up = new THREE.Vector3(0, 1, 0)
function cylinderBetween(p: THREE.Vector3, q: THREE.Vector3, radius: number, mat: THREE.Material): THREE.Mesh {
  const d = q.clone().sub(p), len = d.length(), m = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, Math.max(len, 1e-4), 12, 1), mat)
  m.position.copy(p).add(q).multiplyScalar(0.5); if (len > 1e-9) m.quaternion.setFromUnitVectors(up, d.normalize()); return m
}

export interface MolSceneOptions { style: MolStyle; orbitals: OverlayMode; atoms: Set<number>; angles: boolean }
export interface MolScene { group: THREE.Group; distance: number }

export function buildMoleculeScene(m: Molecule, o: MolSceneOptions): MolScene {
  const group = new THREE.Group(), n = m.atoms.length || 1
  const c = m.atoms.reduce((s, a) => [s[0] + a.x / n, s[1] + a.y / n, s[2] + a.z / n], [0, 0, 0])
  const centred: Molecule = { ...m, atoms: m.atoms.map(a => ({ ...a, x: a.x - c[0], y: a.y - c[1], z: a.z - c[2] })) }
  const pts = centred.atoms.map(a => new THREE.Vector3(a.x, a.y, a.z))
  const extent = Math.max(1, ...pts.map(p => p.length()))

  centred.atoms.forEach((a, i) => {
    const e = elementBySymbol.get(a.symbol), col = [...(e?.color ?? [0.6, 0.6, 0.6]), 0.6, 0.6, 0.6]
    const s = new THREE.Mesh(new THREE.SphereGeometry(atomRadius(a.symbol, o.style), 32, 20), new THREE.MeshPhongMaterial({ color: new THREE.Color(col[0], col[1], col[2]), specular: 0xffffff, shininess: 60 }))
    s.position.copy(pts[i]); group.add(s)
  })
  if (o.style !== 'Space filling') {
    const mat = new THREE.MeshPhongMaterial({ color: 0xbfbfbf })
    for (const b of centred.bonds) {
      if (b.a >= pts.length || b.b >= pts.length) continue
      const p = pts[b.a], q = pts[b.b], d = q.clone().sub(p); if (d.length() < 1e-9) continue
      let perp = new THREE.Vector3(-d.y, d.x, 0); if (Math.abs(d.x) < 1e-6 && Math.abs(d.y) < 1e-6) perp = new THREE.Vector3(1, 0, 0); perp.normalize()
      const offs = b.order === 1 ? [0] : b.order === 2 ? [-0.1, 0.1] : [-0.18, 0, 0.18]
      for (const k of offs) { const sh = perp.clone().multiplyScalar(k); group.add(cylinderBetween(p.clone().add(sh), q.clone().add(sh), o.style === 'Sticks' ? 0.11 : b.order === 1 ? 0.08 : 0.05, mat)) }
    }
  }
  // orbitals
  for (const it of overlayItems(centred, o.orbitals, o.atoms)) {
    const at = pts[it.atom]
    if (it.kind === 's') {
      const sp = new THREE.Mesh(new THREE.SphereGeometry(0.5, 28, 18), new THREE.MeshPhongMaterial({ color: sigmaColor, transparent: true, opacity: 0.35, side: THREE.DoubleSide, depthWrite: false })); sp.position.copy(at); group.add(sp)
    } else if (it.kind === 'pi') {
      const mesh = new THREE.Mesh(pLobeGeometry(0.8), [phaseMaterial('#ff9e26', 0.6), phaseMaterial('#33ccbf', 0.6)]); mesh.position.copy(at); orient(mesh, it.direction as V3); group.add(mesh)
    } else {
      const kind = hybridKindNamed(it.hybrid); if (!kind) continue
      const col = it.kind === 'sigma' ? sigmaColor : lonePairColor
      const mesh = new THREE.Mesh(hybridLobeGeometry(kind, it.kind === 'sigma' ? 0.95 : 0.85), [phaseMaterial(col, 0.55), phaseMaterial(col, 0.28)]); mesh.position.copy(at); orient(mesh, it.direction as V3); group.add(mesh)
    }
  }
  // bond angles: an arc and a label at every pair of bonds
  if (o.angles) {
    const all = bondAngleItems(centred, o.atoms), rank = new Map<number, number[]>()
    for (const x of all) rank.set(x.center, [...(rank.get(x.center) ?? []), x.degrees])
    for (const l of rank.values()) l.sort((p, q) => p - q)
    const arcMat = new THREE.MeshBasicMaterial({ color: arcColor })
    for (const x of all) {
      const origin = pts[x.center], ua = pts[x.a].clone().sub(origin), ub = pts[x.b].clone().sub(origin), bondLen = Math.min(ua.length(), ub.length()); ua.normalize(); ub.normalize()
      const k = rank.get(x.center)!.indexOf(x.degrees), r = Math.max(0.55, Math.min(bondLen * 0.55, 1.1), atomRadius(centred.atoms[x.center].symbol, o.style) + 0.28) + 0.13 * k
      const theta = Math.acos(Math.max(-1, Math.min(1, ua.dot(ub)))); if (theta < 0.02) continue
      const steps = Math.max(6, Math.floor(theta / 0.12)); let prev = origin.clone().add(ua.clone().multiplyScalar(r))
      for (let s = 1; s <= steps; s++) {
        const t = s / steps
        const dir = theta > 3.1 ? ua.clone().multiplyScalar(1 - t).add(ub.clone().multiplyScalar(t)).normalize()
          : ua.clone().multiplyScalar(Math.sin((1 - t) * theta) / Math.sin(theta)).add(ub.clone().multiplyScalar(Math.sin(t * theta) / Math.sin(theta))).normalize()
        const next = origin.clone().add(dir.multiplyScalar(r)); group.add(cylinderBetween(prev, next, 0.018, arcMat)); prev = next
      }
      let bis = ua.clone().add(ub); if (bis.length() < 1e-6) bis = new THREE.Vector3().crossVectors(ua, Math.abs(ua.x) < 0.9 ? new THREE.Vector3(1, 0, 0) : new THREE.Vector3(0, 1, 0))
      const sp = labelSprite(`${x.degrees.toFixed(1)}°`); sp.position.copy(origin).add(bis.normalize().multiplyScalar(r + 0.3)); group.add(sp)
    }
  }
  return { group, distance: extent * 2.6 + 4 }
}
