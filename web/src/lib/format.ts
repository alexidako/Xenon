export interface Unit { name: string; factor: number; offset?: number }
export const toBase = (u: Unit, v: number) => v * u.factor + (u.offset ?? 0)
export const fromBase = (u: Unit, b: number) => (b - (u.offset ?? 0)) / u.factor

export const Units = {
  mass: [{ name: 'g', factor: 1 }, { name: 'mg', factor: 1e-3 }, { name: 'kg', factor: 1e3 }, { name: 't', factor: 1e6 }, { name: 'ct', factor: 0.2 },
    { name: 'lb', factor: 453.59237 }, { name: 'oz', factor: 28.349523125 }, { name: 'oz t', factor: 31.1034768 }] as Unit[],
  pressure: [{ name: 'atm', factor: 1 }, { name: 'Pa', factor: 1 / 101325 }, { name: 'bar', factor: 0.986923267 },
    { name: 'mbar', factor: 0.000986923267 }, { name: 'Torr', factor: 1 / 760 }] as Unit[],
  temperature: [{ name: 'K', factor: 1 }, { name: '°C', factor: 1, offset: 273.15 }, { name: '°F', factor: 5 / 9, offset: 273.15 - 160 / 9 }] as Unit[],
  volume: [{ name: 'L', factor: 1 }, { name: 'mL', factor: 1e-3 }, { name: 'm³', factor: 1000 }, { name: 'gal (US)', factor: 3.785411784 }] as Unit[],
  time: [{ name: 'y', factor: 31_557_600 }, { name: 'weeks', factor: 604_800 }, { name: 'd', factor: 86_400 }, { name: 'h', factor: 3_600 },
    { name: 'min', factor: 60 }, { name: 's', factor: 1 }] as Unit[],
}

/** Round to `n` significant digits without trailing zeros (like Swift's .significantDigits(1...n)). */
export const sig = (v: number, n: number): string => String(Number(v.toPrecision(n)))

export function formatNumber(v: number): string {
  if (!Number.isFinite(v)) return '—'
  if (v === 0) return '0'
  const a = Math.abs(v)
  if (a >= 1e7 || a < 1e-4) return Number(v.toPrecision(5)).toExponential().replace(/e\+?/, 'e').replace(/e(-?)(\d)$/, 'e$10$2')
  return sig(v, 7)
}
