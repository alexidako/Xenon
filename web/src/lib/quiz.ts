import { Element, elements, families, familyInfo, iupacGroup } from './element'
import { formatNumber } from './format'
import { superscript } from './config'
import { t } from '../i18n'

/** Small seeded RNG (mulberry32) so quiz tests are repeatable. */
export class RNG {
  private s: number
  constructor(seed = Math.floor(Math.random() * 2 ** 31)) { this.s = (seed + 0x9E3779B9) >>> 0 }
  next(): number {
    this.s = (this.s + 0x6D2B79F5) >>> 0
    let t = this.s
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  int(n: number) { return Math.floor(this.next() * n) }
  pick<T>(a: readonly T[]): T { return a[this.int(a.length)] }
  shuffle<T>(a: readonly T[]): T[] { const r = a.slice(); for (let i = r.length - 1; i > 0; i--) { const j = this.int(i + 1); [r[i], r[j]] = [r[j], r[i]] } return r }
  bool() { return this.next() < 0.5 }
}

export const quizKinds = ['Symbol → name', 'Name → symbol', 'Atomic number → name', 'Name → atomic number', 'Find it on the table', 'Element families', 'Periodic trends', 'Electron configurations'] as const
export type QuizKind = typeof quizKinds[number]

export interface QuizQuestion {
  kind: QuizKind; prompt: string
  options: string[]          // empty for "find it on the table"
  correct: number            // index into options; ignored for findOnTable
  z: number                  // the element this question is mainly about
  answerZ: number            // atomic number of the right answer (== z except for trends)
  explanation: string
}

/** Remembers which elements you miss, so practice can lean on them. */
export class QuizStats {
  entries: Record<number, { seen: number; missed: number }> = {}
  constructor(private storage: Pick<Storage, 'getItem' | 'setItem' | 'removeItem'> | null = defaultStorage(), private key = 'xenon.quizStats.v1') {
    try { const raw = storage?.getItem(key); if (raw) this.entries = JSON.parse(raw) } catch { /* start fresh */ }
  }
  private save() { try { this.storage?.setItem(this.key, JSON.stringify(this.entries)) } catch { /* ignore */ } }
  record(z: number, correct: boolean) {
    const e = this.entries[z] ?? { seen: 0, missed: 0 }
    e.seen++; if (!correct) e.missed++
    this.entries[z] = e; this.save()
  }
  reset() { this.entries = {}; try { this.storage?.removeItem(this.key) } catch { /* ignore */ } }
  /** Sampling weight: 1 for unseen or perfect elements, up to 6 for ones you always miss. */
  weight(z: number): number { const e = this.entries[z]; return !e || e.seen <= 0 ? 1 : 1 + 5 * e.missed / e.seen }
  get weakSpots() {
    return Object.entries(this.entries).filter(([, v]) => v.missed > 0).map(([z, v]) => ({ z: Number(z), missed: v.missed, seen: v.seen }))
      .sort((a, b) => b.missed - a.missed || b.seen - a.seen)
  }
}
function defaultStorage() { try { return typeof localStorage !== 'undefined' ? localStorage : null } catch { return null } }

const trendProps: [string, (e: Element) => number | null, string][] = [
  ['electronegativity', e => e.electronegativity, ''], ['first ionization energy', e => e.ionization, ' eV'],
  ['covalent radius', e => e.radiusCovalent, ' Å'], ['atomic mass', e => e.mass, ' u'],
  ['melting point', e => e.meltingPoint, ' K'], ['boiling point', e => e.boilingPoint, ' K'],
]

/** "[He] 2s2 2p4" → "[He] 2s² 2p⁴" */
export function prettyConfig(cfg: string): string {
  return cfg.split(' ').filter(Boolean).map(token => {
    if (token.startsWith('[')) return token
    const idx = [...token].findIndex(c => 'spdf'.includes(c))
    if (idx < 0) return token
    const head = token.slice(0, idx + 1), tail = token.slice(idx + 1)
    return head + (/^\d+$/.test(tail) ? superscript(Number(tail)) : tail)
  }).join(' ')
}

export class QuizEngine {
  pool: Element[]
  kinds: QuizKind[]
  constructor(maxZ: number, kinds: QuizKind[], public stats: QuizStats = new QuizStats(), public weighted = false) {
    this.pool = elements.filter(e => e.z <= maxZ)
    this.kinds = kinds.length ? kinds : ['Symbol → name']
  }

  pick(rng: RNG): Element {
    if (!this.weighted) return rng.pick(this.pool)
    const weights = this.pool.map(e => this.stats.weight(e.z))
    let r = rng.next() * weights.reduce((a, b) => a + b, 0)
    for (let i = 0; i < this.pool.length; i++) { r -= weights[i]; if (r < 0) return this.pool[i] }
    return this.pool[this.pool.length - 1]
  }

  next(rng: RNG, forced?: QuizKind): QuizQuestion {
    for (let i = 0; i < 40; i++) {
      const kind = forced ?? rng.pick(this.kinds)
      const q = this.make(kind, this.pick(rng), rng)
      if (q) return q
    }
    return this.make('Symbol → name', this.pool[0], rng)!
  }

