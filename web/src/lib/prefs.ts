import { Store } from './store'
import { formatNumber, sig } from './format'

export const temperatureUnits = ['K', '°C', '°F'] as const
export const energyUnits = ['eV', 'kJ/mol', 'kcal/mol'] as const
export const lengthUnits = ['Å', 'pm', 'nm'] as const
export type TemperatureUnit = typeof temperatureUnits[number]
export type EnergyUnit = typeof energyUnits[number]
export type LengthUnit = typeof lengthUnits[number]
export type Theme = 'system' | 'light' | 'dark'

export interface Prefs { temperature: TemperatureUnit; energy: EnergyUnit; length: LengthUnit; theme: Theme }
export const defaultPrefs: Prefs = { temperature: 'K', energy: 'eV', length: 'Å', theme: 'system' }
export const prefs = new Store<Prefs>(defaultPrefs, 'xenon.prefs')

export const fromKelvin = (u: TemperatureUnit, k: number) => u === 'K' ? k : u === '°C' ? k - 273.15 : (k - 273.15) * 9 / 5 + 32
export const toKelvin = (u: TemperatureUnit, v: number) => u === 'K' ? v : u === '°C' ? v + 273.15 : (v - 32) * 5 / 9 + 273.15
export const fromEV = (u: EnergyUnit, e: number) => u === 'eV' ? e : u === 'kJ/mol' ? e * 96.485332 : e * 23.060549
export const fromAngstrom = (u: LengthUnit, a: number) => u === 'Å' ? a : u === 'pm' ? a * 100 : a / 10

const text = (v: number | null | undefined, unit: string) => v == null ? '—' : Number(v.toPrecision(6)).toLocaleString('en-US', { maximumFractionDigits: 10 }) + ' ' + unit
export const temperatureText = (k: number | null | undefined, p = prefs.get()) => text(k == null ? null : fromKelvin(p.temperature, k), p.temperature)
export const energyText = (ev: number | null | undefined, p = prefs.get()) => text(ev == null ? null : fromEV(p.energy, ev), p.energy)
export const lengthText = (a: number | null | undefined, p = prefs.get()) => text(a == null ? null : fromAngstrom(p.length, a), p.length)

export function applyTheme(t: Theme) {
  const el = document.documentElement
  if (t === 'system') el.removeAttribute('data-theme'); else el.setAttribute('data-theme', t)
}
export { formatNumber, sig }
