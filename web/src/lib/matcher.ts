import { Element, SpectrumLine, elements, spectra, nanometers } from './element'

export interface Match { observed: number; line: number; intensity: number }
export interface Candidate { element: Element; matches: Match[]; precision: number; recall: number; score: number }

/** Ranks elements by how well their known spectral lines explain a set of observed wavelengths (nm). */
export function rankSpectrum(observed: number[], tolerance: number, lines: Map<number, SpectrumLine[]> = spectra, els: Element[] = elements): Candidate[] {
  const obs = observed.filter(o => o > 0)
  if (!obs.length) return []
  const lo = Math.min(...obs), hi = Math.max(...obs)
  const windowLo = Math.min(lo, 380) - tolerance, windowHi = Math.max(hi, 780) + tolerance
  const byZ = new Map(els.map(e => [e.z, e]))
  const out: Candidate[] = []
  for (const [z, all] of lines) {
    const e = byZ.get(z); if (!e) continue
    const inWindow = all.filter(l => nanometers(l) >= windowLo && nanometers(l) <= windowHi)
    if (!inWindow.length) continue
    const matches: Match[] = []; let explained = 0
    const matched = new Set<number>()
    for (const o of obs) {
      let best: { idx: number; d: number } | null = null
      inWindow.forEach((l, i) => { const d = Math.abs(nanometers(l) - o); if (d <= tolerance && (!best || d < best.d)) best = { idx: i, d } })
      if (best) { const b = best as { idx: number; d: number }; explained++; matched.add(b.idx); matches.push({ observed: o, line: nanometers(inWindow[b.idx]), intensity: inWindow[b.idx].intensity }) }
    }
    if (!explained) continue
    inWindow.forEach((l, i) => { if (obs.some(o => Math.abs(o - nanometers(l)) <= tolerance)) matched.add(i) })
    const total = inWindow.reduce((s, l) => s + Math.max(l.intensity, 1), 0)
    const seen = [...matched].reduce((s, i) => s + Math.max(inWindow[i].intensity, 1), 0)
    const precision = explained / obs.length, recall = seen / total
    out.push({ element: e, matches, precision, recall, score: precision + recall === 0 ? 0 : 2 * precision * recall / (precision + recall) })
  }
  return out.sort((a, b) => a.score !== b.score ? b.score - a.score : a.element.z - b.element.z)
}

/** Every element with a line within tolerance of this wavelength, nearest first. */
export function assignments(nm: number, tolerance: number, lines: Map<number, SpectrumLine[]> = spectra, els: Element[] = elements): [Element, number][] {
  const byZ = new Map(els.map(e => [e.z, e]))
  const out: [Element, number][] = []
  for (const [z, ls] of lines) {
    const e = byZ.get(z); if (!e || !ls.length) continue
    const d = Math.min(...ls.map(l => Math.abs(nanometers(l) - nm)))
    if (d <= tolerance) out.push([e, d])
  }
  return out.sort((a, b) => a[1] - b[1])
}

/** Parses "486.1, 656.3 nm" / "4861 6563" style input; returns values converted to nm. */
export function parseWavelengths(text: string, angstrom: boolean): number[] {
  return text.split(/[,;\n\t ]+/).map(s => s.replaceAll('nm', '').replaceAll('Å', '')).filter(s => s !== '' && Number.isFinite(Number(s)))
    .map(s => Number(s)).map(v => angstrom ? v / 10 : v)
}
