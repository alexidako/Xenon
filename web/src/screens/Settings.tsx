import { prefs, defaultPrefs, temperatureUnits, energyUnits, lengthUnits, temperatureText, energyText, lengthText, Theme } from '../lib/prefs'
import { useStore } from '../lib/store'
import { elementBySymbol } from '../lib/element'
import { Card, Field, Page, Segmented, Select } from '../ui/kit'

export function SettingsScreen() {
  const p = useStore(prefs); const fe = elementBySymbol.get('Fe')!
  const set = <K extends keyof typeof p>(k: K, v: (typeof p)[K]) => prefs.set(old => ({ ...old, [k]: v }))
  return <Page title="Settings"><div class="scroll pad col" style={{ maxWidth: 640, gap: 16 }}>
    <h1>Settings</h1>
    <Card title="Appearance"><Field label="Theme"><Segmented<Theme> value={p.theme} options={['system', 'light', 'dark']} onChange={v => set('theme', v)} /></Field></Card>
    <Card title="Units"><div class="col">
      <Field label="Temperature"><Select value={p.temperature} options={temperatureUnits} onChange={v => set('temperature', v)} /></Field>
      <Field label="Energy (ionization, electron affinity)"><Select value={p.energy} options={energyUnits} onChange={v => set('energy', v)} /></Field>
      <Field label="Length (atomic radii)"><Select value={p.length} options={lengthUnits} onChange={v => set('length', v)} /></Field>
      <div class="small dim">These change how values are shown in the element details and the table legend. Calculators have their own unit menus.</div></div></Card>
    <Card title="Preview: Iron"><div class="kv"><div>Melting point</div><div>{temperatureText(fe.meltingPoint, p)}</div><div>First ionization energy</div><div>{energyText(fe.ionization, p)}</div><div>Covalent radius</div><div>{lengthText(fe.radiusCovalent, p)}</div></div></Card>
    <div><button class="btn" onClick={() => prefs.set(defaultPrefs)}>Restore defaults</button></div>
    <Card title="About"><div class="col gap4"><b>Xenon 1.0.1</b><div>A chemistry reference and learning app, built by pupper, 2026. Developed with Claude Code (Anthropic).</div>
      <div class="small dim">Element, isotope and spectrum data: Blue Obelisk project (MIT). Glossary, lab equipment, hazard symbols, molecules, icons and the original application: KDE Kalzium (GPL-2.0-or-later).</div></div></Card>
  </div></Page>
}
