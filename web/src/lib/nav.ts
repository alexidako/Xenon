import { Store } from './store'
import { ScreenId, screens } from './screens'
import { PaletteItem } from './palette'

const last = (() => { try { return localStorage.getItem('xenon.lastScreen') } catch { return null } })()
const fromHash = () => { const h = location.hash.replace(/^#\/?/, ''); return h in screens ? h as ScreenId : null }

export const screen = new Store<ScreenId>(fromHash() ?? (last && last in screens ? last as ScreenId : 'table'))
screen.subscribe(() => {
  try { localStorage.setItem('xenon.lastScreen', screen.get()) } catch { /* ignore */ }
  if (location.hash !== '#/' + screen.get()) history.replaceState(null, '', '#/' + screen.get())
})
addEventListener('hashchange', () => { const s = fromHash(); if (s && s !== screen.get()) screen.set(s) })

/** Where the palette (or another screen) wants the app to land. */
export interface Jump { element: number | null; glossary: string | null; equipment: string | null; molecule: string | null; molFile: string | null; paletteOpen: boolean }
export const jump = new Store<Jump>({ element: null, glossary: null, equipment: null, molecule: null, molFile: null, paletteOpen: false })

export function go(id: ScreenId) { screen.set(id) }
export function goTo(item: PaletteItem) {
  const t = item.target
  jump.set(j => {
    switch (t.kind) {
      case 'element': return { ...j, element: t.z, paletteOpen: false }
      case 'glossary': return { ...j, glossary: t.name, paletteOpen: false }
      case 'equipment': return { ...j, equipment: t.name, paletteOpen: false }
      case 'molecule': return { ...j, molecule: t.name, paletteOpen: false }
      default: return { ...j, paletteOpen: false }
    }
  })
  switch (t.kind) {
    case 'screen': go(t.id); break
    case 'element': go('table'); break
    case 'glossary': go('glossary'); break
    case 'equipment': go('equipment'); break
    case 'molecule': go('molecules'); break
  }
}
