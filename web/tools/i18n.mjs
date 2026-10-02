// i18n codemod and scanner (Babel based).
//   node tools/i18n.mjs scan  <files...>   list user-visible strings per file
//   node tools/i18n.mjs wrap  <files...>   wrap JSX text and label-like attributes in t("…") (in place)
import { parse } from '@babel/parser'
import fs from 'node:fs'

const [mode, ...files] = process.argv.slice(2)
const ATTRS = new Set(['placeholder', 'title', 'aria-label', 'alt', 'label'])
const decode = s => s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&nbsp;/g, ' ').replace(/&middot;/g, '·')
const esc = s => JSON.stringify(s)
const prose = s => /[A-Za-zÀ-ɏ]{2}/.test(s) && /\s/.test(s.trim()) && !/^[\w./:#-]+$/.test(s) && !/^(rgb|hsl|#|M |\d)/.test(s) && !s.includes('px') && !/^[a-z]+( [a-z-]+)*$/.test(s)

function walk(node, fn, parent = null) {
  if (!node || typeof node.type !== 'string') return
  fn(node, parent)
  for (const k of Object.keys(node)) {
    if (k === 'loc' || k === 'tokens' || k === 'leadingComments' || k === 'trailingComments') continue
    const v = node[k]
    if (Array.isArray(v)) v.forEach(c => walk(c, fn, node)); else if (v && typeof v.type === 'string') walk(v, fn, node)
  }
}

let total = 0, mixedTotal = 0
for (const file of files) {
  const src = fs.readFileSync(file, 'utf8')
  const ast = parse(src, { sourceType: 'module', plugins: ['typescript', 'jsx'] })
  const edits = [], found = { text: [], attr: [], mixed: [], literal: [] }
  walk(ast.program, (n, p) => {
    if (n.type === 'JSXText') {
      const raw = n.value, core = decode(raw).replace(/\s+/g, ' ').trim()
      if (!/\p{L}/u.test(core)) return
      const siblings = (p?.children ?? [])
      const mixed = siblings.some(c => c.type === 'JSXExpressionContainer' && c.expression.type !== 'JSXEmptyExpression' && !(c.expression.type === 'CallExpression' && c.expression.callee.name === 't'))
        && siblings.filter(c => c.type === 'JSXText' && /\p{L}/u.test(c.value)).length >= 1 && siblings.some(c => c.type === 'JSXExpressionContainer' && c.expression.type !== 'JSXEmptyExpression')
      // text that sits next to {expression} children is flagged: it usually needs one sentence with placeholders
      const adjacentExpr = (() => { const i = siblings.indexOf(n); const a = siblings[i - 1], b = siblings[i + 1]; return [a, b].some(c => c && c.type === 'JSXExpressionContainer' && c.expression.type !== 'JSXEmptyExpression') })()
      if (adjacentExpr && mixed) { found.mixed.push(core); return }
      found.text.push(core)
      const lead = raw.match(/^\s*/)[0], trail = raw.match(/\s*$/)[0]
      edits.push({ start: n.start, end: n.end, text: `${lead}{t(${esc(core)})}${trail}` })
    } else if (n.type === 'JSXAttribute' && n.name.type === 'JSXIdentifier' && ATTRS.has(n.name.name) && n.value?.type === 'StringLiteral') {
      found.attr.push(n.value.value)
      edits.push({ start: n.value.start, end: n.value.end, text: `{t(${esc(n.value.value)})}` })
    } else if ((n.type === 'StringLiteral' || n.type === 'TemplateLiteral') && !['ImportDeclaration', 'JSXAttribute', 'ExportNamedDeclaration', 'ObjectProperty', 'TSLiteralType'].includes(p?.type) && !(p?.type === 'CallExpression' && p.callee.name === 't' && p.arguments[0] === n)) {
      const v = n.type === 'StringLiteral' ? n.value : '`' + src.slice(n.start + 1, n.end - 1) + '`'
      if (n.type === 'StringLiteral' ? prose(v) : (/[A-Za-z]{3,} [A-Za-z]{2,}/.test(v.replace(/\$\{[^}]*\}/g, '')))) found.literal.push(v)
    } else if (n.type === 'ObjectProperty' && n.value?.type === 'StringLiteral' && prose(n.value.value) && !['id', 'key', 'class', 'style', 'kind', 'value', 'type'].includes(n.key.name ?? n.key.value)) found.literal.push(`${n.key.name ?? n.key.value}: ${n.value.value}`)
  })
  const c = found.text.length + found.attr.length
  total += c; mixedTotal += found.mixed.length
  if (mode === 'scan' || process.env.SHOW) {
    console.log(`${String(c).padStart(4)} auto  ${String(found.mixed.length).padStart(3)} mixed  ${String(found.literal.length).padStart(3)} literals  ${file}`)
    if (process.env.SHOW) for (const [k, arr] of Object.entries(found)) if (k !== 'text' && k !== 'attr' || process.env.SHOW === 'all') for (const s of arr) console.log(`      ${k[0]}: ${s.slice(0, 120)}`)
  }
  if (mode === 'wrap' && edits.length) {
    let out = src
    for (const e of edits.sort((a, b) => b.start - a.start)) out = out.slice(0, e.start) + e.text + out.slice(e.end)
    if (!/from '(\.\.\/)+i18n'/.test(out)) {
      const depth = file.replace(/^src\//, '').split('/').length - 1
      const rel = depth === 0 ? './i18n' : '../'.repeat(depth) + 'i18n'
      out = out.replace(/^((?:import [^\n]*\n)+)/, `$1import { t } from '${rel}'\n`)
    }
    fs.writeFileSync(file, out); console.log(`wrapped ${edits.length} in ${file}`)
  }
}
console.log('TOTAL auto', total, 'mixed', mixedTotal)
