import { Molecule } from './molecule'
import { optimizeMolecule, OptimizeResult } from './optimizer'

let worker: Worker | null = null, nextId = 1
const pending = new Map<number, (r: OptimizeResult) => void>()

/** Runs the geometry search off the main thread when workers are available, so the interface stays responsive. */
export function optimizeAsync(m: Molecule): Promise<OptimizeResult> {
  if (typeof Worker === 'undefined') return new Promise(res => setTimeout(() => res(optimizeMolecule(m)), 0))
  if (!worker) {
    worker = new Worker(new URL('./optimizer.worker.ts', import.meta.url), { type: 'module' })
    worker.onmessage = e => { const cb = pending.get(e.data.id); if (cb) { pending.delete(e.data.id); cb(e.data.result) } }
    worker.onerror = () => { for (const [id, cb] of pending) { pending.delete(id); cb(optimizeMolecule(lastInput.get(id)!)) } }
  }
  const id = nextId++; lastInput.set(id, m)
  return new Promise(res => { pending.set(id, r => { lastInput.delete(id); res(r) }); worker!.postMessage({ id, molecule: m }) })
}
const lastInput = new Map<number, Molecule>()
