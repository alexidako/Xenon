import { Element } from './element'
import { subshellsOf, superscript } from './config'
import { t } from '../i18n'

export interface Sub { n: number; l: number; letter: string; name: string; orbitals: number; capacity: number }
const mk = (n: number, l: number): Sub => ({ n, l, letter: 'spdf'[l], name: `${n}${'spdf'[l]}`, orbitals: 2 * l + 1, capacity: 2 * (2 * l + 1) })

/** 1s 2s 2p 3s 3p 4s 3d 4p 5s 4d 5p 6s 4f 5d 6p 7s 5f 6d 7p (Madelung order) */
export const order: Sub[] = Array.from({ length: 7 }, (_, i) => i + 1)
  .flatMap(n => Array.from({ length: Math.min(n - 1, 3) + 1 }, (_, l) => mk(n, l)))
  .sort((a, b) => (a.n + a.l) - (b.n + b.l) || a.n - b.n)
export const subIndex = (name: string) => order.findIndex(s => s.name === name)

export type Config = Record<string, number>

/** "3d⁵ 4s¹" written the conventional way (by shell, then s p d f). */
export function formatConfig(c: Config): string {
  return Object.entries(c).filter(([, v]) => v > 0)
    .sort(([a], [b]) => { const sa = order[subIndex(a)], sb = order[subIndex(b)]; return sa.n - sb.n || sa.l - sb.l })
    .map(([k, v]) => `${k}${superscript(v)}`).join(' ')
}

/** The configuration the Aufbau order predicts for `z` electrons. */
export function aufbau(z: number): Config {
  let left = z; const out: Config = {}
  for (const s of order) { if (left <= 0) break; const k = Math.min(left, s.capacity); out[s.name] = k; left -= k }
  return out
}

/** The measured configuration from the element data (noble-gas cores expanded). */
export function actualConfig(e: Element): Config {
  const out: Config = {}
  for (const s of subshellsOf(e.configuration ?? '')) { const k = `${s.n}${s.l}`; out[k] = (out[k] ?? 0) + s.electrons }
  return out
}

export const sameConfig = (a: Config, b: Config) => {
  const ka = Object.keys(a).filter(k => a[k] > 0), kb = Object.keys(b).filter(k => b[k] > 0)
  return ka.length === kb.length && ka.every(k => a[k] === b[k])
}

export type Placement = { ok: true } | { ok: false; why: string }
export interface Verdict { complete: boolean; matchesAufbau: boolean; matchesActual: boolean; message: string }

export class FillState {
  /** electrons per orbital box, grouped by subshell in Aufbau order (0, 1 or 2 each) */
  boxes: number[][] = order.map(s => Array(s.orbitals).fill(0))

  clone(): FillState { const f = new FillState(); f.boxes = this.boxes.map(b => b.slice()); return f }
  get total() { return this.boxes.flat().reduce((a, b) => a + b, 0) }
  count(sub: number) { return this.boxes[sub].reduce((a, b) => a + b, 0) }
  isFull(sub: number) { return this.count(sub) === order[sub].capacity }
  get configuration(): Config {
    const out: Config = {}
    order.forEach((s, i) => { if (this.count(i) > 0) out[s.name] = this.count(i) })
    return out
  }

  place(sub: number, box: number, z: number, strictAufbau: boolean): Placement {
    const s = order[sub]
    if (this.total >= z) return { ok: false, why: t('All {z} electrons are already placed. Remove one first.', { z }) }
    if (this.boxes[sub][box] >= 2) return { ok: false, why: t('Pauli exclusion principle: an orbital holds at most two electrons, with opposite spins.') }
    if (strictAufbau) {
      const lower = order.findIndex((_, i) => i < sub && !this.isFull(i))
      if (lower >= 0) return { ok: false, why: t('Aufbau principle: electrons fill the lowest-energy subshell first. {sub} is not full yet.', { sub: order[lower].name }) }
    }
    if (this.boxes[sub][box] === 1 && this.boxes[sub].includes(0)) {
      return { ok: false, why: t("Hund's rule: in {sub}, put one electron in each orbital (all spinning the same way) before pairing any up.", { sub: s.name }) }
    }
    this.boxes[sub][box]++
    return { ok: true }
  }

  remove(sub: number, box: number): boolean {
    if (this.boxes[sub][box] <= 0) return false
    this.boxes[sub][box]--
    return true
  }

  /** Where the next electron should go, following all three rules. */
  nextTarget(z: number): { sub: number; box: number } | null {
    if (this.total >= z) return null
    const sub = order.findIndex((_, i) => !this.isFull(i))
    if (sub < 0) return null
    const empty = this.boxes[sub].indexOf(0)
    if (empty >= 0) return { sub, box: empty }
    const single = this.boxes[sub].indexOf(1)
    return single >= 0 ? { sub, box: single } : null
  }

  verdict(e: Element): Verdict {
    if (this.total !== e.z) return { complete: false, matchesAufbau: false, matchesActual: false, message: t('{n} of {z} electrons placed.', { n: this.total, z: e.z }) }
    const mine = this.configuration, predicted = aufbau(e.z), real = actualConfig(e)
    const a = sameConfig(mine, predicted), r = sameConfig(mine, real)
    let msg: string
    if (r && a) msg = t('Correct. {name} is {config}, exactly what the Aufbau order predicts.', { name: t(e.name), config: formatConfig(real) })
    else if (r) msg = t('Correct! This is the real configuration of {name}: {config}. It breaks the simple Aufbau order (which predicts {predicted}) because {reason}.', { name: t(e.name), config: formatConfig(real), predicted: formatConfig(predicted), reason: reasonFor(e) })
    else if (a) msg = t('This follows the Aufbau order, but real {name} is an exception: {config}, because {reason}. Turn off “Strict Aufbau” to build it.', { name: t(e.name), config: formatConfig(real), reason: reasonFor(e) })
    else msg = t('Not quite. {name} is {config}.', { name: t(e.name), config: formatConfig(real) })
    return { complete: true, matchesAufbau: a, matchesActual: r, message: msg }
  }
}

export function reasonFor(e: Element): string {
  const real = actualConfig(e)
  if (real['3d'] === 5 || real['4d'] === 5 || real['5d'] === 5) return t('a half-filled d subshell is especially stable')
  if (real['3d'] === 10 || real['4d'] === 10 || real['5d'] === 10) return t('a completely filled d subshell is especially stable')
  return t('the s, d and f subshells are so close in energy that electrons shift between them')
}
