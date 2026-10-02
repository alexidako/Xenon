// Collects every English string the app can show: t("…") / tc("ctx","…") calls plus label-like literals
// (option values, table headings, notes) that are translated at display time.  Writes tools/i18n/keys.json.
import { parse } from '@babel/parser'
import fs from 'node:fs'
import path from 'node:path'

const root = 'src'
const files = []
const walkDir = d => { for (const f of fs.readdirSync(d)) { const p = path.join(d, f); if (fs.statSync(p).isDirectory()) { if (!['data', 'i18n'].includes(f)) walkDir(p) } else if (/\.(ts|tsx)$/.test(f) && !/\.test\./.test(f)) files.push(p) } }
walkDir(root)

const noise = s => /\\[bdsw(]|\(\?:|<\?xml|<\/|<html|<style|=\$\{|px\b|^rgb|^hsl|^#|^[A-Z][a-z]?\d?:? \[|^\s*$|\u0000|^[a-z-]+( [a-z-]+)*$|^M |^[\w./:#-]+$|^\{|^\d/.test(s)
const prose = s => /[A-Za-zÀ-ɏ]{2}/.test(s) && !noise(s)
const keys = new Map()   // key -> [files]
const add = (k, f, kind) => { if (!k || !k.trim()) return; const e = keys.get(k) ?? { files: new Set(), kinds: new Set() }; e.files.add(path.basename(f)); e.kinds.add(kind); keys.set(k, e) }
const walk = (n, fn, p = null) => { if (!n || typeof n.type !== 'string') return; fn(n, p); for (const k of Object.keys(n)) { if (k === 'loc' || k === 'tokens') continue; const v = n[k]; if (Array.isArray(v)) v.forEach(c => walk(c, fn, n)); else if (v && typeof v.type === 'string') walk(v, fn, n) } }

for (const file of files) {
  const src = fs.readFileSync(file, 'utf8')
  const ast = parse(src, { sourceType: 'module', plugins: ['typescript', 'jsx'] })
  walk(ast.program, (n, p) => {
    if (n.type === 'CallExpression' && n.callee.type === 'Identifier' && (n.callee.name === 't' || n.callee.name === 'tc')) {
      const args = n.arguments
      if (n.callee.name === 't' && args[0]?.type === 'StringLiteral') add(args[0].value, file, 'call')
      else if (n.callee.name === 't' && args[0]?.type === 'TemplateLiteral' && args[0].expressions.length === 0) add(args[0].quasis[0].value.cooked, file, 'call')
      else if (n.callee.name === 'tc' && args[0]?.type === 'StringLiteral' && args[1]?.type === 'StringLiteral') add(`${args[0].value}|${args[1].value}`, file, 'ctx')
    } else if (n.type === 'StringLiteral' && !['ImportDeclaration', 'ExportNamedDeclaration', 'JSXAttribute', 'TSLiteralType', 'TSEnumMember'].includes(p?.type)) {
      const isTCall = p?.type === 'CallExpression' && p.callee.name === 't'
      if (!isTCall && prose(n.value) && /\s|[A-Z]/.test(n.value)) add(n.value, file, 'literal')
    } else if (n.type === 'TemplateLiteral' && n.expressions.length === 0 && p?.type !== 'CallExpression') {
      const v = n.quasis[0].value.cooked; if (prose(v) && /\s/.test(v)) add(v, file, 'literal')
    } else if (n.type === 'JSXText') {
      const v = n.value.replace(/\s+/g, ' ').trim(); if (/\p{L}{2}/u.test(v)) add(v, file, 'jsx')
    }
  })
}
const out = Object.fromEntries([...keys.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => [k, { files: [...v.files], kinds: [...v.kinds] }]))
fs.writeFileSync('tools/i18n/keys.json', JSON.stringify(out, null, 1))
const calls = Object.values(out).filter(v => v.kinds.includes('call') || v.kinds.includes('ctx')).length
console.log(`${Object.keys(out).length} candidate keys (${calls} from t()/tc() calls, the rest label-like literals)`)
