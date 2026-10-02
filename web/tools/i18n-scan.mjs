// Lists user-visible strings: JSX text, label-like JSX attributes, and other string literals that look like prose.
import ts from 'typescript'
import fs from 'node:fs'
import path from 'node:path'

const ATTRS = new Set(['placeholder', 'title', 'aria-label', 'alt', 'label', 'hint'])
const files = process.argv.slice(2)
const decode = s => s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&nbsp;/g, ' ')
const looksLikeProse = s => /[A-Za-zÀ-ɏ]{2}/.test(s) && /\s/.test(s.trim()) && !/^[\w./:#-]+$/.test(s) && !/^(rgb|hsl|#|M |\d)/.test(s) && !s.includes('px') && !/^[a-z]+( [a-z-]+)*$/.test(s) // lower-case class lists are skipped

let total = 0
for (const file of files) {
  const src = fs.readFileSync(file, 'utf8')
  const sf = ts.createSourceFile(file, src, ts.ScriptTarget.ES2022, true, file.endsWith('x') ? ts.ScriptKind.TSX : ts.ScriptKind.TS)
  const found = { jsxText: [], attr: [], literal: [] }
  const visit = n => {
    if (ts.isJsxText(n)) { const t = decode(n.getText()).replace(/\s+/g, ' ').trim(); if (/\p{L}/u.test(t)) found.jsxText.push(t) }
    else if (ts.isJsxAttribute(n) && ATTRS.has(n.name.getText()) && n.initializer && ts.isStringLiteral(n.initializer)) found.attr.push(n.initializer.text)
    else if ((ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) && !ts.isImportDeclaration(n.parent) && !ts.isJsxAttribute(n.parent) && !ts.isExternalModuleReference(n.parent)) {
      if (n.parent && ts.isPropertyAssignment(n.parent) && n.parent.name === n) { /* object key */ }
      else if (looksLikeProse(n.text)) found.literal.push(n.text)
    } else if (ts.isTemplateExpression(n)) { const t = n.getText(); if (/[A-Za-z]{3,} [A-Za-z]{2,}/.test(t.replace(/\$\{[^}]*\}/g, ''))) found.literal.push('`' + t.slice(1, -1) + '`') }
    ts.forEachChild(n, visit)
  }
  visit(sf)
  const c = found.jsxText.length + found.attr.length + found.literal.length
  total += c
  console.log(`${String(c).padStart(4)}  ${file}  (text ${found.jsxText.length}, attrs ${found.attr.length}, literals ${found.literal.length})`)
  if (process.env.SHOW) for (const k of ['jsxText', 'attr', 'literal']) for (const s of found[k]) console.log(`        ${k[0]}: ${s.slice(0, 110)}`)
}
console.log('TOTAL', total)
