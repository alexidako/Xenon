import { useState } from 'preact/hooks'
import { elements } from '../lib/element'
import { exportProps, buildExport, downloadText, ExportFormat } from '../lib/export'
import { Page, Segmented } from '../ui/kit'

export function ExportScreen() {
  const [els, setEls] = useState(new Set(elements.map(e => e.z))), [ps, setPs] = useState(new Set(exportProps.slice(0, 3).map(p => p.name)))
  const [format, setFormat] = useState<ExportFormat>('HTML'), [msg, setMsg] = useState('')
  const toggle = <T,>(s: Set<T>, v: T, set: (n: Set<T>) => void) => { const n = new Set(s); n.has(v) ? n.delete(v) : n.add(v); set(n) }
  const go = async () => {
    const text = buildExport(format, elements.filter(e => els.has(e.z)), exportProps.filter(p => ps.has(p.name)))
    const name = `elements.${format.toLowerCase()}`; const ok = await downloadText(name, text, format === 'HTML' ? 'text/html' : format === 'XML' ? 'application/xml' : 'text/csv'); setMsg(ok ? `Saved ${name}` : 'Not saved')
  }
  return <Page title="Export Data">
    <div class="split" style={{ gridTemplateColumns: '1fr 1fr' }}>
      <div class="col pad" style={{ minHeight: 0 }}><div class="row"><h3>Elements</h3><span class="grow" /><button class="link" onClick={() => setEls(new Set(elements.map(e => e.z)))}>All</button><button class="link" onClick={() => setEls(new Set())}>None</button></div>
        <div class="list" style={{ flex: 1, border: '1px solid var(--line)', borderRadius: 8 }}>{elements.map(e => <label key={e.z} class="check" style={{ display: 'flex', padding: '3px 8px' }}><input type="checkbox" checked={els.has(e.z)} onChange={() => toggle(els, e.z, setEls)} />{e.z}  {e.name}</label>)}</div></div>
      <div class="col pad" style={{ minHeight: 0 }}><div class="row"><h3>Properties</h3><span class="grow" /><button class="link" onClick={() => setPs(new Set(exportProps.map(p => p.name)))}>All</button><button class="link" onClick={() => setPs(new Set())}>None</button></div>
        <div class="list" style={{ flex: 1, border: '1px solid var(--line)', borderRadius: 8 }}>{exportProps.map(p => <label key={p.name} class="check" style={{ display: 'flex', padding: '3px 8px' }}><input type="checkbox" checked={ps.has(p.name)} onChange={() => toggle(ps, p.name, setPs)} />{p.name}</label>)}</div></div>
    </div>
    <div class="toolbar" style={{ borderTop: '1px solid var(--line)', borderBottom: 0 }}><Segmented value={format} options={['HTML', 'XML', 'CSV'] as const} onChange={setFormat} label="Format" />
      <span class="dim">{els.size} elements, {ps.size} properties</span><span class="grow" />{msg && <span class="small dim">{msg}</span>}
      <button class="btn primary" disabled={!els.size || !ps.size} onClick={go}>Export…</button></div>
  </Page>
}
