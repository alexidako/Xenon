/** Balances chemical equations such as `aCH3CH2OH + bO2 -> cH2O + dCO2` (port of Kalzium's "eqchem" solver). */
export class SolverError extends Error {
  constructor(readonly kind: 'parse' | 'notFound', message = '') { super(message || kind) }
}

export type Coefficient = { k: 'number'; v: number } | { k: 'variable'; c: string }
export interface Term { coefficient: Coefficient; atoms: Map<string, number>; charge: number; text: string }
export interface Entry { coefficient: number; term: Term }
export interface Balanced { left: Entry[]; right: Entry[] }
export type Result<T> = { ok: true; value: T } | { ok: false; error: SolverError }

const isDigit = (c: string) => c >= '0' && c <= '9'
const isUpper = (c: string) => c >= 'A' && c <= 'Z'
const isLower = (c: string) => c >= 'a' && c <= 'z'

export function solve(input: string, isElement: (s: string) => boolean): Result<string> {
  const r = solveStructured(input, isElement)
  if (!r.ok) return r
  const fill = (es: Entry[]) => es.map(e => (e.coefficient === 1 ? '' : `${e.coefficient} `) + e.term.text).join(' + ')
  return { ok: true, value: fill(r.value.left) + ' -> ' + fill(r.value.right) }
}

export function solveStructured(input: string, isElement: (s: string) => boolean): Result<Balanced> {
  const cleaned = input.replaceAll('→', '->').replaceAll(' ', '')
  const sides = cleaned.split('->')
  if (sides.length !== 2) return { ok: false, error: new SolverError('parse', 'missing or duplicate arrow') }
  try {
    const left = sides[0] === '' ? [] : splitTerms(sides[0]).map(t => parseTerm(t, isElement))
    const right = sides[1] === '' ? [] : splitTerms(sides[1]).map(t => parseTerm(t, isElement))
    if (!left.length || !right.length) return { ok: false, error: new SolverError('parse', 'both sides need at least one molecule') }

    const letters = [...new Set([...left, ...right].flatMap(t => t.coefficient.k === 'variable' ? [t.coefficient.c] : []))].sort()
    const index = new Map(letters.map((c, i) => [c, i]))
    const n = letters.length

    const keys = new Set<string>()
    for (const t of [...left, ...right]) for (const k of t.atoms.keys()) keys.add(k)
    const rows: Frac[][] = []
    for (const key of [...[...keys].sort(), '\0charge']) {
      const row: Frac[] = Array.from({ length: n + 1 }, () => frac(0n))
      for (const [side, sign] of [[left, 1], [right, -1]] as [Term[], number][]) {
        for (const t of side) {
          const count = key === '\0charge' ? t.charge : (t.atoms.get(key) ?? 0)
          if (count === 0) continue
          if (t.coefficient.k === 'number') row[n] = sub(row[n], frac(BigInt(sign * count * t.coefficient.v)))
          else { const i = index.get(t.coefficient.c)!; row[i] = add(row[i], frac(BigInt(sign * count))) }
        }
      }
      rows.push(row)
    }
    const solution = solveIntegers(rows, n)
    if (!solution) return { ok: false, error: new SolverError('notFound') }
    const entries = (ts: Term[]): Entry[] => ts.map(t => ({ coefficient: t.coefficient.k === 'number' ? t.coefficient.v : solution[index.get(t.coefficient.c)!], term: t }))
    return { ok: true, value: { left: entries(left), right: entries(right) } }
  } catch (e) {
    if (e instanceof SolverError) return { ok: false, error: e }
    return { ok: false, error: new SolverError('parse', String(e)) }
  }
}

/** Split on `+` that is not inside brackets (charges are written like `[2+]`). */
export function splitTerms(s: string): string[] {
  const out: string[] = []; let cur = '', depth = 0
  for (const ch of s) {
    if (ch === '[') depth++; else if (ch === ']') depth--
    if (depth < 0) throw new SolverError('parse', 'unbalanced brackets')
    if (ch === '+' && depth === 0) { out.push(cur); cur = '' } else cur += ch
  }
  if (depth !== 0) throw new SolverError('parse', 'unbalanced brackets')
  out.push(cur)
  if (out.some(t => t === '')) throw new SolverError('parse', 'empty molecule')
  return out
}

export function parseTerm(s: string, isElement: (s: string) => boolean): Term {
  let chars = [...s]
  let coefficient: Coefficient = { k: 'number', v: 1 }
  if (chars.length && isDigit(chars[0])) {
    let digits = ''
    while (chars.length && isDigit(chars[0])) { digits += chars.shift()! }
    const v = Number(digits)
    if (!Number.isSafeInteger(v)) throw new SolverError('parse', 'coefficient too large')
    coefficient = { k: 'number', v }
  } else if (chars.length >= 2 && isLower(chars[0]) && (isUpper(chars[1]) || chars[1] === '(')) {
    coefficient = { k: 'variable', c: chars.shift()! }
  }
  let charge = 0
  let formulaChars = chars
  const open = chars.indexOf('[')
  if (open >= 0) {
    if (chars[chars.length - 1] !== ']') throw new SolverError('parse', `bad charge in ${s}`)
    const inner = chars.slice(open + 1, chars.length - 1).join('')
    const hasPlus = inner.includes('+'), hasMinus = inner.includes('-')
    if (hasPlus === hasMinus) throw new SolverError('parse', `bad charge in ${s}`)
    const digits = [...inner].filter(isDigit).join('')
    charge = (hasMinus ? -1 : 1) * (digits ? Number(digits) : 1)
    formulaChars = chars.slice(0, open)
  }
  if (!formulaChars.length) throw new SolverError('parse', `missing formula in ${s}`)
  const pos = { i: 0 }
  const atoms = parseGroup(formulaChars, pos, isElement, true)
  if (pos.i !== formulaChars.length) throw new SolverError('parse', `unexpected character in ${s}`)
  return { coefficient, atoms, charge, text: chars.join('') }
}

