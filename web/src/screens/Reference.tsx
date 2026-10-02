import { useEffect, useState } from 'preact/hooks'
import { reference, dataUrl } from '../lib/reference'
import { markupPlain } from '../lib/markup'
import { jump } from '../lib/nav'
import { useStore } from '../lib/store'
import { Markup, Page, Segmented } from '../ui/kit'
import { t } from '../i18n'

function useJumpTarget(key: 'glossary' | 'equipment', setSel: (n: string) => void) {
  const j = useStore(jump)
  useEffect(() => { const v = j[key]; if (v) { setSel(v); jump.set(x => ({ ...x, [key]: null })) } }, [j[key]])
}

export function GlossaryScreen() {
  const [sel, setSel] = useState(reference.glossary[0]?.name ?? ''), [q, setQ] = useState('')
  useJumpTarget('glossary', n => { setSel(n); setQ('') })
  const ql = q.toLowerCase()
  const list = ql ? reference.glossary.filter(g => g.name.toLowerCase().includes(ql) || t(g.name).toLowerCase().includes(ql) || markupPlain(t(g.desc)).toLowerCase().includes(ql)) : reference.glossary
  const entry = reference.glossary.find(g => g.name === sel)
  return <Page title={t("Glossary")} toolbar={<input type="search" aria-label={t("Search the glossary")} placeholder={t("Search the glossary")} value={q} onInput={e => setQ((e.target as HTMLInputElement).value)} style={{ width: 280 }} />}>
    <div class="split" style={{ gridTemplateColumns: '250px 1fr' }}>
      <div class="list" role="listbox" aria-label={t("Terms")}>{list.map(g => <button key={g.name} role="option" aria-selected={g.name === sel} class={g.name === sel ? 'on' : ''} onClick={() => setSel(g.name)}>{t(g.name)}</button>)}</div>
      <div class="scroll pad">{entry ? <div class="col" style={{ maxWidth: 720 }}>
        <h1><Markup text={t(entry.name)} /></h1><div style={{ fontSize: 17, lineHeight: 1.5 }}><Markup text={t(entry.desc)} /></div>
        {entry.refs.length > 0 && <><h3 style={{ marginTop: 8 }}>{t("See also")}</h3>{entry.refs.map(r => <button key={r} class="link" onClick={() => { setSel(r); setQ('') }}>{t(r)}</button>)}</>}
      </div> : <div class="dim center pad">{t("Select a term")}</div>}</div>
    </div>
  </Page>
}

/** Parses "10-23-45" style input; null when malformed. */
export function parsePhrases(s: string): number[] | null {
  const trimmed = s.trim(); if (!trimmed) return []
  if (trimmed.startsWith('-') || trimmed.endsWith('-')) return null
  const parts = trimmed.split('-').map(p => p.trim())
  return parts.some(p => !/^\d+$/.test(p)) ? null : parts.map(Number)
}
/** A safety phrase in the current language (the translations are stored as "R11: Highly flammable"). */
const phrase = (prefix: string, n: number, text: string) => t(`${prefix}${n}: ${text}`).replace(new RegExp(`^${prefix}${n}:\\s*`), '')
const hazards: Record<string, string> = { E: 'Explosive', O: 'Oxidizing', F: 'Flammable', T: 'Toxic', C: 'Corrosive', X: 'Harmful / irritant', N: 'Dangerous for the environment' }

