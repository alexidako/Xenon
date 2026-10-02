import { describe, expect, it } from 'vitest'
import { searchPalette } from './palette'

const top = (q: string) => searchPalette(q)[0]?.target
describe('quick lookup', () => {
  it('finds things', () => {
    expect(top('tungsten')).toEqual({ kind: 'element', z: 74 }); expect(top('fe')).toEqual({ kind: 'element', z: 26 }); expect(top('26')).toEqual({ kind: 'element', z: 26 })
    expect(top('gas law')).toEqual({ kind: 'screen', id: 'calculators' }); expect(top('aufbau')).toEqual({ kind: 'screen', id: 'filling' })
    expect(top('balance equation')).toEqual({ kind: 'screen', id: 'solver' }); expect(top('celsius')).toEqual({ kind: 'screen', id: 'settings' })
    expect(searchPalette('magnetic').some(i => i.target.kind === 'glossary' && i.target.name === 'Magnetic Moment')).toBe(true)
    expect(searchPalette('beaker').some(i => i.target.kind === 'equipment' && i.target.name === 'Beaker')).toBe(true)
    expect(searchPalette('c2h6o').some(i => i.target.kind === 'molecule')).toBe(true)
  })
  it('edge cases', () => {
    expect(searchPalette('zzzzqq')).toEqual([]); expect(searchPalette('').length).toBeGreaterThanOrEqual(10); expect(searchPalette('   ').length).toBeGreaterThanOrEqual(10)
    const items = searchPalette('o'); expect(new Set(items.map(i => i.id)).size).toBe(items.length); expect(items.length).toBeLessThanOrEqual(14)
    for (const q of ['(', '[', '\\', '%%', '💥', 'a'.repeat(500), 'a b c', '-1', '9999']) searchPalette(q)
  })
})
