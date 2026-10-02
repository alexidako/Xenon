import { Molecule } from './molecule'
import { bondAngles } from './vbt'

export interface AngleItem { center: number; a: number; b: number; degrees: number }
/** One entry per pair of bonds at an atom (hydrogens are never centres). `atoms`: only these centres (empty = all).
 *  With no atoms chosen, the H–X–H angles of an atom that also has heavy neighbours are left out so larger molecules stay
 *  readable; choosing the atom shows all of its angles. */
export function bondAngleItems(m: Molecule, atoms: Set<number> = new Set()): AngleItem[] {
  const nbrs: number[][] = m.atoms.map(() => [])
  for (const b of m.bonds) if (b.a < m.atoms.length && b.b < m.atoms.length) { nbrs[b.a].push(b.b); nbrs[b.b].push(b.a) }
  const out: AngleItem[] = []
  m.atoms.forEach((a, c) => {
    if (nbrs[c].length < 2 || a.symbol === 'H' || (atoms.size && !atoms.has(c))) return
    const degs = bondAngles(c, m, nbrs[c]), hasHeavy = nbrs[c].some(j => m.atoms[j].symbol !== 'H'); let k = 0
    for (let i = 0; i < nbrs[c].length; i++) for (let j = i + 1; j < nbrs[c].length; j++) {
      const bothH = m.atoms[nbrs[c][i]].symbol === 'H' && m.atoms[nbrs[c][j]].symbol === 'H'
      if (k < degs.length && !(atoms.size === 0 && hasHeavy && bothH)) out.push({ center: c, a: nbrs[c][i], b: nbrs[c][j], degrees: degs[k] })
      k++
    }
  })
  return out
}
