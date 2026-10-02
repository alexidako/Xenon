import { optimizeMolecule } from './optimizer'
import { Molecule } from './molecule'
self.onmessage = (e: MessageEvent<{ id: number; molecule: Molecule }>) => {
  const r = optimizeMolecule(e.data.molecule)
  ;(self as unknown as Worker).postMessage({ id: e.data.id, result: r })
}
