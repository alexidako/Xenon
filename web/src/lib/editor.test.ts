import { describe, expect, it } from 'vitest'
import { Sketch, makeTemplate, newId } from './sketch'
import { embed3D } from './embed3d'
import { Molecule } from './molecule'
import { bondAngles } from './vbt'
import { analyzeOrbitals, overlayItems } from './molorb'
import { moleculeLibrary } from './molecule'
import { analyzeMolecule } from './vbt'
import { dot, normalize, cross, V3 } from './orbitals'

const sk = (t: string) => makeTemplate(t, 0, 0)
const angles = (m: Molecule, symbol: string, nth = 0) => {
  const idx = m.atoms.map((a, i) => a.symbol === symbol ? i : -1).filter(i => i >= 0); if (nth >= idx.length) return []
  const c = idx[nth]; const nb = m.bonds.flatMap(b => b.a === c ? [b.b] : b.b === c ? [b.a] : [])
  return bondAngles(c, m, nb)
}
const near = (xs: number[], t: number, tol: number) => xs.length > 0 && xs.every(x => Math.abs(x - t) <= tol)

describe('sketch', () => {
  it('formulas and masses', () => {
    expect(sk('Ethanol').formula).toBe('C2H6O'); expect(sk('Ethanol').mass).toBeCloseTo(46.07, 1)
    expect(sk('Benzene').formula).toBe('C6H6'); expect(sk('Acetic acid').formula).toBe('C2H4O2')
    expect(sk('Ethyne').formula).toBe('C2H2'); expect(sk('Ammonia').formula).toBe('H3N'); expect(sk('Water').formula).toBe('H2O')
  })
  it('valence checking', () => {
    const bad = new Sketch(); const c = { id: newId(), symbol: 'C', x: 0, y: 0 }; bad.atoms.push(c)
    for (let k = 0; k < 5; k++) { const h = { id: newId(), symbol: 'H', x: k * 10, y: 50 }; bad.atoms.push(h); bad.bonds.push({ id: newId(), a: c.id, b: h.id, order: 1 }) }
    expect(bad.problems.length).toBe(1); expect(bad.problems[0].atom.symbol).toBe('C')
    expect(sk('Methane').addingHydrogens().atoms.length).toBe(5)
  })
})
describe('3D embedding', () => {
  it('ideal geometries', () => {
    expect(near(angles(embed3D(sk('Methane'), 'm'), 'C'), 109.5, 5)).toBe(true)
    expect(near(angles(embed3D(sk('Water'), 'w'), 'O'), 104.5, 5)).toBe(true)
    expect(near(angles(embed3D(sk('Ammonia'), 'a'), 'N'), 107, 5)).toBe(true)
    expect(near(angles(embed3D(sk('Carbon dioxide'), 'c'), 'C'), 180, 3)).toBe(true)
    const e = embed3D(sk('Ethene'), 'e'); expect(near(angles(e, 'C'), 120, 6)).toBe(true); expect(e.atoms.every(a => Math.abs(a.z - e.atoms[0].z) < 0.05)).toBe(true)
    const et = embed3D(sk('Ethanol'), 'et'); const cc = [...angles(et, 'C', 0), ...angles(et, 'C', 1), ...angles(et, 'O')]; expect(cc.every(a => a > 100 && a < 118)).toBe(true)
    const b = embed3D(sk('Benzene'), 'b'); expect(b.atoms.every(a => Math.abs(a.z) < 0.05)).toBe(true); expect(near(angles(b, 'C'), 120, 6)).toBe(true)
    for (const bd of b.bonds) { const p = b.atoms[bd.a], q = b.atoms[bd.b]; const d = Math.hypot(p.x - q.x, p.y - q.y, p.z - q.z); expect(d).toBeGreaterThan(0.9); expect(d).toBeLessThan(1.7) }
  })
})
describe('orbital placement in molecules', () => {
  const lobes = (m: Molecule, symbol: string, nth = 0) => {
    const idx = m.atoms.map((a, i) => a.symbol === symbol ? i : -1).filter(i => i >= 0); const a = idx[nth]; const r = analyzeOrbitals(m)
    return { sigma: r.sigma.filter(l => l.atom === a).map(l => l.direction), lp: r.lonePairs.filter(l => l.atom === a).map(l => l.direction), pi: r.pi.filter(p => p.a === a || p.b === a).map(p => p.axis) }
  }
  const tmpl = (n: string) => embed3D(sk(n), n)
  const ang = (a: V3, b: V3) => Math.acos(Math.max(-1, Math.min(1, dot(normalize(a), normalize(b))))) * 180 / Math.PI
  it('methane', () => { const m = moleculeLibrary.find(x => x.name === 'Methane')!; const c = lobes(m, 'C'); expect([c.sigma.length, c.lp.length, c.pi.length]).toEqual([4, 0, 0]) })
  it('ammonia', () => { const n = lobes(tmpl('Ammonia'), 'N'); const away = normalize(n.sigma.reduce((s, v) => [s[0] - v[0], s[1] - v[1], s[2] - v[2]] as V3, [0, 0, 0] as V3)); expect(n.sigma.length).toBe(3); expect(n.lp.length).toBe(1); expect(dot(n.lp[0], away)).toBeGreaterThan(0.99) })
  it('water', () => {
    const o = lobes(tmpl('Water'), 'O'); expect([o.sigma.length, o.lp.length]).toEqual([2, 2])
    const between = ang(o.lp[0], o.lp[1]); expect(between).toBeGreaterThan(100); expect(between).toBeLessThan(125)
    for (const l of o.lp) for (const s of o.sigma) { expect(ang(l, s)).toBeGreaterThan(95); expect(ang(l, s)).toBeLessThan(125) }
  })
  it('ethene pi is perpendicular to the plane', () => { const c = lobes(tmpl('Ethene'), 'C'); const n = normalize(cross(c.sigma[0], c.sigma[1])); expect(c.sigma.length).toBe(3); expect(c.pi.length).toBe(1); expect(Math.abs(dot(c.pi[0], n))).toBeGreaterThan(0.98) })
  it('ethyne has two perpendicular pi', () => { const c = lobes(tmpl('Ethyne'), 'C'); expect(c.pi.length).toBe(2); expect(Math.abs(dot(c.pi[0], c.sigma[0]))).toBeLessThan(0.05); expect(Math.abs(dot(c.pi[1], c.sigma[0]))).toBeLessThan(0.05); expect(Math.abs(dot(c.pi[0], c.pi[1]))).toBeLessThan(0.05) })
  it('acetone carbonyl', () => {
    const o = lobes(tmpl('Acetone'), 'O'); expect([o.sigma.length, o.pi.length, o.lp.length]).toEqual([1, 1, 2])
    for (const l of o.lp) { expect(Math.abs(dot(l, o.pi[0]))).toBeLessThan(0.15); expect(Math.abs(ang(l, o.sigma[0]) - 120)).toBeLessThan(10) }
  })
  it('overlay filter', () => {
    const m = moleculeLibrary.find(x => x.name === 'Ethanol')!
    const all = overlayItems(m, 'σ, lone pairs & π').length
    const o = analyzeMolecule(m).atoms.find(a => a.element?.symbol === 'O')!.index
    expect(overlayItems(m, 'σ, lone pairs & π', new Set([o])).length).toBe(5)   // 2 σ + 2 lone pairs + its H
    expect(all).toBeGreaterThan(5); expect(overlayItems(m, 'Off', new Set([o])).length).toBe(0)
    expect(overlayItems(m, 'σ, lone pairs & π', new Set()).length).toBe(all)
    const eth = embed3D(sk('Ethene'), 'e'); const c0 = analyzeMolecule(eth).atoms.find(a => a.element?.symbol === 'C')!.index
    expect(overlayItems(eth, 'σ, lone pairs & π', new Set([c0])).length - overlayItems(eth, 'σ bonds & lone pairs', new Set([c0])).length).toBe(2)
  })
})