function parseGroup(c: string[], pos: { i: number }, isElement: (s: string) => boolean, top: boolean): Map<string, number> {
  const atoms = new Map<string, number>()
  while (pos.i < c.length) {
    let group: Map<string, number>
    if (isUpper(c[pos.i])) {
      let sym = c[pos.i]; pos.i++
      while (pos.i < c.length && isLower(c[pos.i])) { sym += c[pos.i]; pos.i++ }
      if (!isElement(sym)) throw new SolverError('parse', `unknown element ${sym}`)
      group = new Map([[sym, 1]])
    } else if (c[pos.i] === '(') {
      pos.i++
      group = parseGroup(c, pos, isElement, false)
      if (pos.i >= c.length || c[pos.i] !== ')') throw new SolverError('parse', 'missing )')
      pos.i++
    } else if (c[pos.i] === ')') {
      if (top) throw new SolverError('parse', 'unexpected )')
      return atoms
    } else throw new SolverError('parse', `unexpected '${c[pos.i]}'`)
    let digits = ''
    while (pos.i < c.length && isDigit(c[pos.i])) { digits += c[pos.i]; pos.i++ }
    const mult = digits ? Number(digits) : 1
    if (!Number.isSafeInteger(mult)) throw new SolverError('parse', 'count too large')
    for (const [k, v] of group) atoms.set(k, (atoms.get(k) ?? 0) + v * mult)
  }
  if (!top) throw new SolverError('parse', 'missing )')
  return atoms
}

// MARK: exact rationals

export interface Frac { n: bigint; d: bigint }
const gcd = (a: bigint, b: bigint): bigint => { a = a < 0n ? -a : a; b = b < 0n ? -b : b; while (b) [a, b] = [b, a % b]; return a }
export function frac(n: bigint, d = 1n): Frac {
  const g = gcd(n, d) || 1n; const s = d < 0n ? -1n : 1n
  return { n: s * n / g, d: s * d / g }
}
const add = (a: Frac, b: Frac) => frac(a.n * b.d + b.n * a.d, a.d * b.d)
const sub = (a: Frac, b: Frac) => frac(a.n * b.d - b.n * a.d, a.d * b.d)
const mul = (a: Frac, b: Frac) => frac(a.n * b.n, a.d * b.d)
const div = (a: Frac, b: Frac) => frac(a.n * b.d, a.d * b.n)
const isZero = (a: Frac) => a.n === 0n

/** Rows are [a1 … an | rhs]. Returns the smallest positive integer solution, if any. */
export function solveIntegers(input: Frac[][], n: number): number[] | null {
  if (n === 0) return input.every(r => isZero(r[0])) ? [] : null
  const m = input.map(r => r.slice())
  const pivotCols: number[] = []
  let r = 0
  for (let col = 0; col < n && r < m.length; col++) {
    let p = -1
    for (let i = r; i < m.length; i++) if (!isZero(m[i][col])) { p = i; break }
    if (p < 0) continue
    ;[m[r], m[p]] = [m[p], m[r]]
    const inv = m[r][col]
    m[r] = m[r].map(x => div(x, inv))
    for (let i = 0; i < m.length; i++) {
      if (i === r || isZero(m[i][col])) continue
      const f = m[i][col]
      m[i] = m[i].map((x, j) => sub(x, mul(f, m[r][j])))
    }
    pivotCols.push(col); r++
  }
  for (let i = r; i < m.length; i++) if (!isZero(m[i][n])) return null
  const free = Array.from({ length: n }, (_, i) => i).filter(i => !pivotCols.includes(i))
  if (free.length > 3) return null

  const evaluate = (fv: number[]): number[] | null => {
    const x: Frac[] = Array.from({ length: n }, () => frac(0n))
    free.forEach((col, k) => { x[col] = frac(BigInt(fv[k])) })
    for (let row = 0; row < pivotCols.length; row++) {
      let v = m[row][n]
      free.forEach((fc, k) => { v = sub(v, mul(m[row][fc], frac(BigInt(fv[k])))) })
      x[pivotCols[row]] = v
    }
    const out: number[] = []
    for (const v of x) { if (v.d !== 1n || v.n <= 0n || v.n > 1_000_000n) return null; out.push(Number(v.n)) }
    return out
  }
  if (!free.length) return evaluate([])
  const limit = free.length === 1 ? 400 : free.length === 2 ? 40 : 14
  let best: number[] | null = null, bestSum = Infinity
  const search = (depth: number, vals: number[]) => {
    if (depth === free.length) {
      const sol = evaluate(vals)
      if (sol) { const s = sol.reduce((a, b) => a + b, 0); if (s < bestSum) { best = sol; bestSum = s } }
      return
    }
    for (let v = 1; v <= limit; v++) search(depth + 1, [...vals, v])
  }
  search(0, [])
  return best
}
