import { describe, expect, test } from 'vitest'

const files = import.meta.glob('./locales/*.json', { eager: true, import: 'default' }) as Record<string, Record<string, string>>
const params = (s: string) => (s.match(/\{[a-zA-Z]+\}/g) ?? []).sort().join(',')

describe('locale dictionaries', () => {
  test('all five languages are present', () => {
    expect(Object.keys(files).map(f => f.replace(/.*\/|\.json$/g, '')).sort()).toEqual(['es', 'fr', 'ru', 'uk', 'zh'])
  })
  for (const [file, dict] of Object.entries(files)) {
    test(`${file}: the dictionary is populated`, () => {
      expect(Object.keys(dict).length).toBeGreaterThan(1000)
    })
    test(`${file}: placeholders are preserved`, () => {
      const bad = Object.entries(dict).filter(([k, v]) => !k.includes('|') && params(k) !== params(v)).map(([k]) => k)
      expect(bad).toEqual([])
    })
  }
})
