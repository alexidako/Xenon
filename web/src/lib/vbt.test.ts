import { describe, expect, it } from 'vitest'
import { elementBySymbol as el } from './element'
import { Hybridization, analyzeMolecule } from './vbt'
import { moleculeLibrary, parseXYZ, parseMOL, parseCML, exportMolecule, formulaOf, loadMolecule } from './molecule'

const h = (s: string, sg: number, p = 0) => Hybridization.make(el.get(s)!, sg, p)
const chk = (x: Hybridization | null, hybrid: string, lp: number, shape: string) => { expect(x?.hybridName).toBe(hybrid); expect(x?.lonePairs).toBe(lp); expect(x?.shape?.name).toBe(shape) }
const mol = (n: string) => moleculeLibrary.find(m => m.name.toLowerCase() === n) ?? moleculeLibrary.find(m => m.name.toLowerCase().includes(n))!

describe('hybridization', () => {
  it('textbook cases', () => {
    chk(h('C', 4), 'sp³', 0, 'tetrahedral'); chk(h('N', 3), 'sp³', 1, 'trigonal pyramidal'); chk(h('O', 2), 'sp³', 2, 'bent')
    chk(h('B', 3), 'sp²', 0, 'trigonal planar'); chk(h('Be', 2), 'sp', 0, 'linear'); chk(h('C', 2, 2), 'sp', 0, 'linear')
    chk(h('C', 3, 1), 'sp²', 0, 'trigonal planar'); chk(h('S', 2, 2), 'sp²', 1, 'bent'); chk(h('S', 4), 'sp³d', 1, 'seesaw')
    chk(h('Cl', 3), 'sp³d', 2, 'T-shaped'); chk(h('P', 5), 'sp³d', 0, 'trigonal bipyramidal'); chk(h('S', 6), 'sp³d²', 0, 'octahedral'); chk(h('Xe', 4), 'sp³d²', 2, 'square planar')
  })
  it('charges', () => {
    expect(h('C', 1, 2)).toBeNull()
    const c = Hybridization.makeAllowingCharge(el.get('C')!, 1, 2)!, o = Hybridization.makeAllowingCharge(el.get('O')!, 1, 2)!
    expect([c.charge, c.hybridName, c.lonePairs, o.charge, o.hybridName, o.lonePairs]).toEqual([-1, 'sp', 1, 1, 'sp', 1])
    const n = Hybridization.makeAllowingCharge(el.get('N')!, 4, 0)!; expect([n.charge, n.hybridName, n.lonePairs]).toEqual([1, 'sp³', 0])
    expect(Hybridization.makeAllowingCharge(el.get('C')!, 4, 0)!.charge).toBe(0)
    const f = Hybridization.makeAllowingCharge(el.get('F')!, 3, 0); expect(f == null || f.charge !== 0).toBe(true)
    expect(h('Fe', 2)).toBeNull()
  })
  it('boxes hold the valence electrons; promotion', () => {
    for (const x of [h('C', 4), h('N', 3), h('O', 2), h('S', 6), h('Xe', 4), h('C', 2, 2), h('Cl', 3)]) {
      const sum = (b: { electrons: number }[]) => b.reduce((s, y) => s + y.electrons, 0)
      expect(sum(x!.hybridized)).toBe(x!.valence); expect(sum(x!.groundState)).toBe(x!.valence)
    }
    expect(h('C', 4)!.needsPromotion).toBe(true); expect(h('N', 3)!.needsPromotion).toBe(false)
  })
  it('whole molecules from the library', () => {
    const a = analyzeMolecule(mol('methane')).atoms.find(x => x.element?.symbol === 'C')!
    expect(a.hybrid?.hybridName).toBe('sp³'); expect(a.measuredAngles.length).toBeGreaterThan(0); for (const x of a.measuredAngles) expect(Math.abs(x - 109.5)).toBeLessThan(2)
    const w = analyzeMolecule(mol('water')).atoms.find(x => x.element?.symbol === 'O')!
    expect(w.hybrid?.shape?.name).toBe('bent'); expect(Math.abs(w.measuredAngles[0] - 104.5)).toBeLessThan(3)
    const co2 = analyzeMolecule(mol('carbon dioxide')); expect(co2.atoms.find(x => x.element?.symbol === 'C')!.hybrid?.hybridName).toBe('sp'); expect(co2.bonds.every(b => b.detail.includes('π'))).toBe(true)
    expect(analyzeMolecule(mol('ethanol')).atoms.filter(x => x.element?.symbol !== 'H').every(x => x.hybrid?.hybridName === 'sp³')).toBe(true)
  })
})
describe('molecules', () => {
  it('library loads', () => { expect(moleculeLibrary.length).toBe(19); expect(moleculeLibrary.some(m => m.name === 'Ethanol')).toBe(true) })
  it('round trips', () => {
    const m = mol('ethanol')
    for (const f of ['xyz', 'mol', 'cml'] as const) {
      const back = loadMolecule(exportMolecule(m, f), `x.${f}`)!
      expect(back.atoms.length).toBe(m.atoms.length); expect(formulaOf(back)).toBe(formulaOf(m))
      if (f !== 'xyz') expect(back.bonds.length).toBe(m.bonds.length)
    }
    expect(formulaOf(m)).toBe('C2H6O')
  })
  it('rejects malformed input', () => {
    expect(parseXYZ('-3\nx\n', 'a')).toBeNull(); expect(parseXYZ('2\nx\nH 0 0 0', 'a')).toBeNull()
    expect(parseMOL('t\n\n\n -1  0\n', 'a')).toBeNull(); expect(parseCML('<molecule/>', 'a')).toBeNull(); expect(parseCML('garbage', 'a')).toBeNull()
  })
})
