import { describe, expect, it } from 'vitest'
import { Field, optimizeMolecule, flatten, dihedral } from './optimizer'
import { Sketch, makeTemplate, bondLength, newId } from './sketch'
import { embed3D } from './embed3d'
import { Molecule, moleculeLibrary } from './molecule'
import { bondAngles } from './vbt'
import { bondAngleItems } from './angles'
import { Trackball } from './trackball'
import { RNG } from './quiz'

const mol = (n: string) => embed3D(makeTemplate(n, 0, 0), n)
const near = (v: number, t: number, tol: number) => { let d = Math.abs(v - t) % 360; if (d > 180) d = 360 - d; return d <= tol }
const nbOf = (m: Molecule, a: number) => m.bonds.flatMap(b => b.a === a ? [b.b] : b.b === a ? [b.a] : [])
const torsions = (m: Molecule, a: number, b: number) => nbOf(m, a).filter(x => x !== b).flatMap(i => nbOf(m, b).filter(x => x !== a).map(l => dihedral(m, i, a, b, l)))
const angle = (m: Molecule, s: string) => { const c = m.atoms.findIndex(a => a.symbol === s); return bondAngles(c, m, nbOf(m, c)) }
function chain(n: number): Sketch { const s = new Sketch(); s.atoms = Array.from({ length: n }, (_, k) => ({ id: newId(), symbol: 'C', x: k * bondLength * 0.85, y: k % 2 ? bondLength * 0.5 : 0 })); s.bonds = s.atoms.slice(1).map((a, k) => ({ id: newId(), a: s.atoms[k].id, b: a.id, order: 1 })); return s }

