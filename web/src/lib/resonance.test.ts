import { describe, expect, it } from 'vitest'
import { resonancePresets, resonanceStructures, hybridOrders, averageCharges, ResonanceInput } from './resonance'
import { elementBySymbol } from './element'
import { atomicFunction, hybridKinds, hybridLobe, overlapIntegral, perpendicularTo, dot } from './orbitals'

const run = (n: string) => resonanceStructures(resonancePresets.find(p => p.name === n)!) ?? []
const sum = (a: number[]) => a.reduce((x, y) => x + y, 0)
describe('resonance', () => {
  it('ozone', () => { const o = run('Ozone'); expect(o.length).toBe(2); for (const s of o) { expect([...s.orders].sort()).toEqual([1, 2]); expect([...s.charges].sort((a, b) => a - b)).toEqual([-1, 0, 1]) } })
  it('nitrate', () => {
    const n = run('Nitrate'); expect(n.length).toBe(3)
    for (const s of n) { expect([...s.orders].sort()).toEqual([1, 1, 2]); expect(s.charges[0]).toBe(1); expect(sum(s.charges)).toBe(-1) }
    for (const o of hybridOrders(n)) expect(o).toBeCloseTo(4 / 3, 9)
    const avg = averageCharges(n); expect(avg[0]).toBe(1); for (const c of avg.slice(1)) expect(c).toBeCloseTo(-2 / 3, 9)
  })
  it('carbonate, CO, sulfate, SO2', () => {
    const c = run('Carbonate'); expect(c.length).toBe(3); for (const s of c) { expect(s.charges[0]).toBe(0); expect(sum(s.charges)).toBe(-2) }
    const co = run('Carbon monoxide'); expect(co.length).toBe(1); expect(co[0].orders).toEqual([3]); expect(co[0].charges).toEqual([-1, 1])
    const so4 = run('Sulfate'); expect(so4.length).toBe(6); for (const s of so4) { expect(s.orders.filter(o => o === 2).length).toBe(2); expect(s.charges[0]).toBe(0) }
    const so2 = run('Sulfur dioxide'); expect(so2.length).toBe(1); expect(so2[0].orders).toEqual([2, 2]); expect(so2[0].charges).toEqual([0, 0, 0])
  })
  it('benzene, acetate, ammonium, hydronium', () => {
    const b = run('Benzene'); expect(b.length).toBe(2); for (const s of b) expect(s.orders.slice(0, 6).sort()).toEqual([1, 1, 1, 2, 2, 2]); for (const o of hybridOrders(b).slice(0, 6)) expect(o).toBeCloseTo(1.5, 9)
    const a = run('Acetate'); expect(a.length).toBe(2); for (const o of hybridOrders(a).slice(0, 2)) expect(o).toBeCloseTo(1.5, 9)
    const nh = run('Ammonium'); expect([nh.length, nh[0].charges[0], nh[0].lonePairs[0]]).toEqual([1, 1, 0])
    const h3 = run('Hydronium'); expect([h3.length, h3[0].charges[0], h3[0].lonePairs[0]]).toEqual([1, 1, 1])
  })
  it('every preset is consistent', () => {
    for (const p of resonancePresets) {
      const ss = resonanceStructures(p); expect(ss, p.name).not.toBeNull()
      for (const s of ss!) {
        expect(sum(s.charges), p.name).toBe(p.charge)
        s.lonePairs.forEach((lp, i) => {
          const bonds = p.bonds.reduce((t, b, k) => (b[0] === i || b[1] === i ? t + s.orders[k] : t), 0)
          if (p.atoms[i].symbol === 'H') expect(bonds).toBe(1); else expect(2 * lp + 2 * bonds).toBeLessThanOrEqual(12)
        })
      }
    }
  })
  it('refuses the impossible', () => {
    expect(resonanceStructures({ name: 'x', formula: 'x', atoms: [{ symbol: 'Fe', x: 0, y: 0 }], bonds: [], charge: 0 })).toBeNull()
    const odd: ResonanceInput = { name: 'NO2', formula: 'NO₂', atoms: [{ symbol: 'O', x: 0, y: 0 }, { symbol: 'N', x: 1, y: 0 }, { symbol: 'O', x: 2, y: 0 }], bonds: [[0, 1], [1, 2]], charge: 0 }
    expect(resonanceStructures(odd)).toBeNull()
    expect(elementBySymbol.get('N')).toBeDefined()
  })
})
describe('orbital math', () => {
  it('atomic orbitals are orthonormal', () => {
    const ids = ['s', 'px', 'py', 'pz', 'dz2', 'dxz', 'dyz', 'dxy', 'dx2y2']
    for (const a of ids) for (const b of ids) expect(overlapIntegral(atomicFunction(a), atomicFunction(b), 60, 120), `${a}${b}`).toBeCloseTo(a === b ? 1 : 0, 2)
  })
  it('hybrids are normalised and orthogonal', () => {
    for (const h of hybridKinds.slice(0, 3)) {
      const lobes = h.directions.map(d => hybridLobe(h.cs, h.cp, d))
      lobes.forEach((f, i) => lobes.forEach((g, j) => expect(overlapIntegral(f, g, 60, 120), `${h.id} ${i}${j}`).toBeCloseTo(i === j ? 1 : 0, 3)))
    }
  })
  it('perpendicular helper', () => { for (const v of [[1, 0, 0], [0, 1, 0], [1, 2, 3]] as [number, number, number][]) expect(Math.abs(dot(perpendicularTo(v), v))).toBeLessThan(1e-9) })
})
