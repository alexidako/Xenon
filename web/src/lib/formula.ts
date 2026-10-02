import { Element, elementBySymbol } from './element'

export interface ElementCount { element: Element; count: number }
export const countMass = (c: ElementCount) => (c.element.mass ?? 0) * c.count

export const builtInAliases: Record<string, string> = { Et: 'C2H5', Me: 'CH3', Ph: 'C6H5' }
const aliasKey = 'xenon.userAliases'
export function userAliases(): Record<string, string> {
  try { return JSON.parse(localStorage.getItem(aliasKey) ?? '{}') } catch { return {} }
}
export function setUserAliases(a: Record<string, string>) { try { localStorage.setItem(aliasKey, JSON.stringify(a)) } catch { /* ignore */ } }
export const allAliases = () => ({ ...builtInAliases, ...userAliases() })

const isUpper = (c: string) => c >= 'A' && c <= 'Z'
const isLower = (c: string) => c >= 'a' && c <= 'z'
const isDigit = (c: string) => c >= '0' && c <= '9'

function expand(s: string): string {
  const aliases = allAliases()
  const cs = [...s]; let out = '', i = 0
  while (i < cs.length) {
    if (isUpper(cs[i])) {
      let tok = cs[i]; i++
      if (i < cs.length && isLower(cs[i])) { tok += cs[i]; i++ }
      if (elementBySymbol.has(tok)) out += tok
      else if (Object.hasOwn(aliases, tok)) out += '(' + aliases[tok] + ')'
      else out += tok
    } else { out += cs[i]; i++ }
  }
  return out
}

class Parser {
  i = 0
  constructor(readonly cs: string[]) {}
  submolecule(): [Element, number][] | null {
    const result: [Element, number][] = []
    for (let t = this.term(); t; t = this.term()) result.push(...t)
    return result
  }
  term(): [Element, number][] | null {
    const { cs } = this
    if (this.i >= cs.length) return null
    let group: [Element, number][]
    if (isUpper(cs[this.i])) {
      let sym = cs[this.i]; this.i++
      if (this.i < cs.length && isLower(cs[this.i])) { sym += cs[this.i]; this.i++ }
      const e = elementBySymbol.get(sym)
      if (!e) { this.i = cs.length + 1; return null }          // poison: unknown symbol
      group = [[e, 1]]
    } else if (cs[this.i] === '(') {
      this.i++
      const inner = this.submolecule()
      if (!inner || this.i >= cs.length || cs[this.i] !== ')') { this.i = cs.length + 1; return null }
      this.i++
      group = inner
    } else return null
    let digits = ''
    while (this.i < cs.length && isDigit(cs[this.i])) { digits += cs[this.i]; this.i++ }
    if (digits) {
      const n = Number(digits)
      if (!(n > 0 && n <= 100_000)) { this.i = cs.length + 1; return null }     // "O0" is not a formula
      group = group.map(([e, c]) => [e, c * n])
    }
    return group
  }
}

/** Parses chemical formulas such as `Ca(OH)2`, `Al2(SO4)3` or `EtOH` (with aliases). Returns null for invalid input. */
export function parseFormula(formula: string): ElementCount[] | null {
  let expanded = expand([...formula.replaceAll('#', '')].filter(c => !/\s/.test(c)).join(''))
  expanded = expanded.replaceAll('[', '(').replaceAll(']', ')')
  if (!expanded) return null
  const p = new Parser([...expanded])
  const list = p.submolecule()
  if (!list || p.i !== p.cs.length || !list.length) return null
  const merged: ElementCount[] = []
  for (const [e, n] of list) {
    const m = merged.find(x => x.element === e)
    if (m) m.count += n; else merged.push({ element: e, count: n })
  }
  return merged
}

export const molarMass = (f: string): number | null => {
  const p = parseFormula(f)
  return p ? p.reduce((s, c) => s + countMass(c), 0) : null
}
