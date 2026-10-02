import { Element, elements, familyInfo, gridPosition, isotopesByElement, stateAt, discoveryYear, MatterState } from './element'
import { formatNumber } from './format'

/** Plain-language element search ("liquid at room temperature", "halogens discovered before 1850" …). Rule-based, offline. */
export interface QueryResult { matches: Element[]; description: string; unsupported?: boolean }

export type PropKey = 'affinity' | 'ionization' | 'covalent' | 'vdw' | 'melting' | 'boiling' | 'electronegativity' | 'mass'
interface Prop { key: PropKey; pattern: string; label: string; unit: string; value: (e: Element) => number | null }
const props: Prop[] = [
  { key: 'affinity', pattern: 'electron affinity', label: 'electron affinity', unit: 'eV', value: e => e.electronAffinity },
  { key: 'ionization', pattern: '(?:first )?(?:ionis|ioniz)ation(?: energy)?', label: 'ionization energy', unit: 'eV', value: e => e.ionization },
  { key: 'covalent', pattern: 'covalent radius', label: 'covalent radius', unit: 'Å', value: e => e.radiusCovalent },
  { key: 'vdw', pattern: '(?:van der waals|vdw|atomic) radius|radii|radius|size', label: 'radius', unit: 'Å', value: e => e.radiusVDW },
  { key: 'melting', pattern: 'melting (?:point|temperature)|melting', label: 'melting point', unit: 'K', value: e => e.meltingPoint },
  { key: 'boiling', pattern: 'boiling (?:point|temperature)|boiling', label: 'boiling point', unit: 'K', value: e => e.boilingPoint },
  { key: 'electronegativity', pattern: 'electronegativity|electronegative', label: 'electronegativity', unit: '', value: e => e.electronegativity },
  { key: 'mass', pattern: '(?:atomic )?(?:mass|weight)', label: 'atomic mass', unit: 'u', value: e => e.mass },
]
const byKey = (k: PropKey) => props.find(p => p.key === k)!
const isTemperature = (p: Prop) => p.key === 'melting' || p.key === 'boiling'

class Scan {
  constructor(public s: string) {}
  take(pattern: string): string[] | null {
    const m = new RegExp(pattern).exec(this.s)
    if (!m) return null
    const groups = Array.from({ length: m.length }, (_, i) => m[i] ?? '')
    this.s = this.s.slice(0, m.index) + ' ' + this.s.slice(m.index + m[0].length)
    return groups
  }
  has(pattern: string): boolean { return new RegExp(pattern).test(this.s) }
}

const num = '(-?\\d+(?:\\.\\d+)?)'
const unitPat = '(k|kelvin|°c|°|celsius|c|ev|u|å)?(?![a-z])'
const above = 'above|over|greater than|more than|higher than|larger than|bigger than|at least|exceeding|>=|>'
const below = 'below|under|less than|lower than|smaller than|at most|<=|<'
const aboveWords = above.split('|')

const countries: Record<string, string> = {
  germany: 'de', denmark: 'dk', spain: 'es', finland: 'fi', france: 'fr', italy: 'it', russia: 'ru', sweden: 'se', uk: 'uk',
  britain: 'uk', england: 'uk', 'united kingdom': 'uk', scotland: 'uk', us: 'us', usa: 'us', america: 'us', 'united states': 'us', japan: 'jp',
}
const unsupportedWords = ['density', 'dense', 'conductivity', 'conductor', 'price', 'cost', 'abundance in', 'crust', 'toxic', 'magnetic', 'color', 'colour', 'hardness', 'heat capacity', 'crystal structure']

const kelvin = (v: number, unit: string) => ['°c', '°', 'celsius', 'c'].includes(unit) ? v + 273.15 : v
const cap = (s: string) => s.replace(/\b\w/g, c => c.toUpperCase())

export const hasStableIsotope = (e: Element) => (isotopesByElement.get(e.z) ?? []).some(i => i.halfLife == null && i.abundance != null)

