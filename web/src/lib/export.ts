import { Element, familyInfo } from './element'

export interface ExportProp { name: string; value: (e: Element) => string }
const num = (v: number | null, unit = '') => v == null ? '' : (unit ? `${Number(v.toFixed(5))} ${unit}` : String(Number(v.toFixed(5))))
export const exportProps: ExportProp[] = [
  { name: 'Atomic Number', value: e => String(e.z) }, { name: 'Symbol', value: e => e.symbol }, { name: 'Mass', value: e => num(e.mass, 'u') },
  { name: 'Exact Mass', value: e => num(e.exactMass, 'u') }, { name: 'Ionization', value: e => num(e.ionization, 'eV') },
  { name: 'Electron Affinity', value: e => num(e.electronAffinity, 'eV') }, { name: 'Electronegativity', value: e => num(e.electronegativity) },
  { name: 'Covalent Radius', value: e => num(e.radiusCovalent, 'Å') }, { name: 'Van der Waals Radius', value: e => num(e.radiusVDW, 'Å') },
  { name: 'Melting Point', value: e => num(e.meltingPoint, 'K') }, { name: 'Boiling Point', value: e => num(e.boilingPoint, 'K') },
  { name: 'Family', value: e => familyInfo(e)?.label ?? '' },
]
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
export type ExportFormat = 'HTML' | 'XML' | 'CSV'

export function exportHtml(els: Element[], ps: ExportProp[]): string {
  let s = `<html>\n<head>\n<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>\n<style type="text/css">\nbody { font-family: arial; } .property { font-style: italic; }\nth { font-weight: bold; text-align: left; background-color: #F0F0F0; }\n</style>\n</head>\n<body>\n<table>\n`
  for (const e of els) { s += `<tr>\n<th colspan="2">${esc(e.name)}</th>\n</tr>\n`; for (const p of ps) s += `<tr>\n<td class="property">${esc(p.name)}</td>\n<td class="value">${esc(p.value(e))}</td>\n</tr>\n` }
  return s + '</table>\n</body>\n</html>\n'
}
export function exportXml(els: Element[], ps: ExportProp[]): string {
  let s = '<?xml version="1.0" encoding="UTF-8" ?>\n<elements>\n'
  for (const e of els) { s += `  <element name="${esc(e.name)}">\n`; for (const p of ps) s += `    <property name="${esc(p.name)}">${esc(p.value(e))}</property>\n`; s += '  </element>\n' }
  return s + '</elements>\n'
}
export function exportCsv(els: Element[], ps: ExportProp[]): string {
  const q = (s: string) => '"' + s.replace(/"/g, '""') + '"'
  let s = ['Name', ...ps.map(p => p.name)].map(q).join(',') + '\n'
  for (const e of els) s += [e.name, ...ps.map(p => p.value(e))].map(q).join(',') + '\n'
  return s
}
export const buildExport = (f: ExportFormat, els: Element[], ps: ExportProp[]) => f === 'HTML' ? exportHtml(els, ps) : f === 'XML' ? exportXml(els, ps) : exportCsv(els, ps)

const inTauri = () => typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window

/** Saves text as a file: a native "Save as" dialog in the desktop app, a normal download in the browser. */
export async function downloadText(name: string, text: string, mime = 'text/plain'): Promise<boolean> {
  if (inTauri()) {
    try {
      const { save } = await import('@tauri-apps/plugin-dialog'), { writeTextFile } = await import('@tauri-apps/plugin-fs')
      const path = await save({ defaultPath: name })
      if (!path) return false
      await writeTextFile(path, text); return true
    } catch (e) { console.error(e); return false }
  }
  const url = URL.createObjectURL(new Blob([text], { type: mime + ';charset=utf-8' }))
  const a = document.createElement('a'); a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000)
  return true
}

/** In the desktop app, links to the web open in the system browser. */
export function installExternalLinks() {
  if (!inTauri()) return
  document.addEventListener('click', async e => {
    const a = (e.target as HTMLElement).closest?.('a[href^="http"]') as HTMLAnchorElement | null
    if (!a) return
    e.preventDefault()
    const { openUrl } = await import('@tauri-apps/plugin-opener'); openUrl(a.href)
  })
}