export function RSScreen() {
  const [rText, setR] = useState(''), [sText, setS] = useState('')
  const r = parsePhrases(rText), s = parsePhrases(sText)
  const section = (title: string, prefix: string, nums: number[], table: Record<string, string>) => nums.length > 0 && <div class="col gap8"><h2>{title}</h2>
    {nums.map((n, i) => <div key={i} class="row" style={{ alignItems: 'baseline' }}><b class="mono" style={{ width: 46 }}>{prefix}{n}</b><span class={table[String(n)] ? '' : 'dim'}>{table[String(n)] ? phrase(prefix, n, table[String(n)]) : t('No phrase with this number.')}</span></div>)}</div>
  return <Page title={t("Risk & Safety Phrases")}><div class="scroll pad col" style={{ maxWidth: 820 }}>
    <h1>{t("Risk & Safety Phrases")}</h1><div class="dim">{t("Enter phrase numbers separated by dashes, for example R 11-23-36 and S 2-16.")}</div>
    <div class="row wrap gap16"><label class="field"><span class="label">{t("R-phrases (risks)")}</span><input type="text" placeholder={t("e.g. 11-23")} value={rText} onInput={e => setR((e.target as HTMLInputElement).value)} /></label>
      <label class="field"><span class="label">{t("S-phrases (safety)")}</span><input type="text" placeholder={t("e.g. 2-16")} value={sText} onInput={e => setS((e.target as HTMLInputElement).value)} /></label></div>
    {(r == null || s == null) && <div class="warn" role="alert">{t("⚠ Invalid input: use numbers separated by single dashes.")}</div>}
    {section('R-phrases (risks)', 'R', r ?? [], reference.rphrases)}{section('S-phrases (safety)', 'S', s ?? [], reference.sphrases)}
    {r != null && s != null && !r.length && !s.length && <div class="dim">{t("You asked for no R/S-phrases.")}</div>}
    <h2 style={{ marginTop: 16 }}>{t("Hazard symbols")}</h2>
    <div class="row wrap gap16" style={{ alignItems: 'flex-start' }}>{Object.entries(hazards).map(([k, v]) => <div key={k} class="col center gap4" style={{ width: 90, alignItems: 'center' }}>
      <img src={dataUrl(`hazardsymbols/hazard_${k}.png`)} alt="" width={64} height={64} /><span class="small">{t(v)}</span></div>)}</div>
  </div></Page>
}

export function TablesScreen() {
  const [tab, setTab] = useState<'Greek alphabet' | 'Numeric prefixes & Roman numerals'>('Greek alphabet')
  return <Page title={t("Reference Tables")} toolbar={<Segmented value={tab} options={['Greek alphabet', 'Numeric prefixes & Roman numerals'] as const} onChange={setTab} />}>
    <div class="scroll pad">{tab === 'Greek alphabet'
      ? <table class="t" style={{ maxWidth: 520 }}><thead><tr><th>{t("Uppercase")}</th><th>{t("Lowercase")}</th><th>{t("Name")}</th></tr></thead><tbody>{reference.greek.map(g => <tr key={g.name}><td style={{ fontSize: 18 }}>{g.upper}</td><td style={{ fontSize: 18 }}>{g.lower}</td><td>{t(g.name)}</td></tr>)}</tbody></table>
      : <table class="t" style={{ maxWidth: 520 }}><thead><tr><th>{t("Number")}</th><th>{t("Prefix")}</th><th>{t("Roman numeral")}</th></tr></thead><tbody>{reference.numbers.map((n, i) => <tr key={i}><td>{n.number}</td><td>{t(n.prefix)}</td><td>{n.roman}</td></tr>)}</tbody></table>}</div>
  </Page>
}

export function EquipmentScreen() {
  const [sel, setSel] = useState(reference.tools[0]?.name ?? ''), [q, setQ] = useState('')
  useJumpTarget('equipment', n => { setSel(n); setQ('') })
  const list = q ? reference.tools.filter(x => x.name.toLowerCase().includes(q.toLowerCase()) || t(x.name).toLowerCase().includes(q.toLowerCase())) : reference.tools
  const tool = reference.tools.find(x => x.name === sel)
  return <Page title={t("Lab Equipment")} toolbar={<input type="search" aria-label={t("Search equipment")} placeholder={t("Search equipment")} value={q} onInput={e => setQ((e.target as HTMLInputElement).value)} style={{ width: 280 }} />}>
    <div class="split" style={{ gridTemplateColumns: '250px 1fr' }}>
      <div class="list" role="listbox" aria-label={t("Equipment")}>{list.map(x => <button key={x.name} role="option" aria-selected={x.name === sel} class={x.name === sel ? 'on' : ''} onClick={() => setSel(x.name)}>{t(x.name)}</button>)}</div>
      <div class="scroll pad">{tool ? <div class="col" style={{ maxWidth: 720 }}><h1>{t(tool.name)}</h1>
        <img src={dataUrl(`toolpics/${tool.picture}`)} alt={t(tool.name)} style={{ maxHeight: 280, maxWidth: '100%', objectFit: 'contain', borderRadius: 8, alignSelf: 'flex-start' }} />
        <div style={{ fontSize: 17, lineHeight: 1.5 }}><Markup text={t(tool.desc)} /></div></div> : <div class="dim center pad">{t("Select a piece of equipment")}</div>}</div>
    </div>
  </Page>
}
