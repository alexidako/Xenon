import { describe, expect, it } from 'vitest'
import { QuizEngine, QuizStats, RNG, quizKinds, prettyConfig } from './quiz'
import { elements, elementBySymbol, elementByZ, familyInfo } from './element'
import { FillState, order, subIndex, aufbau, actualConfig, reasonFor, sameConfig } from './filling'

const mem = () => { const m = new Map<string, string>(); return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => void m.set(k, v), removeItem: (k: string) => void m.delete(k) } }

describe('quiz', () => {
  it('questions are well-formed and correct for every kind', () => {
    const problems: string[] = []; const perKind: Record<string, number> = {}
    const stats = new QuizStats(mem())
    for (const kind of quizKinds) {
      const engine = new QuizEngine(54, [kind], stats)
      for (let seed = 0; seed < 80; seed++) {
        const rng = new RNG(seed)
        const q = engine.make(kind, engine.pick(rng), rng); if (!q) continue
        perKind[kind] = (perKind[kind] ?? 0) + 1
        const e = elementByZ.get(q.z)!
        if (!q.explanation) problems.push(kind + ': empty explanation')
        if (kind === 'Find it on the table') { if (q.options.length) problems.push('find has options'); continue }
        if (q.options.length < 2 || new Set(q.options).size !== q.options.length) problems.push(`${kind}: options ${q.options}`)
        const right = q.options[q.correct]
        if ((kind === 'Symbol → name' || kind === 'Atomic number → name' || kind === 'Electron configurations') && right !== e.name) problems.push(`${kind}: ${right} ≠ ${e.name}`)
        if (kind === 'Name → symbol' && right !== e.symbol) problems.push(`${kind}: ${right}`)
        if (kind === 'Name → atomic number' && right !== String(e.z)) problems.push(`${kind}: ${right}`)
        if (kind === 'Element families' && right !== familyInfo(e)?.label) problems.push('family')
        if (kind === 'Periodic trends') {
          const answer = elementByZ.get(q.answerZ)!
          if (right !== answer.name) problems.push('trend answer')
        }
      }
    }
    expect(problems).toEqual([])
    for (const k of quizKinds) expect(perKind[k] ?? 0, k).toBeGreaterThanOrEqual(40)
  })
  it('is deterministic per seed and stays in range', () => {
    const a = new QuizEngine(36, ['Symbol → name', 'Element families'], new QuizStats(mem())), b = new QuizEngine(36, ['Symbol → name', 'Element families'], new QuizStats(mem()))
    const ra = new RNG(7), rb = new RNG(7)
    for (let i = 0; i < 10; i++) expect(a.next(ra).prompt).toBe(b.next(rb).prompt)
    const small = new QuizEngine(20, [...quizKinds], new QuizStats(mem())), r = new RNG(3)
    for (let i = 0; i < 100; i++) expect(small.next(r).z).toBeLessThanOrEqual(20)
  })
  it('weak spots', () => {
    const st = mem(); const stats = new QuizStats(st)
    for (let i = 0; i < 6; i++) stats.record(26, false)
    for (let i = 0; i < 6; i++) stats.record(8, true)
    expect([stats.weight(26), stats.weight(8), stats.weight(99)]).toEqual([6, 1, 1])
    const w = new QuizEngine(36, ['Symbol → name'], stats, true), rng = new RNG(11)
    const drawn = Array.from({ length: 3000 }, () => w.pick(rng).z)
    const fe = drawn.filter(z => z === 26).length / 3000, ne = drawn.filter(z => z === 10).length / 3000
    expect(fe).toBeGreaterThan(4 * ne); expect(fe).toBeGreaterThan(0.1)
    expect(stats.weakSpots[0].z).toBe(26); expect(new QuizStats(st).entries[26].missed).toBe(6)
    stats.reset(); expect(new QuizStats(st).weakSpots).toEqual([])
  })
  it('config formatting', () => { expect(prettyConfig('[He] 2s2 2p4')).toBe('[He] 2s² 2p⁴'); expect(prettyConfig('1s1')).toBe('1s¹') })
})

describe('electron filling', () => {
  const el = (s: string) => elementBySymbol.get(s)!
  const fill = (e: ReturnType<typeof el>, moves: [string, number][], strict = true) => {
    const s = new FillState(), errors: string[] = []
    for (const [n, b] of moves) { const r = s.place(subIndex(n), b, e.z, strict); if (!r.ok) errors.push(r.why) }
    return { s, errors }
  }
  const autofill = (e: ReturnType<typeof el>) => { const s = new FillState(); for (let t = s.nextTarget(e.z); t; t = s.nextTarget(e.z)) s.place(t.sub, t.box, e.z, true); return s }
  it('order', () => {
    expect(order.slice(0, 8).map(s => s.name)).toEqual(['1s', '2s', '2p', '3s', '3p', '4s', '3d', '4p'])
    expect(order.slice(11, 16).map(s => s.name)).toEqual(['6s', '4f', '5d', '6p', '7s'])
  })
  it('rules', () => {
    const o = el('O')
    expect(fill(o, [['2s', 0]]).errors[0]).toContain('Aufbau')
    const p = fill(o, [['1s', 0], ['1s', 0], ['1s', 0]]); expect(p.s.total).toBe(2); expect(p.errors[0]).toContain('Pauli')
    const h = fill(o, [['1s', 0], ['1s', 0], ['2s', 0], ['2s', 0], ['2p', 0], ['2p', 0]]); expect(h.s.total).toBe(5); expect(h.errors[0]).toContain('Hund')
    const ok = fill(o, [['1s', 0], ['1s', 0], ['2s', 0], ['2s', 0], ['2p', 0], ['2p', 1], ['2p', 2], ['2p', 0]])
    expect(ok.errors).toEqual([]); expect(ok.s.verdict(o).matchesActual).toBe(true)
    const over = fill(o, [['1s', 0], ['1s', 0], ['2s', 0], ['2s', 0], ['2p', 0], ['2p', 1], ['2p', 2], ['2p', 0], ['2p', 1]]); expect(over.errors.at(-1)).toContain('already placed')
  })
  it('autofill reproduces ordinary elements; exceptions flagged', () => {
    const ordinary = ['H', 'He', 'C', 'N', 'O', 'Ne', 'Na', 'Si', 'Cl', 'Ar', 'K', 'Ca', 'Sc', 'Fe', 'Zn', 'Br', 'Kr', 'Sr', 'Sn', 'Xe', 'Ba', 'Pb', 'Rn']
    expect(ordinary.filter(s => !autofill(el(s)).verdict(el(s)).matchesActual)).toEqual([])
    const cr = el('Cr'); const strict = autofill(cr)
    expect(strict.configuration).toEqual(aufbau(24)); expect(strict.verdict(cr).matchesActual).toBe(false); expect(strict.verdict(cr).message).toContain('exception')
    expect(reasonFor(el('Cu'))).toContain('completely filled')
    const ex = elements.filter(e => !sameConfig(aufbau(e.z), actualConfig(e))).map(e => e.symbol)
    for (const s of ['Cr', 'Cu', 'Nb', 'Mo', 'Ru', 'Rh', 'Pd', 'Ag', 'La', 'Ce', 'Gd', 'Pt', 'Au', 'Th', 'U']) expect(ex).toContain(s)
    expect(ex).not.toContain('Fe'); expect(ex).not.toContain('O')
  })
  it('remove', () => { const s = new FillState(); s.place(0, 0, 2, true); expect(s.remove(0, 0)).toBe(true); expect(s.remove(0, 0)).toBe(false) })
})
