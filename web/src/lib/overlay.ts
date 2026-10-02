import { Element, elements, families, familyInfo, stateAt, stateColor, discoveryYear, MatterState } from './element'
import { formatNumber } from './format'
import { prefs, fromKelvin, fromEV, fromAngstrom } from './prefs'

export const numerations = ['No numeration', 'IUPAC', 'CAS', 'Old IUPAC'] as const
export type Numeration = typeof numerations[number]
export function numerationItems(n: Numeration): string[] {
  switch (n) {
    case 'No numeration': return []
    case 'IUPAC': return Array.from({ length: 18 }, (_, i) => String(i + 1))
    case 'CAS': return ['IA', 'IIA', 'IIIB', 'IVB', 'VB', 'VIB', 'VIIB', 'VIII', 'VIII', 'VIII', 'IB', 'IIB', 'IIIA', 'IVA', 'VA', 'VIA', 'VIIA', 'VIIIA']
    case 'Old IUPAC': return ['1A', '2A', '3A', '4A', '5A', '6A', '7A', '8', '8', '8', '1B', '2B', '3B', '4B', '5B', '6B', '7B', '0']
  }
}

export const schemeNames = ['Monochrome', 'Blocks', 'Family', 'Groups', 'Colors', 'Iconic'] as const
export const gradientNames = ['Atomic mass', 'Covalent radius', 'Van der Waals radius', 'Electronegativity (Pauling)', 'Electron affinity', 'First ionization energy', 'Melting point', 'Boiling point', 'Discovery date'] as const
export type Overlay = typeof schemeNames[number] | typeof gradientNames[number] | 'State of matter'
export const isGradient = (o: Overlay) => (gradientNames as readonly string[]).includes(o)

export function overlayValue(o: Overlay, e: Element): number | null {
  switch (o) {
    case 'Atomic mass': return e.mass
    case 'Covalent radius': return e.radiusCovalent
    case 'Van der Waals radius': return e.radiusVDW
    case 'Electronegativity (Pauling)': return e.electronegativity
    case 'Electron affinity': return e.electronAffinity
    case 'First ionization energy': return e.ionization
    case 'Melting point': return e.meltingPoint
    case 'Boiling point': return e.boilingPoint
    case 'Discovery date': return discoveryYear(e)
    default: return null
  }
}
export function overlayUnit(o: Overlay): string {
  switch (o) { case 'Atomic mass': return 'u'; case 'Melting point': case 'Boiling point': return 'K'; case 'First ionization energy': case 'Electron affinity': return 'eV'
    case 'Covalent radius': case 'Van der Waals radius': return 'Å'; default: return '' }
}

export const blockColors: [string, string][] = [['s-Block', 'hsl(8 75% 66%)'], ['p-Block', 'hsl(105 40% 62%)'], ['d-Block', 'hsl(215 65% 66%)'], ['f-Block', 'hsl(290 35% 70%)']]
const hsb = (h: number, s: number, b: number) => { const l = b * (1 - s / 2), sl = l === 0 || l === 1 ? 0 : (b - l) / Math.min(l, 1 - l); return `hsl(${h * 360} ${sl * 100}% ${l * 100}%)` }
export const groupColors = Array.from({ length: 8 }, (_, i) => hsb(i / 8, 0.45, 0.92))
/** Gradient from cool blue (low) to red (high). */
export const gradientColor = (t: number) => hsb(0.60 - 0.60 * Math.min(Math.max(t, 0), 1), 0.55, 0.92)

export const overlayNote = (o: Overlay) => o === 'Colors' ? 'Nice colors without meaning (from the Open Babel project).' : o === 'Iconic' ? 'Each element is represented by an icon that shows what it is used for.' : null

export function overlayLegend(o: Overlay): [string, string][] {
  switch (o) {
    case 'Monochrome': return [['All the elements', 'rgb(184,184,184)']]
    case 'Blocks': return blockColors
    case 'Family': return families.map(f => [f.label, f.color] as [string, string])
    case 'Groups': return groupColors.map((c, i) => [`Group ${i + 1}`, c] as [string, string])
    case 'State of matter': return (['Solid', 'Liquid', 'Gas', 'Unknown'] as MatterState[]).map(s => [s, stateColor[s]] as [string, string])
    default: return []
  }
}

export function overlayRange(o: Overlay, els: Element[] = elements): [number, number] {
  const vals = els.map(e => overlayValue(o, e)).filter((v): v is number => v != null)
  return vals.length ? [Math.min(...vals), Math.max(...vals)] : [0, 1]
}

export function overlayColor(o: Overlay, e: Element, temperature: number, range: [number, number]): string {
  switch (o) {
    case 'Monochrome': return 'rgb(184,184,184)'
    case 'Blocks': return blockColors[Math.max(0, ['s', 'p', 'd', 'f'].indexOf(e.block ?? ''))][1]
    case 'Family': return familyInfo(e)?.color ?? 'rgba(128,128,128,.4)'
    case 'Groups': return groupColors[Math.max(0, Math.min(7, (e.group ?? 1) - 1))]
    case 'Colors': { const c = [...e.color, 0.5, 0.5, 0.5]; return `rgb(${c.slice(0, 3).map(v => Math.round(v * 255)).join(',')})` }
    case 'Iconic': return 'rgb(230,230,230)'
    case 'State of matter': return stateColor[stateAt(e, temperature)]
    default: {
      const v = overlayValue(o, e)
      return v == null || range[1] <= range[0] ? 'rgba(128,128,128,.25)' : gradientColor((v - range[0]) / (range[1] - range[0]))
    }
  }
}

/** Shows an overlay's quantity in the user's units, for legends. */
export function overlayDisplay(o: Overlay, v: number): string {
  const p = prefs.get()
  switch (o) {
    case 'Melting point': case 'Boiling point': return formatNumber(fromKelvin(p.temperature, v)) + ' ' + p.temperature
    case 'First ionization energy': case 'Electron affinity': return formatNumber(fromEV(p.energy, v)) + ' ' + p.energy
    case 'Covalent radius': case 'Van der Waals radius': return formatNumber(fromAngstrom(p.length, v)) + ' ' + p.length
    default: return formatNumber(v) + (overlayUnit(o) ? ' ' + overlayUnit(o) : '')
  }
}
