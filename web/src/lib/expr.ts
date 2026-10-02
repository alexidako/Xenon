import { t } from '../i18n'
/** Small arithmetic language: numbers (`,` or `.` decimals), variables, + − * / ^, parentheses and a few functions. */
export type Expr =
  | { k: 'num'; v: number } | { k: 'var'; n: string }
  | { k: 'un'; op: string; e: Expr } | { k: 'bin'; op: string; l: Expr; r: Expr }
  | { k: 'call'; f: string; e: Expr }

export function evalExpr(x: Expr, lookup: (name: string) => number): number {
  switch (x.k) {
    case 'num': return x.v
    case 'var': return lookup(x.n)
    case 'un': { const v = evalExpr(x.e, lookup); return x.op === '-' ? -v : v }
    case 'bin': {
      const a = evalExpr(x.l, lookup), b = evalExpr(x.r, lookup)
      switch (x.op) { case '+': return a + b; case '-': return a - b; case '*': return a * b; case '/': return a / b; default: return Math.pow(a, b) }
    }
    case 'call': {
      const v = evalExpr(x.e, lookup)
      switch (x.f.toLowerCase()) {
        case 'sqrt': return Math.sqrt(v); case 'ln': return Math.log(v); case 'log': return Math.log10(v)
        case 'exp': return Math.exp(v); case 'abs': return Math.abs(v); case 'sin': return Math.sin(v)
        case 'cos': return Math.cos(v); case 'tan': return Math.tan(v); case 'tanh': return Math.tanh(v)
        default: throw new Error(t('unknown function {f}', { f: x.f }))
      }
    }
  }
}

const isDigit = (c: string) => c >= '0' && c <= '9'
const isLetter = (c: string) => /\p{L}/u.test(c)

class P {
  i = 0
  constructor(readonly cs: string[]) {}
  get peek(): string | undefined { return this.cs[this.i] }
  expression(): Expr | null {
    let left = this.term(); if (!left) return null
    while (this.peek === '+' || this.peek === '-') {
      const op = this.peek; this.i++
      const r = this.term(); if (!r) return null
      left = { k: 'bin', op, l: left, r }
    }
    return left
  }
  term(): Expr | null {
    let left = this.unary(); if (!left) return null
    while (this.peek === '*' || this.peek === '/') {
      const op = this.peek; this.i++
      const r = this.unary(); if (!r) return null
      left = { k: 'bin', op, l: left, r }
    }
    return left
  }
  unary(): Expr | null {
    if (this.peek === '-' || this.peek === '+') {
      const op = this.peek; this.i++
      const e = this.unary(); return e ? { k: 'un', op, e } : null
    }
    return this.power()
  }
  power(): Expr | null {
    const base = this.primary(); if (!base) return null
    if (this.peek === '^') {
      this.i++
      const e = this.unary(); if (!e) return null       // right-associative, allows 10^-3
      return { k: 'bin', op: '^', l: base, r: e }
    }
    return base
  }
  primary(): Expr | null {
    const c = this.peek; if (c === undefined) return null
    if (isDigit(c) || c === '.') {
      let s = ''
      while (this.peek !== undefined && (isDigit(this.peek) || this.peek === '.')) { s += this.peek; this.i++ }
      const e = this.peek
      if ((e === 'e' || e === 'E') && this.i + 1 < this.cs.length && (isDigit(this.cs[this.i + 1]) || this.cs[this.i + 1] === '-')) {
        s += 'e'; this.i++
        if (this.peek === '-') { s += '-'; this.i++ }
        while (this.peek !== undefined && isDigit(this.peek)) { s += this.peek; this.i++ }
      }
      const v = Number(s)
      return s !== '' && /^(\d+\.?\d*|\.\d+)(e-?\d+)?$/.test(s) && Number.isFinite(v) ? { k: 'num', v } : null
    }
    if (isLetter(c) || c === '_') {
      let name = ''
      while (this.peek !== undefined && (isLetter(this.peek) || isDigit(this.peek) || this.peek === '_')) { name += this.peek; this.i++ }
      if (this.peek === '(') {
        this.i++
        const arg = this.expression(); if (!arg || (this.peek as string | undefined) !== ')') return null
        this.i++
        return { k: 'call', f: name, e: arg }
      }
      return { k: 'var', n: name }
    }
    if (c === '(') {
      this.i++
      const e = this.expression(); if (!e || this.peek !== ')') return null
      this.i++
      return e
    }
    return null
  }
}

export function parseExpr(text: string): Expr | null {
  const p = new P([...text.replaceAll(',', '.')].filter(c => !/\s/.test(c)))
  const e = p.expression()
  return e && p.i === p.cs.length ? e : null
}
