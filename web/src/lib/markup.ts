const sup: Record<string, string> = {}
const sub: Record<string, string> = {}
const zip = (a: string, b: string, into: Record<string, string>) => { const A = [...a], B = [...b]; A.forEach((c, i) => { into[c] = B[i] }) }
zip('0123456789+-=()', '⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾', sup)
zip('abcdefghijklmnoprstuvwxyz', 'ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻ', sup)
sup['−'] = '⁻'
zip('0123456789+-=()', '₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎', sub)
zip('aehijklmnoprstuvx', 'ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ', sub)
sub['−'] = '₋'

type Style = 'normal' | 'sub' | 'sup'
export interface Run { text: string; style: Style; italic: boolean; shift?: boolean }

/** Kalzium's text data uses a small BBCode-style markup: [sub], [sup], [i], [br]. */
export function markupRuns(raw: string): Run[] {
  const source = raw.replaceAll('ß', 'β')
  const out: Run[] = []
  let italic = false, style: Style = 'normal', last = 0
  const push = (text: string) => {
    if (!text) return
    if (style === 'normal') { out.push({ text, style, italic }); return }
    const table = style === 'sub' ? sub : sup
    for (const ch of text) out.push({ text: table[ch] ?? ch, style, italic, shift: table[ch] == null })
  }
  const re = /\[(\/?)(sub|sup|i|br)\]/gi
  for (let m; (m = re.exec(source));) {
    push(source.slice(last, m.index))
    const closing = m[1] === '/'
    switch (m[2].toLowerCase()) {
      case 'sub': style = closing ? 'normal' : 'sub'; break
      case 'sup': style = closing ? 'normal' : 'sup'; break
      case 'i': italic = !closing; break
      default: out.push({ text: '\n', style: 'normal', italic: false })
    }
    last = m.index + m[0].length
  }
  push(source.slice(last))
  return out
}

export const markupPlain = (raw: string): string => markupRuns(raw).map(r => r.text).join('')

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
/** HTML for display: sub/sup characters with no Unicode form fall back to <sub>/<sup>. */
export function markupHtml(raw: string): string {
  return markupRuns(raw).map(r => {
    let t = esc(r.text).replaceAll('\n', '<br>')
    if (r.shift) t = `<${r.style}>${t}</${r.style}>`
    return r.italic ? `<i>${t}</i>` : t
  }).join('')
}

const isDigit = (c: string) => c >= '0' && c <= '9'
const isLetter = (c: string) => /\p{L}/u.test(c)

/** Chemical formula with real subscripts and charges: "Fe[2+]" → Fe²⁺, "3 H2O" → 3 H₂O. */
export function formulaText(f: string): string {
  let out = '', prev = ' '
  const cs = [...f]
  for (let i = 0; i < cs.length; i++) {
    const c = cs[i]
    if (c === '[') {
      const close = cs.indexOf(']', i)
      if (close > i) {
        const inner = cs.slice(i + 1, close)
        if (inner.length && inner.every(ch => isDigit(ch) || ch === '+' || ch === '-')) {
          out += inner.map(ch => ch === '+' ? '⁺' : ch === '-' ? '⁻' : (sup[ch] ?? ch)).join('')
          i = close; prev = ']'; continue
        }
      }
    }
    if (isDigit(c) && (isLetter(prev) || prev === ')')) out += sub[c] ?? c; else out += c
    prev = isDigit(c) && (isLetter(prev) || prev === ')') ? 'a' : c    // digits after a subscript keep subscripting: C10H22
  }
  return out
}
