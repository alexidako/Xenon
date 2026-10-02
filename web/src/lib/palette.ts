import { elements } from './element'
import { reference } from './reference'
import { moleculeLibrary, formulaOf } from './molecule'
import { formulaText } from './markup'
import { ScreenId, screens } from './screens'
import { t } from '../i18n'

export type PaletteTarget =
  | { kind: 'screen'; id: ScreenId } | { kind: 'element'; z: number } | { kind: 'glossary'; name: string }
  | { kind: 'equipment'; name: string } | { kind: 'molecule'; name: string }
export interface PaletteItem { title: string; subtitle: string; icon: string; target: PaletteTarget; score: number; id: string }

/** 0 = no match; higher is better. */
export function score(text: string, q: string): number {
  const t = text.toLowerCase()
  if (t === q) return 100
  if (t.startsWith(q)) return 80
  if (t.split(/[^\p{L}\p{N}]+/u).some(w => w && w.startsWith(q))) return 60
  if (t.includes(q)) return 40
  return 0
}

export function searchPalette(raw: string, limit = 14): PaletteItem[] {
  const q = raw.trim().toLowerCase()
  const out: PaletteItem[] = []
  const add = (title: string, subtitle: string, icon: string, target: PaletteTarget, s: number) =>
    out.push({ title, subtitle, icon, target, score: s, id: JSON.stringify(target) })

  for (const s of Object.values(screens)) {
    const best = Math.max(...[s.title, t(s.title), ...s.aliases].map(x => q ? score(x, q) : 30))
    if (best > 0) add(t(s.title), t('Go to screen'), s.icon, { kind: 'screen', id: s.id }, q ? best + 5 : 30)
  }
  if (!q) return out.slice(0, limit)

  for (const e of elements) {
    let best = Math.max(score(e.name, q), score(t(e.name), q), score(e.symbol, q) === 100 ? 95 : 0)
    if (String(e.z) === q) best = Math.max(best, 95)
    if (best > 0) add(`${t(e.name)} (${e.symbol})`, t('Element {z}', { z: e.z }), 'grid', { kind: 'element', z: e.z }, best + 10)
  }
  for (const g of reference.glossary) { const b = Math.max(score(g.name, q), score(t(g.name), q)); if (b > 0) add(t(g.name), t('Glossary'), 'book', { kind: 'glossary', name: g.name }, b) }
  for (const tool of reference.tools) { const b = Math.max(score(tool.name, q), score(t(tool.name), q)); if (b > 0) add(t(tool.name), t('Lab equipment'), 'flask', { kind: 'equipment', name: tool.name }, b - 5) }
  for (const m of moleculeLibrary) {
    const f = formulaOf(m); const b = Math.max(score(m.name, q), score(t(m.name), q), score(f, q))
    if (b > 0) add(t(m.name), `${t('Molecule')} · ${formulaText(f)}`, 'atom', { kind: 'molecule', name: m.name }, b - 5)
  }
  return out.sort((a, b) => b.score - a.score || (a.title < b.title ? 1 : -1)).slice(0, limit)
}
