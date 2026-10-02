import { Store } from './store'
import { Molecule } from './molecule'

/** Molecules handed over from the editor (and imported files), shown at the top of the Molecules and Valence Bond lists. */
export const userMolecules = new Store<{ items: Molecule[]; focus: string | null }>({ items: [], focus: null })
export function addUserMolecule(m: Molecule) {
  userMolecules.set(s => ({ items: [m, ...s.items.filter(x => x.name !== m.name)], focus: m.name }))
}

/** Removes a molecule you made (by identity, so a custom molecule that shares a name with a built-in one is safe). */
export function removeUserMolecule(m: Molecule) {
  userMolecules.set(s => ({ items: s.items.filter(x => x !== m), focus: s.focus === m.name ? null : s.focus }))
}
