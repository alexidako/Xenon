import { describe, expect, it } from 'vitest'
import { solveGas, R_GAS, concentrations, requiredSolute, soluteMassFrom, solveDecay, fitTitration, theoryCurve, bestTimeUnit, Solution } from './calc'

describe('gas', () => {
  it('ideal gas: 1 mol at 273 K and 1 atm is 22.4 L', () => expect(solveGas('Volume', { P: 1, V: 0, T: 273.15, n: 1, a: 0, b: 0 })!).toBeCloseTo(22.414, 2))
  it('round trips all four unknowns', () => {
    const g = { P: 2, V: 10, T: 300, n: 0, a: 1.36, b: 0.0318 }
    const n = solveGas('Amount', g)!; const g2 = { ...g, n }
    expect(solveGas('Pressure', { ...g2, P: 0 })!).toBeCloseTo(2, 6); expect(solveGas('Temperature', { ...g2, T: 0 })!).toBeCloseTo(300, 4); expect(solveGas('Volume', { ...g2, V: 0 })!).toBeCloseTo(10, 6)
    expect(solveGas('Pressure', { P: 0, V: 0.01, T: 300, n: 1, a: 0, b: 0.02 })).toBeNull(); expect(R_GAS).toBeGreaterThan(0)
  })
})
describe('concentration', () => {
  const s: Solution = { molarMass: 58.5, eqMass: 58.5, soluteDensity: 2.17, solventKind: 'Volume (L)', solventAmount: 1, solventMolarMass: 18.015, solventDensity: 1 }
  it('117 g NaCl in 1 L water is 2 mol/L', () => { const c = concentrations(soluteMassFrom(117, 'Mass (g)', s), s); expect(c[0][1]).toBeCloseTo(2, 6); expect(c[3][1]).toBeCloseTo(117 / 1117 * 100, 6) })
  it('required solute is the inverse', () => { expect(requiredSolute('Molarity (mol/L)', 2, s)!).toBeCloseTo(117, 6); expect(requiredSolute('% (mass)', 100, s)).toBeNull(); expect(requiredSolute('% (mass)', 10, s)!).toBeCloseTo(111.11, 1) })
})
describe('nuclear decay', () => {
  it('half-lives', () => { expect(solveDecay('Final amount', 10, 8, 0, 20)!).toBeCloseTo(2, 9); expect(solveDecay('Initial amount', 10, 0, 2, 20)!).toBeCloseTo(8, 9); expect(solveDecay('Time', 10, 6, 3, 0)!).toBeCloseTo(10, 9)
    expect(solveDecay('Time', 10, 3, 6, 0)).toBeNull(); expect(solveDecay('Final amount', 0, 1, 0, 1)).toBeNull(); expect(bestTimeUnit(4.468e9 * 31557600)).toBe(0) })
})
describe('titration', () => {
  it('fits a tanh curve and finds the equivalence point', () => {
    const f = (x: number) => 3.5 * Math.tanh(0.8 * (x - 31)) + 8; const pts = [29, 30, 30.5, 31, 31.5, 32, 33].map(x => ({ x, y: f(x) }))
    expect(fitTitration(pts)!.equivalence).toBeCloseTo(31, 0); expect(fitTitration(pts.slice(0, 2))).toBeNull()
  })
  it('evaluates the theory curve with nested variables', () => {
    const t = theoryCurve([{ name: 'A', text: '(C*D)/(B*K)' }, { name: 'K', text: '10^-3' }, { name: 'C', text: 'OH' }, { name: 'OH', text: '(10^-14)/H' }, { name: 'H', text: '10^-4' }, { name: 'B', text: '6*(10^-2)' }], 'D', 'A', 0, 60)!
    expect(t.samples.length).toBe(241); expect(t.samples[240].y).toBeCloseTo(1e-10 * 60 / (0.06 * 1e-3), 6); expect(t.formula).toBe('A = (C*D)/(B*K)')
    expect(theoryCurve([{ name: 'A', text: '2+' }], 'D', 'A', 0, 1)).toBeNull(); expect(theoryCurve([], 'D', 'A', 0, 1)).toBeNull()
  })
})
