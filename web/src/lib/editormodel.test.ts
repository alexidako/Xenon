import { describe, expect, it } from 'vitest'
import { EditorModel, distanceToSegment } from './editormodel'

describe('editor model', () => {
  it('the name follows the drawing, not the last template', () => {
    const m = new EditorModel(); m.load('Ammonia'); const atLoad = m.name
    const centre = m.sketch.atoms[0].id; m.setElement(centre, 'P')
    for (let k = 0; k < 3; k++) m.connect(centre, m.addAtom('Cl', 100 + k * 40, 100), 1)
    expect(atLoad).toBe('Ammonia'); expect(m.name).toBe('Cl3P')
    m.customName = 'My phosphine'; expect(m.name).toBe('My phosphine'); expect(m.molecule3D().name).toBe('My phosphine')
  })
  it('undo and redo', () => {
    const m = new EditorModel(); m.snapshot(); m.addAtom('C', 10, 10); expect(m.sketch.atoms.length).toBe(1); m.undo(); expect(m.sketch.atoms.length).toBe(0); expect(m.canRedo).toBe(true); m.redo(); expect(m.sketch.atoms.length).toBe(1)
  })
  it('hit testing, cycling and snapping', () => {
    const m = new EditorModel(); const a = m.addAtom('C', 0, 0), b = m.addAtom('C', 46, 0); m.connect(a, b, 1)
    expect(m.atomAt(5, 5)?.id).toBe(a); expect(m.atomAt(100, 100)).toBeUndefined(); expect(m.bondAt(23, 3)).toBeDefined(); expect(m.bondAt(23, 30)).toBeUndefined()
    m.connect(a, b, 1); expect(m.sketch.bonds[0].order).toBe(2); m.connect(a, b, 1); m.connect(a, b, 1); expect(m.sketch.bonds[0].order).toBe(1)
    const s = m.snapped(m.sketch.atoms[0], 40, 5); expect(Math.hypot(s.x, s.y)).toBeCloseTo(46, 5)
    expect(distanceToSegment(5, 5, 0, 0, 0, 0)).toBeCloseTo(Math.hypot(5, 5)); m.removeAtom(a); expect(m.sketch.bonds.length).toBe(0)
  })
})

import { userMolecules, addUserMolecule, removeUserMolecule } from './usermol'
import { moleculeLibrary } from './molecule'
describe('deleting custom molecules', () => {
  it('removes only the molecule you made', () => {
    userMolecules.set({ items: [], focus: null })
    const a = { name: 'Mine A', atoms: [{ symbol: 'O', x: 0, y: 0, z: 0 }], bonds: [] }, b = { name: 'Mine B', atoms: [{ symbol: 'N', x: 0, y: 0, z: 0 }], bonds: [] }
    addUserMolecule(a); addUserMolecule(b)
    removeUserMolecule(moleculeLibrary[0]); expect(userMolecules.get().items.length).toBe(2)       // a built-in molecule is not in the list: nothing happens
    removeUserMolecule(b); expect(userMolecules.get().items.map(m => m.name)).toEqual(['Mine A']); expect(userMolecules.get().focus).toBeNull()
    removeUserMolecule(a); removeUserMolecule(a); expect(userMolecules.get().items).toEqual([])
  })
  it('a custom molecule with a built-in name does not take the built-in one with it', () => {
    userMolecules.set({ items: [], focus: null })
    const mine = { ...moleculeLibrary.find(m => m.name === 'Ethanol')! }
    addUserMolecule(mine); removeUserMolecule(mine)
    expect(userMolecules.get().items).toEqual([]); expect(moleculeLibrary.some(m => m.name === 'Ethanol')).toBe(true)
  })
})
