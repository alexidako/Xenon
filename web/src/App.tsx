import { useEffect } from 'preact/hooks'
import { ComponentType } from 'preact'
import { useStore } from './lib/store'
import { language } from './i18n'
import { screen, jump, go } from './lib/nav'
import { screens, screenGroups, shortcutOrder, ScreenId } from './lib/screens'
import { prefs, applyTheme } from './lib/prefs'
import { Icon } from './ui/icons'
import { Palette } from './ui/Palette'
import { TableScreen } from './screens/Table'
import { SettingsScreen } from './screens/Settings'
import { GlossaryScreen, RSScreen, TablesScreen, EquipmentScreen } from './screens/Reference'
import { QuizScreen } from './screens/Quiz'
import { FillingScreen } from './screens/Filling'
import { IsotopeScreen } from './screens/Isotopes'
import { PlotScreen } from './screens/Plot'
import { MatcherScreen } from './screens/Matcher'
import { CalculatorsScreen } from './screens/Calculators'
import { SolverScreen } from './screens/Solver'
import { ExportScreen } from './screens/Export'
import { MoleculesScreen } from './screens/Molecules'
import { EditorScreen } from './screens/Editor'
import { OrbitalsScreen } from './screens/Orbitals'
import { VBTScreen } from './screens/VBT'
import { t } from './i18n'

const views: Record<ScreenId, ComponentType> = {
  table: TableScreen, glossary: GlossaryScreen, rs: RSScreen, tables: TablesScreen, equipment: EquipmentScreen, editor: EditorScreen,
  molecules: MoleculesScreen, orbitals: OrbitalsScreen, filling: FillingScreen, quiz: QuizScreen, vbt: VBTScreen, isotopes: IsotopeScreen,
  plot: PlotScreen, calculators: CalculatorsScreen, solver: SolverScreen, matcher: MatcherScreen, export: ExportScreen, settings: SettingsScreen,
}

const isMac = /Mac|iPhone|iPad/.test(navigator.platform)
export const modKey = isMac ? '⌘' : 'Ctrl+'

export function App() {
  const current = useStore(screen), j = useStore(jump), p = useStore(prefs), lang = useStore(language)
  useEffect(() => applyTheme(p.theme), [p.theme])
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const mod = isMac ? e.metaKey : e.ctrlKey
      if (!mod || e.altKey) return
      if (e.key.toLowerCase() === 'k') { e.preventDefault(); jump.set(x => ({ ...x, paletteOpen: !x.paletteOpen })) }
      else if (e.key === ',') { e.preventDefault(); go('settings') }
      else if (/^[0-9]$/.test(e.key)) { const i = e.key === '0' ? 9 : Number(e.key) - 1; const s = shortcutOrder[i]; if (s) { e.preventDefault(); go(s) } }
    }
    addEventListener('keydown', onKey); return () => removeEventListener('keydown', onKey)
  }, [])
  useEffect(() => { document.title = `${t(screens[current].title)} · Xenon` }, [current, lang])
  const View = views[current]
  return <div class="shell">
    <nav class="sidebar" aria-label={t("Screens")}>
      <div class="brand"><img src="icon.png" alt="" />{t("Xenon")}</div>
      <button class="nav-item" onClick={() => jump.set(x => ({ ...x, paletteOpen: true }))}><Icon name="search" />{t("Quick lookup")}<span class="kbd">{modKey}K</span></button>
      {screenGroups.map(g => <div class="nav-group" key={g.title}>
        <div class="nav-title">{t(g.title)}</div>
        {g.items.map(id => <button key={id} class={'nav-item' + (id === current ? ' active' : '')} aria-current={id === current ? 'page' : undefined} onClick={() => go(id)}>
          <Icon name={screens[id].icon} />{t(screens[id].title)}{shortcutOrder.includes(id) && <span class="kbd">{modKey}{(shortcutOrder.indexOf(id) + 1) % 10}</span>}
        </button>)}
      </div>)}
      <div class="nav-spacer" />
      <button class={'nav-item' + (current === 'settings' ? ' active' : '')} onClick={() => go('settings')}><Icon name="gear" />{t("Settings")}</button>
    </nav>
    <main class="main"><View key={current} /></main>
    {j.paletteOpen && <Palette />}
  </div>
}
