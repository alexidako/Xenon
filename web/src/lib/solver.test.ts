import { describe, expect, it } from 'vitest'
import { elements, elementBySymbol } from './element'
import { solve, solveStructured } from './solver'
import { speciesFrom, solveStoich } from './stoich'
import { formatNumber } from './format'

const isEl = (s: string) => elementBySymbol.has(s)
const ok = (eq: string) => { const r = solve(eq, isEl); return r.ok ? r.value : 'ERR ' + r.error.message }

describe('solver', () => {
  it('combustion of ethanol', () => expect(ok('aCH3CH2OH + bO2 -> cH2O + dCO2')).toBe('CH3CH2OH + 3 O2 -> 3 H2O + 2 CO2'))
  it('water', () => expect(ok('aH2 + bO2 -> cH2O')).toBe('2 H2 + O2 -> 2 H2O'))
  it('redox with charges', () => expect(ok('aFe[2+] + bMnO4[-] + cH[+] -> dFe[3+] + eMn[2+] + fH2O')).toBe('5 Fe[2+] + MnO4[-] + 8 H[+] -> 5 Fe[3+] + Mn[2+] + 4 H2O'))
  it('rejects junk', () => { for (const s of ['', 'H2', 'H2->', '->O2', 'aXx -> bH', 'aH2( -> bH2', 'aH2 -> bO2']) expect(ok(s)).toMatch(/^ERR/) })
  it('structured', () => { const r = solveStructured('aH2 + bO2 -> cH2O', isEl); expect(r.ok && r.value.left.map(e => e.coefficient)).toEqual([2, 1]) })
})
describe('stoichiometry', () => {
  const masses = new Map(elements.map(e => [e.symbol, e.mass ?? 0]))
  const setup = (eq: string) => { const r = solveStructured(eq, isEl); if (!r.ok) throw r.error; return speciesFrom(r.value, s => masses.get(s)) }
  it('limiting reagent', () => {
    const sp = setup('aH2 + bO2 -> cH2O')
    expect(sp.map(s => s.coefficient)).toEqual([2, 1, 2])
    const out = solveStoich(sp, new Map([[0, [4, 'g']], [1, [32, 'g']]]))!
    expect(out.limiting!.formula).toBe('H2')
    expect(out.products[0].grams).toBeCloseTo(35.74, 1)
    expect(solveStoich(sp, new Map([[0, [4, 'g']], [1, [8, 'g']]]))!.limiting!.formula).toBe('O2')
    expect(solveStoich(sp, new Map([[1, [1, 'mol']]]))!.products[0].moles).toBeCloseTo(2, 9)
  })
  it('ethanol yield', () => {
    const e = setup('aCH3CH2OH + bO2 -> cH2O + dCO2')
    expect(solveStoich(e, new Map([[0, [10, 'g']]]))!.products.at(-1)!.grams).toBeCloseTo(19.1, 0)
  })
})
describe('format', () => {
  it('numbers', () => { expect(formatNumber(1234.5678)).toBe('1234.568'); expect(formatNumber(0)).toBe('0'); expect(formatNumber(NaN)).toBe('—') })
})
