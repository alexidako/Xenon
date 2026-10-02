import { describe, expect, it } from 'vitest'
import { runQuery } from './query'
import { rankSpectrum, parseWavelengths } from './matcher'

const syms = (q: string, stable: any = null) => runQuery(q, stable)?.matches.map(e => e.symbol) ?? []
describe('query', () => {
  it('liquid at room temperature', () => { const l = syms('liquid at room temperature'); expect(l).toContain('Hg'); expect(l).toContain('Br'); expect(l.length).toBeLessThanOrEqual(3) })
  it('noble gases', () => expect(syms('noble gases').sort()).toEqual(['Ar', 'He', 'Kr', 'Ne', 'Og', 'Rn', 'Xe']))
  it('halogens before 1850', () => expect(new Set(syms('halogens discovered before 1850'))).toEqual(new Set(['Cl', 'Br', 'I'])))
  it('highest electronegativity', () => expect(syms('highest electronegativity')[0]).toBe('F'))
  it('heaviest noble gas', () => expect(syms('heaviest noble gas')[0]).toBe('Og'))
  it('melting point above 3000 K', () => { const h = syms('melting point above 3000 K'); for (const s of ['W', 'Re', 'Ta', 'Os']) expect(h).toContain(s); expect(h).not.toContain('Fe') })
  it('group 17', () => expect(new Set(syms('group 17'))).toEqual(new Set(['F', 'Cl', 'Br', 'I', 'At', 'Ts'])))
  it('period 2 nonmetals', () => expect(new Set(syms('period 2 nonmetals'))).toEqual(new Set(['C', 'N', 'O'])))
  it('boiling below 0 C', () => { const c = syms('boiling point below 0 °C'); for (const s of ['He', 'N', 'O']) expect(c).toContain(s); expect(c).not.toContain('Fe') })
  it('plain names are not queries', () => { for (const n of ['iron', 'mercury', 'sodium']) expect(runQuery(n, null)).toBeNull() })
  it('sweden', () => { const s = syms('discovered in sweden'); expect(s.length).toBeGreaterThan(0) })
  it('unsupported', () => expect(runQuery('density of lead', null)?.unsupported).toBe(true))
  it('lowest melting point', () => expect(syms('lowest melting point')).toContain('He'))
  it('s-block metals in period 3', () => expect(new Set(syms('s-block metals in period 3'))).toEqual(new Set(['Na', 'Mg'])))
  it('radioactive group 17', () => expect(new Set(runQuery('radioactive group 17')!.matches.map(e => e.symbol))).toEqual(new Set(['At', 'Ts'])))
})
describe('spectrum matcher', () => {
  const top = (obs: number[], tol = 1) => rankSpectrum(obs, tol).slice(0, 3).map(c => c.element.symbol)
  it('H', () => expect(top([486.13, 656.28])[0]).toBe('H'))
  it('He', () => expect(top([587.56, 667.82, 706.52, 501.57])[0]).toBe('He'))
  it('Na', () => expect(top([589.0, 589.6])[0]).toBe('Na'))
  it('mix', () => { const m = rankSpectrum([486.13, 656.28, 587.56, 667.82], 1).slice(0, 4).map(c => c.element.symbol); expect(m).toContain('H'); expect(m).toContain('He') })
  it('edge cases', () => { expect(rankSpectrum([], 1)).toEqual([]); expect(rankSpectrum([123], 0.05)).toEqual([]); expect(parseWavelengths('4861, 6563', true)).toEqual([486.1, 656.3]) })
})
