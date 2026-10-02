import { useEffect, useState } from 'preact/hooks'
import { reference, dataUrl } from '../lib/reference'
import { markupPlain } from '../lib/markup'
import { jump } from '../lib/nav'
import { useStore } from '../lib/store'
import { Markup, Page, Segmented } from '../ui/kit'

function useJumpTarget(key: 'glossary' | 'equipment', setSel: (n: string) => void) {
  const j = useStore(jump)
  useEffect(() => { const v = j[key]; if (v) { setSel(v); jump.set(x => ({ ...x, [key]: null })) } }, [j[key]])
}

export function GlossaryScreen() {
  const [sel, setSel] = useState(reference.glossary[0]?.name ?? ''), [q, setQ] = useState('')
  useJumpTarget('glossary', n => { setSel(n); setQ('') })
  const ql = q.toLowerCase()
  const list = ql ? reference.glossary.filter(g => g.name.toLowerCase().includes(ql) || markupPlain(g.desc).toLowerCase().includes(ql)) : reference.glossary
  const entry = reference.glossary.find(g => g.name === sel)
  return <Page title="Glossary" toolbar={<input type="search" aria-label="Search the glossary" placeholder="Search the glossary" value={q} onInput={e => setQ((e.target as HTMLInputElement).value)} style={{ width: 280 }} />}>
    <div class="split" style={{ gridTemplateColumns: '250px 1fr' }}>
      <div class="list" role="listbox" aria-label="Terms">{list.map(g => <button key={g.name} role="option" aria-selected={g.name === sel} class={g.name === sel ? 'on' : ''} onClick={() => setSel(g.name)}>{g.name}</button>)}</div>
      <div class="scroll pad">{entry ? <div class="col" style={{ maxWidth: 720 }}>
        <h1><Markup text={entry.name} /></h1><div style={{ fontSize: 17, lineHeight: 1.5 }}><Markup text={entry.desc} /></div>
        {entry.refs.length > 0 && <><h3 style={{ marginTop: 8 }}>See also</h3>{entry.refs.map(r => <button key={r} class="link" onClick={() => { setSel(r); setQ('') }}>{r}</button>)}</>}
      </div> : <div class="dim center pad">Select a term</div>}</div>
    </div>
  </Page>
}

/** Parses "10-23-45" style input; null when malformed. */
export function parsePhrases(s: string): number[] | null {
  const t = s.trim(); if (!t) return []
  if (t.startsWith('-') || t.endsWith('-')) return null
  const parts = t.split('-').map(p => p.trim())
  return parts.some(p => !/^\d+$/.test(p)) ? null : parts.map(Number)
}
const hazards: Record<string, string> = { E: 'Explosive', O: 'Oxidizing', F: 'Flammable', T: 'Toxic', C: 'Corrosive', X: 'Harmful / irritant', N: 'Dangerous for the environment' }

