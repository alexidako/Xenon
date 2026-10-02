import { Element, elements, families, familyInfo, iupacGroup } from './element'
import { formatNumber } from './format'
import { superscript } from './config'

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
        const s = this.shuffled(e.name, o.map(x => x.name), rng)
        return { ...base, prompt: `Which element has the symbol ${e.symbol}?`, ...s, explanation: `${e.symbol} is ${e.name}${e.nameOrigin ? '. ' + e.nameOrigin : ''}.` }
      }
      case 'Name → symbol': {
        const s = this.shuffled(e.symbol, o.map(x => x.symbol), rng)
        return { ...base, prompt: `What is the symbol for ${e.name}?`, ...s, explanation: `${e.name} is ${e.symbol}, atomic number ${e.z}.` }
      }
      case 'Atomic number → name': {
        const s = this.shuffled(e.name, o.map(x => x.name), rng)
        return { ...base, prompt: `Which element has atomic number ${e.z}?`, ...s, explanation: `Atomic number ${e.z} is ${e.name} (${e.symbol}).` }
      }
      case 'Name → atomic number': {
        const valid = new Set(this.pool.map(x => x.z))
        const near = [-4, -3, -2, -1, 1, 2, 3, 4].map(d => e.z + d).filter(z => valid.has(z)).map(String)
        const s = this.shuffled(String(e.z), near, rng)
        return { ...base, prompt: `What is the atomic number of ${e.name}?`, ...s, explanation: `${e.name} has ${e.z} protons, so its atomic number is ${e.z}.` }
      }
      case 'Find it on the table': {
        const g = iupacGroup(e.z)
        return { ...base, prompt: `Click ${e.name} (${e.symbol}) on the periodic table.`, options: [], correct: 0, explanation: `${e.name} is in ${g != null ? `group ${g}` : 'the f-block'}, period ${e.period ?? '—'}.` }
      }
      case 'Element families': {
        const fam = familyInfo(e); if (!fam) return null
        const s = this.shuffled(fam.label, families.filter(f => f !== fam).map(f => f.label), rng)
        return { ...base, prompt: `What kind of element is ${e.name}?`, ...s, explanation: `${e.name} is one of the ${fam.label.toLowerCase()}.` }
      }
      case 'Periodic trends': {
        const [name, f, unit] = rng.pick(trendProps)
        const a = f(e); if (a == null) return null
        const p = o.find(x => { const v = f(x); return v != null && Math.abs(v - a) > 0.08 * Math.max(Math.abs(v), Math.abs(a)) })
        if (!p) return null
        const b = f(p)!
        const higher = a > b ? e : p
        const lowerFirst = rng.bool()
        const ask = lowerFirst ? 'lower' : 'higher'
        const answer = lowerFirst ? (a > b ? p : e) : higher
        const opts = rng.shuffle([e.name, p.name])
        return { ...base, prompt: `Which has the ${ask} ${name}: ${opts[0]} or ${opts[1]}?`, options: opts, correct: opts.indexOf(answer.name), answerZ: answer.z,
          explanation: `${e.name} ${formatNumber(a)}${unit}, ${p.name} ${formatNumber(b)}${unit}, so ${answer.name} has the ${ask} ${name}.` }
      }
      case 'Electron configurations': {
        const cfg = e.configuration; if (!cfg) return null
        if (this.pool.some(x => x.configuration === cfg && x.z !== e.z)) return null
        const shown = prettyConfig(cfg)
        const s = this.shuffled(e.name, o.map(x => x.name), rng)
        return { ...base, prompt: `Which element has the electron configuration ${shown}?`, ...s, explanation: `${e.name} (${e.symbol}) is ${shown}.` }
      }
    }
  }
}
