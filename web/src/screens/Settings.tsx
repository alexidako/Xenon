import { prefs, defaultPrefs, temperatureUnits, energyUnits, lengthUnits, temperatureText, energyText, lengthText, Theme } from '../lib/prefs'
import { useStore } from '../lib/store'
import { elementBySymbol } from '../lib/element'
import { Card, Field, Page, Segmented, Select } from '../ui/kit'
import { t, language, languages, setLanguage, Lang } from '../i18n'
import pkg from '../../package.json'

export function SettingsScreen() {
  const p = useStore(prefs); const lang = useStore(language); const fe = elementBySymbol.get('Fe')!
  const set = <K extends keyof typeof p>(k: K, v: (typeof p)[K]) => prefs.set(old => ({ ...old, [k]: v }))
  return <Page title={t("Settings")}><div class="scroll pad col" style={{ maxWidth: 640, gap: 16 }}>
    <h1>{t("Settings")}</h1>
    <Card title={t("Language")}><Field label={t("Language")}><select aria-label={t("Language")} value={lang} onChange={e => setLanguage((e.target as HTMLSelectElement).value as Lang)}>{languages.map(l => <option key={l.code} value={l.code}>{l.name}</option>)}</select></Field>
      <div class="small dim" style={{ marginTop: 8 }}>{t("Element names, the glossary and the lab equipment use the official KDE Kalzium translations. You can ask the periodic table search questions in any of these languages.")}</div></Card>
    <Card title={t("Appearance")}><Field label={t("Theme")}><Segmented<Theme> value={p.theme} options={['system', 'light', 'dark']} labels={{ system: 'System', light: 'Light', dark: 'Dark' }} onChange={v => set('theme', v)} /></Field></Card>
    <Card title={t("Units")}><div class="col">
      <Field label={t("Temperature")}><Select value={p.temperature} options={temperatureUnits} onChange={v => set('temperature', v)} /></Field>
      <Field label={t("Energy (ionization, electron affinity)")}><Select value={p.energy} options={energyUnits} onChange={v => set('energy', v)} /></Field>
      <Field label={t("Length (atomic radii)")}><Select value={p.length} options={lengthUnits} onChange={v => set('length', v)} /></Field>
      <div class="small dim">{t("These change how values are shown in the element details and the table legend. Calculators have their own unit menus.")}</div></div></Card>
    <Card title={t("Preview: Iron")}><div class="kv"><div>{t("Melting point")}</div><div>{temperatureText(fe.meltingPoint, p)}</div><div>{t("First ionization energy")}</div><div>{energyText(fe.ionization, p)}</div><div>{t("Covalent radius")}</div><div>{lengthText(fe.radiusCovalent, p)}</div></div></Card>
    <div><button class="btn" onClick={() => prefs.set(defaultPrefs)}>{t("Restore defaults")}</button></div>
    <Card title={t("About")}><div class="col gap4"><b>{t("Xenon {version}", { version: pkg.version })}</b><div>{t("A chemistry reference and learning app, built by pupper, 2026. Developed with Claude Code (Anthropic).")}</div>
      <div class="small dim">{t("Element, isotope and spectrum data: Blue Obelisk project (MIT). Glossary, lab equipment, hazard symbols, molecules, icons and the original application: KDE Kalzium (GPL-2.0-or-later).")}</div></div></Card>
  </div></Page>
}
