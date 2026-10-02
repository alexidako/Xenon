import { describe, expect, it } from 'vitest'
import { elements, stateAt, iupacGroup, elementBySymbol, decayLabel, halfLifeText, isotopes } from './element'
import { markupPlain, formulaText } from './markup'
import { parseFormula, molarMass } from './formula'
import { parseExpr, evalExpr } from './expr'

describe('data', () => {
  it('has 118 elements', () => expect(elements.length).toBe(118))
  it('arsenic sublimes', () => { const as = elementBySymbol.get('As')!; expect(stateAt(as, 300)).toBe('Solid') })
  it('germanium is group 14', () => expect(iupacGroup(32)).toBe(14))
  it('decay label', () => expect(decayLabel('betaminusneutron')).toBe('β⁻ + n'))
  it('half life', () => expect(halfLifeText(isotopes.find(i => i.z === 1 && i.a === 1)!)).toBe('stable'))
})
describe('markup', () => {
  it('magnetic moment', () => expect(markupPlain('μ[sub]n[/sub]=(5.0507866 ± 0.0000017) 10[sup]-27[/sup] JT[sup]-1[/sup]')).toBe('μₙ=(5.0507866 ± 0.0000017) 10⁻²⁷ JT⁻¹'))
  it('beta + break', () => expect(markupPlain('ß[sup]+[/sup] decay[br]next')).toBe('β⁺ decay\nnext'))
  it('formulas', () => {
    expect(formulaText('CH3CH2OH + 3 O2 -> 3 H2O + 2 CO2')).toBe('CH₃CH₂OH + 3 O₂ -> 3 H₂O + 2 CO₂')
    expect(formulaText('Fe[2+] + MnO4[-] + 8 H3O[+]')).toBe('Fe²⁺ + MnO₄⁻ + 8 H₃O⁺')
    expect(formulaText('C10H22')).toBe('C₁₀H₂₂')
  })
})
describe('formula', () => {
  it('water', () => expect(molarMass('H2O')!).toBeCloseTo(18.015, 2))
  it('nested', () => expect(molarMass('Al2(SO4)3')!).toBeCloseTo(342.15, 1))
  it('aliases', () => expect(molarMass('EtOH')!).toBeCloseTo(46.07, 1))
  it('rejects junk', () => { for (const f of ['O0', 'Xx', '(', 'H2)', '', '2']) expect(parseFormula(f)).toBeNull() })
})
describe('expr', () => {
  const ev = (s: string) => evalExpr(parseExpr(s)!, () => 0)
  it('arithmetic', () => { expect(ev('2+3*4')).toBe(14); expect(ev('2^3^2')).toBe(512); expect(ev('10^-3')).toBeCloseTo(0.001); expect(ev('1,5*2')).toBe(3); expect(ev('1e-5')).toBeCloseTo(1e-5) })
  it('rejects', () => { for (const s of ['', '2+', '(1', '1..2']) expect(parseExpr(s)).toBeNull() })
})
