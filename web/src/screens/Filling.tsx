import { useState } from 'preact/hooks'
import { elements, familyInfo } from '../lib/element'
import { FillState, order, subIndex, aufbau, actualConfig, formatConfig, sameConfig } from '../lib/filling'
import { Page, Check, Segmented } from '../ui/kit'
import { t } from '../i18n'

export function FillingScreen() {
  const [z, setZ] = useState(8), [state, setState] = useState(new FillState()), [strict, setStrict] = useState(true)
  const [removing, setRemoving] = useState(false), [warning, setWarning] = useState<string | null>(null), [hint, setHint] = useState<{ sub: number; box: number } | null>(null)
  const el = elements[z - 1], verdict = state.verdict(el)
  const used = new Set([...Object.keys(aufbau(z)), ...Object.keys(actualConfig(el))].map(subIndex))
  const rows = Math.min(order.length, Math.max(...used) + 2)
  const reset = (nz = z) => { setZ(nz); setState(new FillState()); setWarning(null); setHint(null) }
  const mutate = (fn: (s: FillState) => void) => { const s = state.clone(); fn(s); setState(s) }
  const tap = (sub: number, box: number) => {
    setHint(null)
    mutate(s => {
      if (removing) { setWarning(s.remove(sub, box) ? null : t('That orbital is already empty.')); return }
      const r = s.place(sub, box, z, strict); setWarning(r.ok ? null : r.why)
    })
  }
  const autofill = () => {
    const s = new FillState(), real = actualConfig(el)
    if (!strict && !sameConfig(real, aufbau(z))) {
      for (const [name, n] of Object.entries(real).sort(([a], [b]) => subIndex(a) - subIndex(b))) {
        const i = subIndex(name)
        for (let k = 0; k < n; k++) { let box = s.boxes[i].indexOf(0); if (box < 0) box = s.boxes[i].indexOf(1); s.place(i, box, z, false) }
      }
    } else for (let t = s.nextTarget(z); t; t = s.nextTarget(z)) s.place(t.sub, t.box, z, strict)
    setState(s); setWarning(null); setHint(null)
  }
  return <Page title={t("Electron Filling")}><div class="split" style={{ gridTemplateColumns: 'minmax(460px,1fr) 360px' }}>
    <div class="scroll pad col" style={{ gap: 14 }}>
      <div class="elhead" style={{ alignItems: 'center' }}>
        <div class="bigtile" style={{ width: 64, height: 64, background: familyInfo(el)?.color }}><span class="small">{el.z}</span><b style={{ fontSize: 30 }}>{el.symbol}</b></div>
        <div class="col gap4"><h1>{t(el.name)}</h1><div class="dim">{t('{n} of {z} electrons placed', { n: state.total, z })}</div><span class="bar" style={{ width: 220 }}><i style={{ width: `${state.total / z * 100}%` }} /></span></div></div>
      {order.slice(0, rows).map((s, sub) => <div key={s.name} class="row" style={{ gap: 10 }}>
        <span class="mono bold" style={{ width: 40, textAlign: 'right', fontSize: 16 }}>{s.name}</span>
        <div class="row gap4" role="group" aria-label={t('{sub} orbitals', { sub: s.name })}>{state.boxes[sub].map((n, b) => {
          const hl = hint?.sub === sub && hint.box === b
          return <button key={b} aria-label={n === 1 ? t('{sub} orbital {i}: 1 electron', { sub: s.name, i: b + 1 }) : t('{sub} orbital {i}: {n} electrons', { sub: s.name, i: b + 1, n })} onClick={() => tap(sub, b)}
            style={{ width: 50, height: 44, borderRadius: 5, border: `${hl ? 2.5 : 1.5}px solid ${hl ? '#ffd60a' : 'var(--text2)'}`, background: hl ? 'rgba(255,214,10,.25)' : 'var(--bg2)', cursor: 'pointer', fontSize: 18, fontWeight: 700, color: 'var(--text)' }}>
            {n >= 1 ? '↑' : ''}{n >= 2 ? '↓' : ''}</button> })}</div>
        <span class="small dim">{state.count(sub) ? `${state.count(sub)}/${s.capacity}` : ''}</span></div>)}
    </div>
    <aside class="inspector pad col">
      <label class="field"><span class="label">{t("Element")}</span><select value={z} onChange={e => reset(Number((e.target as HTMLSelectElement).value))}>{elements.map(e => <option key={e.z} value={e.z}>{e.z}  {t(e.name)}</option>)}</select></label>
      <div class="row wrap gap8"><button class="btn" onClick={() => reset(1 + Math.floor(Math.random() * 54))}>{t("Random")}</button><button class="btn" onClick={() => reset()}>{t("Reset")}</button>
        <button class="btn" disabled={state.total >= z} onClick={() => { setHint(state.nextTarget(z)); setWarning(null) }}>{t("Hint")}</button><button class="btn" onClick={autofill}>{t("Fill for me")}</button></div>
      <Segmented small value={removing ? 'Removes an electron' : 'Adds an electron'} options={['Adds an electron', 'Removes an electron'] as const} onChange={v => setRemoving(v === 'Removes an electron')} label={t("Click")} />
      <span title={t("Turn off to build exceptions such as chromium and copper")}><Check checked={strict} onChange={setStrict}>{t("Strict Aufbau order")}</Check></span>
      {warning && <div class="card warn" role="alert" style={{ background: 'rgba(255,159,10,.12)' }}>⚠ {warning}</div>}
      {state.total === z && <div class="card" role="status" style={{ background: verdict.matchesActual ? 'rgba(48,164,108,.12)' : 'rgba(59,130,246,.12)' }}>{verdict.matchesActual ? '✔ ' : 'ⓘ '}{verdict.message}</div>}
      <div class="card"><h3>{t("Your configuration")}</h3><div class="mono" style={{ fontSize: 17, userSelect: 'text' }}>{state.total === 0 ? '—' : formatConfig(state.configuration)}</div></div>
      <div class="card col gap8"><h3>{t("The three rules")}</h3><div class="small"><b>{t("Aufbau:")}</b> {t("fill the lowest-energy subshell first (1s, 2s, 2p, 3s, 3p, 4s, 3d …).")}</div>
        <div class="small"><b>{t("Pauli:")}</b> {t("an orbital holds at most 2 electrons, spinning opposite ways (↑ then ↓).")}</div><div class="small"><b>{t("Hund:")}</b> {t("in a subshell, give every orbital one electron before pairing any up.")}</div></div>
    </aside>
  </div></Page>
}
