import elementsJson from '../data/elements.json'
import { t } from '../i18n'
import isotopesJson from '../data/isotopes.json'
import spectraJson from '../data/spectra.json'

export interface Element {
  z: number; symbol: string; name: string
  mass: number | null; exactMass: number | null; ionization: number | null; electronAffinity: number | null
  electronegativity: number | null; radiusCovalent: number | null; radiusVDW: number | null
  boilingPoint: number | null; meltingPoint: number | null
  block: string | null; period: number | null; group: number | null; family: string | null
  configuration: string | null; nameOrigin: string | null; discoveryDate: string | null
  discoverers: string[]; discoveryCountry: string[]; oxidation: number[]; color: number[]
}

export const elements = elementsJson as unknown as Element[]
export const elementBySymbol = new Map(elements.map(e => [e.symbol, e]))
export const elementByZ = new Map(elements.map(e => [e.z, e]))

export const discoveryYear = (e: Element): number | null => {
  if (e.discoveryDate == null) return null
  const v = Number(e.discoveryDate)
  return Number.isFinite(v) ? v : null
}

/** (row, col) in the standard 18-column layout; the f-block sits in rows 8 and 9. */
export function gridPosition(z: number): { row: number; col: number } {
  if (z === 1) return { row: 0, col: 0 }
  if (z === 2) return { row: 0, col: 17 }
  if (z <= 4) return { row: 1, col: z - 3 }
  if (z <= 10) return { row: 1, col: z - 5 + 12 }
  if (z <= 12) return { row: 2, col: z - 11 }
  if (z <= 18) return { row: 2, col: z - 13 + 12 }
  if (z <= 36) return { row: 3, col: z - 19 }
  if (z <= 54) return { row: 4, col: z - 37 }
  if (z <= 56) return { row: 5, col: z - 55 }
  if (z <= 71) return { row: 8, col: z - 57 + 2 }
  if (z <= 86) return { row: 5, col: z - 72 + 3 }
  if (z <= 88) return { row: 6, col: z - 87 }
  if (z <= 103) return { row: 9, col: z - 89 + 2 }
  return { row: 6, col: z - 104 + 3 }
}

/** Modern IUPAC group, 1–18 (the data file uses the older 1–8 numbering). null for the f-block rows. */
export function iupacGroup(z: number): number | null {
  const p = gridPosition(z)
  return p.row < 8 ? p.col + 1 : null
}

export type MatterState = 'Solid' | 'Liquid' | 'Gas' | 'Unknown'

export function stateAt(e: Element, kelvin: number): MatterState {
  const m = e.meltingPoint, b = e.boilingPoint
  // Arsenic and berkelium are listed with a melting point above their boiling point: they sublime.
  if (m != null && b != null && m > b) return kelvin < b ? 'Solid' : 'Gas'
  if (m == null) return 'Unknown'
  if (kelvin < m) return 'Solid'
  if (b == null) return 'Unknown'
  return kelvin < b ? 'Liquid' : 'Gas'
}

export const stateColor: Record<MatterState, string> = {
  Solid: 'rgb(89,115,191)', Liquid: 'rgb(64,166,217)', Gas: 'rgb(217,115,102)', Unknown: 'rgba(128,128,128,0.35)',
}

export interface FamilyInfo { key: string; label: string; color: string }
const rgb = (r: number, g: number, b: number) => `rgb(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)})`
export const families: FamilyInfo[] = [
  { key: 'Alkali_Earth', label: 'Alkali metals', color: rgb(0.90, 0.45, 0.40) },
  { key: 'Alkaline_Earth', label: 'Alkaline earth metals', color: rgb(0.93, 0.65, 0.35) },
  { key: 'Transition', label: 'Transition metals', color: rgb(0.45, 0.62, 0.85) },
  { key: 'Other_Metal', label: 'Other metals', color: rgb(0.55, 0.75, 0.70) },
  { key: 'Metalloids', label: 'Metalloids', color: rgb(0.70, 0.75, 0.40) },
  { key: 'Non-Metal', label: 'Nonmetals', color: rgb(0.55, 0.80, 0.50) },
  { key: 'Halogen', label: 'Halogens', color: rgb(0.35, 0.75, 0.80) },
  { key: 'Noblegas', label: 'Noble gases', color: rgb(0.70, 0.55, 0.85) },
  { key: 'Rare_Earth', label: 'Lanthanides & actinides', color: rgb(0.85, 0.60, 0.75) },
]
export const familyInfo = (e: Element): FamilyInfo | undefined => families.find(f => f.key === e.family)

