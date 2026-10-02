import { useMemo, useState } from 'preact/hooks'
import * as THREE from 'three'
import { atomicOrbitals, atomicFunction, hybridKinds, hybridLobe, V3 } from '../lib/orbitals'
import { orbitalMesh, orient, hybridLobeGeometry, phaseMaterial, POSITIVE, NEGATIVE } from '../lib/orbmesh'
import { Page, Segmented, Slider } from '../ui/kit'
import { Scene3D } from '../ui/Scene3D'

const modes = ['Atomic', 'Hybrid', 'Bonding'] as const
type Mode = typeof modes[number]
const interactions = ['σ  s + s', 'σ  s + p', 'σ  p + p (end-on)', 'π  p + p (side-on)'] as const
type Interaction = typeof interactions[number]
const coef = (v: number) => v.toFixed(3)

function axes(length: number): THREE.Object3D {
  const g = new THREE.Group()
  for (const [dir, color] of [[[1, 0, 0], 0xff3b30], [[0, 1, 0], 0x34c759], [[0, 0, 1], 0x0a84ff]] as [number[], number][]) {
    const c = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.012, length * 2, 8), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.55 }))
    c.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), new THREE.Vector3(...dir)); g.add(c)
  }
  return g
}
const nucleus = (at: V3 = [0, 0, 0]) => { const n = new THREE.Mesh(new THREE.SphereGeometry(0.07, 16, 12), new THREE.MeshBasicMaterial({ color: 0xffffff })); n.position.set(...at); return n }

export function OrbitalsScreen() {
  const [mode, setMode] = useState<Mode>('Atomic'), [atomic, setAtomic] = useState('pz'), [hybrid, setHybrid] = useState('sp3')
  const [inter, setInter] = useState<Interaction>('σ  p + p (end-on)'), [anti, setAnti] = useState(false), [dist, setDist] = useState(1.6), [reset, setReset] = useState(0)
  const key = `${mode}|${atomic}|${hybrid}|${inter}|${anti}|${dist}`
  const build = () => {
    const g = new THREE.Group()
    if (mode === 'Atomic') { g.add(orbitalMesh(atomicFunction(atomic), 1.6)); g.add(axes(2.2)) }
    else if (mode === 'Hybrid') {
      const h = hybridKinds.find(k => k.id === hybrid); if (!h) return g
      for (const d of h.directions) { const m = new THREE.Mesh(hybridLobeGeometry(h, 1.5).clone(), [phaseMaterial(POSITIVE, 0.7), phaseMaterial(NEGATIVE, 0.7)]); orient(m, d); g.add(m) }
      g.add(nucleus())
    } else {
      const a: V3 = [-dist / 2, 0, 0], b: V3 = [dist / 2, 0, 0], s = atomicFunction('s'), px = atomicFunction('px'), pz = atomicFunction('pz'), flip = anti ? -1 : 1
      const [fa, fb] = inter === 'σ  s + s' ? [s, (v: V3) => flip * s(v)] : inter === 'σ  s + p' ? [s, (v: V3) => -flip * px(v)] : inter === 'σ  p + p (end-on)' ? [px, (v: V3) => -flip * px(v)] : [pz, (v: V3) => flip * pz(v)]
      for (const [f, p] of [[fa, a], [fb, b]] as [(v: V3) => number, V3][]) { g.add(orbitalMesh(f, 1.25, { at: p, alpha: 0.62 })); g.add(nucleus(p)) }
      if (anti) { const plane = new THREE.Mesh(new THREE.CylinderGeometry(1.3, 1.3, 0.01, 48), new THREE.MeshBasicMaterial({ color: 0xb3b3b3, transparent: true, opacity: 0.22, side: THREE.DoubleSide, depthWrite: false })); plane.rotation.z = Math.PI / 2; g.add(plane) }
    }
    return g
  }
  const hk = hybridKinds.find(h => h.id === hybrid), ao = atomicOrbitals.find(a => a.id === atomic)
  const overlap = dist < 1 ? 'Too close: the nuclei would repel each other.' : dist < 2.4 ? 'Good overlap: a strong bond forms at this distance.' : dist < 3.2 ? 'Weak overlap.' : 'Almost no overlap: no bond.'
  void useMemo
  return <Page title="Orbitals" toolbar={<><Segmented value={mode} options={modes} onChange={setMode} label="Mode" /><button class="btn" title="Drag to rotate · scroll or pinch to zoom · double-click to reset" onClick={() => setReset(n => n + 1)}>↺ Reset view</button>
    <span class="grow" /><span class="row gap16 small"><span style={{ color: POSITIVE }}>● positive phase (+)</span><span style={{ color: NEGATIVE }}>● negative phase (−)</span></span></>}>
    <div class="split" style={{ gridTemplateColumns: 'minmax(0,1fr) 340px' }}>
      <div style={{ minHeight: 0 }}><Scene3D build={build} sceneKey={key} distance={mode === 'Bonding' ? 8 : 6.5} tilt={{ x: 0.32, y: 0.6 }} resetToken={reset} label={`${mode} orbital view`} /></div>
      <aside class="inspector pad col" style={{ gap: 14 }}>
        {mode === 'Atomic' && <><h3>Atomic orbital</h3><div class="col gap4" role="radiogroup" aria-label="Atomic orbital">{atomicOrbitals.map(o => <label key={o.id} class="check"><input type="radio" name="ao" checked={atomic === o.id} onChange={() => setAtomic(o.id)} />{o.label}</label>)}</div>
          {ao && <div class="dim">{ao.kind}</div>}<div class="dim">The two colors are the two signs of the wave function. Surfaces show the angular probability |ψ|². Where the sign changes the surface closes up: that is a node, a place the electron is never found.</div></>}
        {mode === 'Hybrid' && <><h3>Hybrid set</h3><div class="col gap4" role="radiogroup" aria-label="Hybrid set">{hybridKinds.map(o => <label key={o.id} class="check"><input type="radio" name="hy" checked={hybrid === o.id} onChange={() => setHybrid(o.id)} />{o.name}</label>)}</div>
          {hk && <><div class="dim">{hk.note}</div><div class="mono">Each lobe: ψ = {coef(hk.cs)}·s + {coef(hk.cp)}·p</div><div class="small dim">Each lobe has a small opposite-phase lobe on the far side (barely visible here).</div></>}</>}
        {mode === 'Bonding' && <><h3>Overlap</h3><div class="col gap4" role="radiogroup" aria-label="Overlap">{interactions.map(o => <label key={o} class="check"><input type="radio" name="in" checked={inter === o} onChange={() => setInter(o)} />{o}</label>)}</div>
          <Segmented small value={anti ? 'Antibonding (out of phase)' : 'Bonding (in phase)'} options={['Bonding (in phase)', 'Antibonding (out of phase)'] as const} onChange={v => setAnti(v.startsWith('Anti'))} label="Phase" />
          <label class="row gap8">Distance <Slider label="Distance" value={dist} min={0.6} max={4} step={0.05} onChange={setDist} width={150} /></label>
          <div class="dim">{overlap}</div>
          <div>{anti ? 'Out of phase, the lobes cancel between the nuclei and a node plane appears there (shown as a gray disc).' : 'In phase, the lobes add up between the nuclei, which is what holds the atoms together.'}</div></>}
      </aside>
    </div>
  </Page>
}
export { hybridLobe }