export function RSScreen() {
  const [rText, setR] = useState(''), [sText, setS] = useState('')
  const r = parsePhrases(rText), s = parsePhrases(sText)
  const section = (title: string, prefix: string, nums: number[], table: Record<string, string>) => nums.length > 0 && <div class="col gap8"><h2>{title}</h2>
    {nums.map((n, i) => <div key={i} class="row" style={{ alignItems: 'baseline' }}><b class="mono" style={{ width: 46 }}>{prefix}{n}</b><span class={table[String(n)] ? '' : 'dim'}>{table[String(n)] ?? 'No phrase with this number.'}</span></div>)}</div>
  return <Page title="Risk & Safety Phrases"><div class="scroll pad col" style={{ maxWidth: 820 }}>
    <h1>Risk & Safety Phrases</h1><div class="dim">Enter phrase numbers separated by dashes, for example R 11-23-36 and S 2-16.</div>
    <div class="row wrap gap16"><label class="field"><span class="label">R-phrases (risks)</span><input type="text" placeholder="e.g. 11-23" value={rText} onInput={e => setR((e.target as HTMLInputElement).value)} /></label>
      <label class="field"><span class="label">S-phrases (safety)</span><input type="text" placeholder="e.g. 2-16" value={sText} onInput={e => setS((e.target as HTMLInputElement).value)} /></label></div>
    {(r == null || s == null) && <div class="warn" role="alert">⚠ Invalid input: use numbers separated by single dashes.</div>}
    {section('R-phrases (risks)', 'R', r ?? [], reference.rphrases)}{section('S-phrases (safety)', 'S', s ?? [], reference.sphrases)}
    {r != null && s != null && !r.length && !s.length && <div class="dim">You asked for no R/S-phrases.</div>}
    <h2 style={{ marginTop: 16 }}>Hazard symbols</h2>
    <div class="row wrap gap16" style={{ alignItems: 'flex-start' }}>{Object.entries(hazards).map(([k, v]) => <div key={k} class="col center gap4" style={{ width: 90, alignItems: 'center' }}>
      <img src={dataUrl(`hazardsymbols/hazard_${k}.png`)} alt="" width={64} height={64} /><span class="small">{v}</span></div>)}</div>
  </div></Page>
}

export function TablesScreen() {
  const [tab, setTab] = useState<'Greek alphabet' | 'Numeric prefixes & Roman numerals'>('Greek alphabet')
  return <Page title="Reference Tables" toolbar={<Segmented value={tab} options={['Greek alphabet', 'Numeric prefixes & Roman numerals'] as const} onChange={setTab} />}>
    <div class="scroll pad">{tab === 'Greek alphabet'
      ? <table class="t" style={{ maxWidth: 520 }}><thead><tr><th>Uppercase</th><th>Lowercase</th><th>Name</th></tr></thead><tbody>{reference.greek.map(g => <tr key={g.name}><td style={{ fontSize: 18 }}>{g.upper}</td><td style={{ fontSize: 18 }}>{g.lower}</td><td>{g.name}</td></tr>)}</tbody></table>
      : <table class="t" style={{ maxWidth: 520 }}><thead><tr><th>Number</th><th>Prefix</th><th>Roman numeral</th></tr></thead><tbody>{reference.numbers.map((n, i) => <tr key={i}><td>{n.number}</td><td>{n.prefix}</td><td>{n.roman}</td></tr>)}</tbody></table>}</div>
  </Page>
}

export function EquipmentScreen() {
  const [sel, setSel] = useState(reference.tools[0]?.name ?? ''), [q, setQ] = useState('')
  useJumpTarget('equipment', n => { setSel(n); setQ('') })
  const list = q ? reference.tools.filter(t => t.name.toLowerCase().includes(q.toLowerCase())) : reference.tools
  const t = reference.tools.find(x => x.name === sel)
  return <Page title="Lab Equipment" toolbar={<input type="search" aria-label="Search equipment" placeholder="Search equipment" value={q} onInput={e => setQ((e.target as HTMLInputElement).value)} style={{ width: 280 }} />}>
    <div class="split" style={{ gridTemplateColumns: '250px 1fr' }}>
      <div class="list" role="listbox" aria-label="Equipment">{list.map(x => <button key={x.name} role="option" aria-selected={x.name === sel} class={x.name === sel ? 'on' : ''} onClick={() => setSel(x.name)}>{x.name}</button>)}</div>
      <div class="scroll pad">{t ? <div class="col" style={{ maxWidth: 720 }}><h1>{t.name}</h1>
        <img src={dataUrl(`toolpics/${t.picture}`)} alt={t.name} style={{ maxHeight: 280, maxWidth: '100%', objectFit: 'contain', borderRadius: 8, alignSelf: 'flex-start' }} />
        <div style={{ fontSize: 17, lineHeight: 1.5 }}><Markup text={t.desc} /></div></div> : <div class="dim center pad">Select a piece of equipment</div>}</div>
    </div>
  </Page>
}