// MARK: isotopes & spectra

export interface Decay { mode: string; energy: number | null; percent: number | null }
export interface Isotope {
  z: number; a: number; mass: number | null; spin: string | null; magneticMoment: number | null
  halfLife: number | null; abundance: number | null; decays: Decay[]
}
export interface SpectrumLine { intensity: number; wavelength: number }   // wavelength in angstrom

export const isotopes = isotopesJson as unknown as Isotope[]
export const isotopesByElement = new Map<number, Isotope[]>()
for (const i of isotopes) {
  const list = isotopesByElement.get(i.z) ?? []
  list.push(i); isotopesByElement.set(i.z, list)
}
export const spectra = new Map<number, SpectrumLine[]>(
  Object.entries(spectraJson as unknown as Record<string, SpectrumLine[]>).map(([k, v]) => [Number(k), v]))
export const nanometers = (l: SpectrumLine) => l.wavelength / 10

/** "betaminusneutron" -> "β⁻ + n" */
export function decayLabel(mode: string): string {
  const tokens: [string, string][] = [['betaminus', 'β⁻'], ['betaplus', 'β⁺'], ['alpha', 'α'], ['neutron', 'n'], ['proton', 'p'], ['fission', 'fission'], ['ec', 'EC']]
  let rest = mode; const parts: string[] = []
  outer: while (rest.length) {
    let count = ''
    while (rest.length && /\d/.test(rest[0])) { count += rest[0]; rest = rest.slice(1) }
    for (const [key, sym] of tokens) if (rest.startsWith(key)) { parts.push(count + sym); rest = rest.slice(key.length); continue outer }
    parts.push(rest); break
  }
  return parts.join(' + ')
}

const signif = (v: number, n: number) => String(Number(v.toPrecision(n)))
export function halfLifeText(i: Isotope): string {
  const s = i.halfLife
  if (s == null) return i.abundance != null ? t('stable') : '—'
  const units: [string, number][] = [['y', 31_557_600], ['d', 86_400], ['h', 3_600], ['min', 60], ['s', 1], ['ms', 1e-3], ['µs', 1e-6], ['ns', 1e-9], ['ps', 1e-12]]
  for (const [name, size] of units) if (s >= size) return signif(s / size, 4) + ' ' + name
  return s.toExponential(2) + ' s'
}

/** Approximate display color for a visible wavelength in nm (Bruton's algorithm). */
export function wavelengthColor(nm: number, clampToVisible = false): string {
  if (clampToVisible && (nm < 380 || nm > 780)) return nm < 380 ? 'rgb(89,89,89)' : 'rgb(51,51,51)'
  let r = 0, g = 0, b = 0
  if (nm >= 380 && nm < 440) { r = -(nm - 440) / 60; b = 1 }
  else if (nm >= 440 && nm < 490) { g = (nm - 440) / 50; b = 1 }
  else if (nm >= 490 && nm < 510) { g = 1; b = -(nm - 510) / 20 }
  else if (nm >= 510 && nm < 580) { r = (nm - 510) / 70; g = 1 }
  else if (nm >= 580 && nm < 645) { r = 1; g = -(nm - 645) / 65 }
  else if (nm >= 645 && nm <= 780) { r = 1 }
  else return 'gray'
  const edge = nm < 420 ? 0.3 + 0.7 * (nm - 380) / 40 : nm > 700 ? 0.3 + 0.7 * (780 - nm) / 80 : 1
  return rgb(r * edge, g * edge, b * edge)
}