describe('optimizer', () => {
  it('analytic forces match finite differences', () => {
    for (const name of ['Acetic acid', 'Benzene']) {
      const m = mol(name), rng = new RNG(5), x = flatten(m).map(v => v + (rng.next() - 0.5) * 0.4), f = new Field(m), g = new Array(x.length).fill(0); f.energy(x, g)
      let worst = 0
      for (let i = 0; i < x.length; i++) { const xp = x.slice(), xm = x.slice(); xp[i] += 1e-5; xm[i] -= 1e-5; const num = (f.energy(xp) - f.energy(xm)) / 2e-5; worst = Math.max(worst, Math.abs(num - g[i]) / Math.max(1, Math.abs(num))) }
      expect(worst, name).toBeLessThan(1e-4)
    }
  })
  it('never raises the energy and is repeatable', () => { const a = optimizeMolecule(mol('Ethanol')), b = optimizeMolecule(mol('Ethanol')); expect(a.energyAfter).toBeLessThanOrEqual(a.energyBefore + 1e-6); expect(a.molecule.atoms.map(p => p.x)).toEqual(b.molecule.atoms.map(p => p.x)) })
  it('ethane is staggered', () => {
    const e = optimizeMolecule(embed3D(chain(2), 'ethane')).molecule, cs = e.atoms.map((a, i) => a.symbol === 'C' ? i : -1).filter(i => i >= 0), t = torsions(e, cs[0], cs[1])
    expect(t.length).toBe(9); for (const v of t) expect(near(Math.abs(v), 60, 12) || near(v, 180, 12)).toBe(true)
  })
  it('butane is anti', () => {
    const b = optimizeMolecule(embed3D(chain(4), 'butane')).molecule, cs = b.atoms.map((a, i) => a.symbol === 'C' ? i : -1).filter(i => i >= 0)
    const mid = cs.filter(c => nbOf(b, c).filter(x => b.atoms[x].symbol === 'C').length === 2), ends = cs.filter(c => nbOf(b, c).filter(x => b.atoms[x].symbol === 'C').length === 1)
    const cA = ends.find(e => nbOf(b, mid[0]).includes(e))!, cB = ends.find(e => nbOf(b, mid[1]).includes(e))!
    expect(near(Math.abs(dihedral(b, cA, mid[0], mid[1], cB)), 180, 10)).toBe(true)
  })
  it('cyclohexane is a chair, lower in energy than the flat drawing', () => {
    const r = optimizeMolecule(mol('Cyclohexane')), m = r.molecule, f = new Field(m), ring = f.rings.find(x => x.length === 6)!
    const t = ring.map((_, k) => dihedral(m, ring[k], ring[(k + 1) % 6], ring[(k + 2) % 6], ring[(k + 3) % 6]))
    for (const v of t) expect(Math.abs(Math.abs(v) - 55)).toBeLessThan(12); for (let k = 0; k < 6; k++) expect(t[k] * t[(k + 1) % 6]).toBeLessThan(0)
    expect(r.energyAfter).toBeLessThan(r.energyBefore)
  })
  it('π systems stay flat; textbook angles survive', () => {
    const eth = optimizeMolecule(mol('Ethene')).molecule, ec = eth.atoms.map((a, i) => a.symbol === 'C' ? i : -1).filter(i => i >= 0)
    for (const v of torsions(eth, ec[0], ec[1])) expect(near(v, 0, 8) || near(v, 180, 8)).toBe(true)
    const ben = optimizeMolecule(mol('Benzene')).molecule; expect(Math.max(...ben.atoms.map(a => Math.abs(a.z)))).toBeLessThan(0.1)
    for (const b of ben.bonds) if (ben.atoms[b.a].symbol === 'C' && ben.atoms[b.b].symbol === 'C') { const p = ben.atoms[b.a], q = ben.atoms[b.b], d = Math.hypot(p.x - q.x, p.y - q.y, p.z - q.z); expect(d).toBeGreaterThan(1.3); expect(d).toBeLessThan(1.5) }
    expect(Math.abs(angle(optimizeMolecule(mol('Water')).molecule, 'O')[0] - 104.5)).toBeLessThan(3)
    expect(Math.abs(angle(optimizeMolecule(mol('Carbon dioxide')).molecule, 'C')[0] - 180)).toBeLessThan(3)
    for (const a of angle(optimizeMolecule(mol('Ammonia')).molecule, 'N')) expect(Math.abs(a - 107)).toBeLessThan(4)
  })
  it('every bundled molecule optimizes cleanly', () => {
    for (const m of moleculeLibrary) {
      const r = optimizeMolecule(m, 6)
      expect(r.molecule.atoms.every(a => Number.isFinite(a.x + a.y + a.z)), m.name).toBe(true); expect(r.energyAfter, m.name).toBeLessThanOrEqual(r.energyBefore + 1e-6)
      for (const b of r.molecule.bonds) { const p = r.molecule.atoms[b.a], q = r.molecule.atoms[b.b], d = Math.hypot(p.x - q.x, p.y - q.y, p.z - q.z); expect(d, m.name).toBeGreaterThan(0.8); expect(d, m.name).toBeLessThan(2.2) }
    }
  })
  it('edge cases', () => { expect(optimizeMolecule({ name: 'He', atoms: [{ symbol: 'He', x: 0, y: 0, z: 0 }], bonds: [] }).molecule.atoms.length).toBe(1); expect(optimizeMolecule({ name: '', atoms: [], bonds: [] }).molecule.atoms.length).toBe(0) })
})
describe('bond angle list', () => {
  it('counts', () => {
    expect(bondAngleItems(mol('Water')).length).toBe(1); expect(Math.abs(bondAngleItems(mol('Water'))[0].degrees - 104.5)).toBeLessThan(3)
    const me = bondAngleItems(mol('Methane')); expect(me.length).toBe(6); for (const a of me) expect(Math.abs(a.degrees - 109.5)).toBeLessThan(4)
    expect(bondAngleItems(mol('Carbon dioxide'))[0].degrees).toBeGreaterThan(177)
    const eth = mol('Ethanol'), c1 = eth.atoms.findIndex(a => a.symbol === 'C'), o = eth.atoms.findIndex(a => a.symbol === 'O')
    expect(bondAngleItems(eth, new Set([c1])).length).toBeGreaterThan(bondAngleItems(eth).filter(a => a.center === c1).length)
    expect(bondAngleItems(eth, new Set([o])).length).toBe(1); expect(bondAngleItems({ name: 'x', atoms: [], bonds: [] }).length).toBe(0)
  })
})
describe('trackball', () => {
  it('keeps the camera within limits however it is thrown around', () => {
    const t = new Trackball(10), rng = new RNG(99)
    for (let i = 0; i < 2000; i++) { t.rotate((rng.next() - 0.5) * 160, (rng.next() - 0.5) * 160); t.zoom((rng.next() - 0.5) * 6) }
    expect(t.distance).toBeGreaterThanOrEqual(3 - 1e-9); expect(t.distance).toBeLessThanOrEqual(20 + 1e-9); expect(Math.hypot(...t.orientation)).toBeCloseTo(1, 6)
    t.reset(); expect(t.distance).toBe(10)
  })
})