  private shuffled(correct: string, distractors: string[], rng: RNG) {
    const opts = rng.shuffle([...new Set(distractors.filter(d => d !== correct))].sort()).slice(0, 3)
    opts.push(correct)
    const shuffled = rng.shuffle(opts)
    return { options: shuffled, correct: shuffled.indexOf(correct) }
  }
  private others(e: Element, rng: RNG) { return rng.shuffle(this.pool.filter(p => p.z !== e.z)).slice(0, 12) }

  make(kind: QuizKind, e: Element, rng: RNG): QuizQuestion | null {
    if (this.pool.length < 4) return null
    const o = this.others(e, rng)
    const base = { kind, z: e.z, answerZ: e.z }
    switch (kind) {
      case 'Symbol → name': {
        const s = this.shuffled(t(e.name), o.map(x => t(x.name)), rng)
        return { ...base, prompt: t('Which element has the symbol {symbol}?', { symbol: e.symbol }), ...s, explanation: e.nameOrigin ? t('{symbol} is {name}. {origin}', { symbol: e.symbol, name: t(e.name), origin: t(e.nameOrigin) }) : t('{symbol} is {name}.', { symbol: e.symbol, name: t(e.name) }) }
      }
      case 'Name → symbol': {
        const s = this.shuffled(e.symbol, o.map(x => x.symbol), rng)
        return { ...base, prompt: t('What is the symbol for {name}?', { name: t(e.name) }), ...s, explanation: t('{name} is {symbol}, atomic number {z}.', { name: t(e.name), symbol: e.symbol, z: e.z }) }
      }
      case 'Atomic number → name': {
        const s = this.shuffled(t(e.name), o.map(x => t(x.name)), rng)
        return { ...base, prompt: t('Which element has atomic number {z}?', { z: e.z }), ...s, explanation: t('Atomic number {z} is {name} ({symbol}).', { z: e.z, name: t(e.name), symbol: e.symbol }) }
      }
      case 'Name → atomic number': {
        const valid = new Set(this.pool.map(x => x.z))
        const near = [-4, -3, -2, -1, 1, 2, 3, 4].map(d => e.z + d).filter(z => valid.has(z)).map(String)
        const s = this.shuffled(String(e.z), near, rng)
        return { ...base, prompt: t('What is the atomic number of {name}?', { name: t(e.name) }), ...s, explanation: t('{name} has {z} protons, so its atomic number is {z}.', { name: t(e.name), z: e.z }) }
      }
      case 'Find it on the table': {
        const g = iupacGroup(e.z)
        return { ...base, prompt: t('Click {name} ({symbol}) on the periodic table.', { name: t(e.name), symbol: e.symbol }), options: [], correct: 0, explanation: g != null ? t('{name} is in group {group}, period {period}.', { name: t(e.name), group: g, period: e.period ?? '—' }) : t('{name} is in the f-block, period {period}.', { name: t(e.name), period: e.period ?? '—' }) }
      }
      case 'Element families': {
        const fam = familyInfo(e); if (!fam) return null
        const s = this.shuffled(t(fam.label), families.filter(f => f !== fam).map(f => t(f.label)), rng)
        return { ...base, prompt: t('What kind of element is {name}?', { name: t(e.name) }), ...s, explanation: t('{name} is one of the {family}.', { name: t(e.name), family: t(fam.label).toLowerCase() }) }
      }
      case 'Periodic trends': {
        const [name, f, unit] = rng.pick(trendProps)
        const a = f(e); if (a == null) return null
        const p = o.find(x => { const v = f(x); return v != null && Math.abs(v - a) > 0.08 * Math.max(Math.abs(v), Math.abs(a)) })
        if (!p) return null
        const b = f(p)!
        const higher = a > b ? e : p
        const lowerFirst = rng.bool()
        const answer = lowerFirst ? (a > b ? p : e) : higher
        const opts = rng.shuffle([t(e.name), t(p.name)])
        return { ...base, prompt: t(lowerFirst ? 'Which has the lower {property}: {a} or {b}?' : 'Which has the higher {property}: {a} or {b}?', { property: t(name), a: opts[0], b: opts[1] }), options: opts, correct: opts.indexOf(t(answer.name)), answerZ: answer.z,
          explanation: t(lowerFirst ? '{a} {va}{unit}, {b} {vb}{unit}, so {winner} has the lower {property}.' : '{a} {va}{unit}, {b} {vb}{unit}, so {winner} has the higher {property}.', { a: t(e.name), va: formatNumber(a), b: t(p.name), vb: formatNumber(b), unit, winner: t(answer.name), property: t(name) }) }
      }
      case 'Electron configurations': {
        const cfg = e.configuration; if (!cfg) return null
        if (this.pool.some(x => x.configuration === cfg && x.z !== e.z)) return null
        const shown = prettyConfig(cfg)
        const s = this.shuffled(t(e.name), o.map(x => t(x.name)), rng)
        return { ...base, prompt: t('Which element has the electron configuration {config}?', { config: shown }), ...s, explanation: t('{name} ({symbol}) is {config}.', { name: t(e.name), symbol: e.symbol, config: shown }) }
      }
    }
  }
}