export function runQuery(raw: string, isStable: ((e: Element) => boolean) | null = hasStableIsotope): QueryResult | null {
  const t = new Scan(' ' + raw.toLowerCase().replaceAll('’', "'") + ' ')
  const filters: [string, (e: Element) => boolean][] = []
  let sort: { prop: Prop; descending: boolean; count: number } | null = null
  let recognised = false

  const w = unsupportedWords.find(x => t.has('\\b' + x))
  if (w && !props.some(p => t.has('\\b(?:' + p.pattern + ')\\b'))) {
    return { matches: [], unsupported: true, description: `This app has no “${w}” data. Try mass, melting/boiling point, electronegativity, ionization energy, radius, family, block, period, group, state or discovery.` }
  }

  // superlatives
  let g = t.take('\\b(?:the )?(?:top (\\d+) )?(highest|largest|biggest|greatest|most|heaviest|lowest|smallest|least|lightest)\\b(?: (\\d+))?')
  if (g) {
    const adj = g[2]
    const desc = ['highest', 'largest', 'biggest', 'greatest', 'most', 'heaviest'].includes(adj)
    const n = Number(g[1]) || Number(g[3]) || 3
    let prop: Prop | null = null
    if (adj === 'heaviest' || adj === 'lightest') prop = byKey('mass')
    for (const p of props) if (!prop && t.take('\\b(?:' + p.pattern + ')\\b')) prop = p
    if (!prop && ['largest', 'smallest', 'biggest'].includes(adj)) { prop = byKey('vdw'); t.take('\\b(?:atoms?|elements?)\\b') }
    if (prop) { sort = { prop, descending: desc, count: n }; recognised = true }
  }

  // families (longest names first so "alkaline earth" wins over "alkali")
  const fams: [string, string[], string][] = [
    ['alkaline[- ]earth(?: metals?)?', ['Alkaline_Earth'], 'alkaline earth metals'],
    ['alkali(?: metals?)?', ['Alkali_Earth'], 'alkali metals'],
    ['transition(?: metals?)?', ['Transition'], 'transition metals'],
    ['(?:post[- ]transition|other) metals?', ['Other_Metal'], 'other metals'],
    ['metalloids?|semi-?metals?', ['Metalloids'], 'metalloids'],
    ['non-?metals?', ['Non-Metal'], 'nonmetals'],
    ['halogens?', ['Halogen'], 'halogens'],
    ['noble gas(?:es)?', ['Noblegas'], 'noble gases'],
    ['lanthanides?|actinides?|rare[- ]earths?', ['Rare_Earth'], 'lanthanides & actinides'],
    ['metals?', ['Alkali_Earth', 'Alkaline_Earth', 'Transition', 'Other_Metal', 'Rare_Earth'], 'metals'],
  ]
  for (const [pat, keys, label] of fams) {
    if (t.take('\\b(?:' + pat + ')\\b')) { filters.push([label, e => keys.includes(familyInfo(e)?.key ?? '')]); recognised = true; break }
  }

  // states of matter
  g = t.take('\\b(solid|liquid|gas|gaseous)(?:e?s)?\\b(?: at (?:(?:room temp(?:erature)?)|(stp|standard (?:conditions|temperature))|' + num + ' ?' + unitPat + '))?')
  if (g) {
    let T = 298.15
    if (g[2]) T = 273.15
    else if (g[3]) { const v = Number(g[3]); T = g[4] === '°f' ? (v - 32) * 5 / 9 + 273.15 : kelvin(v, g[4]) }
    const want: MatterState = g[1] === 'solid' ? 'Solid' : g[1] === 'liquid' ? 'Liquid' : 'Gas'
    filters.push([`${want === 'Gas' ? 'gases' : want.toLowerCase() + 's'} at ${formatNumber(T)} K`, e => stateAt(e, T) === want])
    recognised = true
  }

  const addCompare = (p: Prop, op: string, v: number, unit: string) => {
    const x = isTemperature(p) ? kelvin(v, unit) : v
    if (aboveWords.includes(op)) filters.push([`${p.label} > ${formatNumber(x)} ${p.unit}`, e => (p.value(e) ?? -Infinity) > x])
    else filters.push([`${p.label} < ${formatNumber(x)} ${p.unit}`, e => (p.value(e) ?? Infinity) < x])
    recognised = true
  }
  g = t.take('\\b(heavier|lighter) than ' + num)
  if (g) addCompare(byKey('mass'), g[1] === 'heavier' ? '>' : '<', Number(g[2]), '')
  for (const p of props) {
    for (let m; (m = t.take('\\b(?:' + p.pattern + ')\\b(?: is| of| at)? ?(' + above + '|' + below + ') ?' + num + ' ?' + unitPat));) addCompare(p, m[1], Number(m[2]), m[3])
    const b = t.take('\\b(?:' + p.pattern + ')\\b (?:is |of )?between ' + num + ' ?' + unitPat + ' and ' + num + ' ?' + unitPat)
    if (b) {
      const lo = isTemperature(p) ? kelvin(Number(b[1]), b[2]) : Number(b[1])
      const hi = isTemperature(p) ? kelvin(Number(b[3]), b[4] || b[2]) : Number(b[3])
      filters.push([`${p.label} ${formatNumber(lo)}–${formatNumber(hi)} ${p.unit}`, e => { const v = p.value(e); return v != null && v >= Math.min(lo, hi) && v <= Math.max(lo, hi) }])
      recognised = true
    }
  }

  g = t.take('\\b([spdf])[- ]?block\\b')
  if (g) { const b = g[1]; filters.push([`${b}-block`, e => e.block === b]); recognised = true }
  g = t.take('\\bperiod (\\d+)\\b')
  if (g) { const n = Number(g[1]); filters.push([`period ${n}`, e => e.period === n]); recognised = true }
  g = t.take('\\bgroup (\\d+)\\b')
  if (g) { const n = Number(g[1]); filters.push([`group ${n}`, e => { const p = gridPosition(e.z); return p.row < 8 && p.col + 1 === n }]); recognised = true }

  // discovery
  g = t.take('\\b(?:discovered|found|isolated|identified)? ?(before|prior to|after|since|until|by|in|during) (?:the year )?(\\d{3,4})\\b')
  if (g) {
    const y = Number(g[2]), yr = (e: Element) => discoveryYear(e)
    switch (g[1]) {
      case 'before': case 'prior to': filters.push([`discovered before ${y}`, e => (yr(e) ?? 99999) < y && (yr(e) ?? 0) > 0]); break
      case 'after': filters.push([`discovered after ${y}`, e => (yr(e) ?? 0) > y]); break
      case 'since': filters.push([`discovered since ${y}`, e => (yr(e) ?? 0) >= y]); break
      case 'until': case 'by': filters.push([`discovered by ${y}`, e => (yr(e) ?? 99999) <= y && (yr(e) ?? 0) > 0]); break
      default: filters.push([`discovered in ${y}`, e => yr(e) === y])
    }
    recognised = true
  }
  if (t.take('\\b(?:known since antiquity|ancient|prehistoric)\\b')) {
    filters.push(['known since antiquity', e => discoveryYear(e) === 0 || e.discoveryCountry.includes('ancient')]); recognised = true
  }
  g = t.take("\\b(?:discovered|found|isolated) (?:in|by|from) ([a-z.' ]+?)(?= and | with | that | which |$| in )")
  if (g) {
    const who = g[1].trim()
    const code = Object.hasOwn(countries, who) ? countries[who] : undefined
    if (code) { filters.push([`discovered in ${cap(who)}`, e => e.discoveryCountry.includes(code)]); recognised = true }
    else if (who.length >= 3) { filters.push([`discovered by ${cap(who)}`, e => e.discoverers.some(d => d.toLowerCase().includes(who))]); recognised = true }
  }

  g = t.take('\\boxidation (?:state|number) ([+-]?\\d+)\\b')
  if (g) { const n = Number(g[1].replace('+', '')); filters.push([`oxidation state ${n > 0 ? '+' : ''}${n}`, e => e.oxidation.includes(n)]); recognised = true }

  if (isStable) {
    if (t.take('\\b(?:radioactive|unstable)\\b')) { filters.push(['radioactive (no stable isotope)', e => !isStable(e)]); recognised = true }
    else if (t.take('\\b(?:stable|non-?radioactive)\\b')) { filters.push(['has a stable isotope', e => isStable(e)]); recognised = true }
  }

  g = t.take('\\b(?:starting|starts|beginning|begins) with (?:the letter )?([a-z])\\b')
  if (g) { const c = g[1]; filters.push([`name starts with ${c.toUpperCase()}`, e => e.name.toLowerCase().startsWith(c)]); recognised = true }

  if (!recognised) return null

  let list = elements.filter(e => filters.every(f => f[1](e)))
  const parts = filters.map(f => f[0])
  if (sort) {
    const s = sort
    list = list.filter(e => s.prop.value(e) != null).sort((a, b) => {
      const x = s.prop.value(a) ?? 0, y = s.prop.value(b) ?? 0
      if (x === y) return a.z - b.z
      return s.descending ? y - x : x - y
    }).slice(0, s.count)
    parts.unshift(`${s.descending ? 'highest' : 'lowest'} ${s.prop.label} (top ${s.count})`)
  }
  return { matches: list, description: parts.join(' · ') }
}
