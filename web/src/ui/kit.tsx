import { ComponentChildren } from 'preact'
import { useState } from 'preact/hooks'
import { markupHtml, formulaText } from '../lib/markup'
import { t, tc } from '../i18n'

export function Segmented<T extends string>({ value, options, onChange, small, label, labels }: { value: T; options: readonly T[]; onChange: (v: T) => void; small?: boolean; label?: string; labels?: Record<string, string> }) {
  return <div class={'seg' + (small ? ' small' : '')} role="group" aria-label={label}>
    {options.map(o => <button key={o} class={o === value ? 'on' : ''} aria-pressed={o === value} onClick={() => onChange(o)}>{t(labels?.[o] ?? o)}</button>)}
  </div>
}
export function Select<T extends string>({ value, options, onChange, label, labels }: { value: T; options: readonly T[]; onChange: (v: T) => void; label?: string; labels?: Record<string, string> }) {
  return <select value={value} aria-label={label} onChange={e => onChange((e.target as HTMLSelectElement).value as T)}>
    {options.map(o => <option key={o} value={o}>{t(labels?.[o] ?? o)}</option>)}
  </select>
}
export function Check({ checked, onChange, children }: { checked: boolean; onChange: (v: boolean) => void; children: ComponentChildren }) {
  return <label class="check"><input type="checkbox" checked={checked} onChange={e => onChange((e.target as HTMLInputElement).checked)} />{children}</label>
}
export function Slider({ value, min, max, step = 1, onChange, width = 180, label }: { value: number; min: number; max: number; step?: number; onChange: (v: number) => void; width?: number; label?: string }) {
  return <input type="range" aria-label={label} min={min} max={max} step={step} value={value} style={{ width }} onInput={e => onChange(Number((e.target as HTMLInputElement).value))} />
}
export function Field({ label, children }: { label: string; children: ComponentChildren }) {
  return <div class="field"><label>{label}</label>{children}</div>
}
export function Card({ title, children, class: c }: { title?: string; children: ComponentChildren; class?: string }) {
  return <section class={'card ' + (c ?? '')}>{title && <h3>{title}</h3>}{children}</section>
}
export function KV({ rows }: { rows: [string, ComponentChildren][] }) {
  return <div class="kv">{rows.flatMap(([k, v]) => [<div key={k + 'k'}>{t(k)}</div>, <div key={k + 'v'}>{v}</div>])}</div>
}
export function Markup({ text }: { text: string }) { return <span dangerouslySetInnerHTML={{ __html: markupHtml(text) }} /> }
export const F = ({ text }: { text: string }) => <>{formulaText(text)}</>
export function Page({ title, toolbar, children }: { title: string; toolbar?: ComponentChildren; children: ComponentChildren }) {
  return <div class="page" role="region" aria-label={title}>{toolbar && <div class="toolbar">{toolbar}</div>}{children}</div>
}
export function NumInput({ value, onChange, width = 110, label, step }: { value: number; onChange: (v: number) => void; width?: number; label?: string; step?: string }) {
  const [text, setText] = useState<string | null>(null)
  return <input type="text" inputMode="decimal" aria-label={label} style={{ width }} step={step} value={text ?? String(Number(value.toPrecision(10)))}
    onInput={e => { const t = (e.target as HTMLInputElement).value; setText(t); const v = Number(t.replace(',', '.')); if (t.trim() !== '' && Number.isFinite(v)) onChange(v) }}
    onBlur={() => setText(null)} />
}

import { Unit, fromBase, toBase, formatNumber } from '../lib/format'
/** A labeled numeric input with an optional unit menu, or a read-only computed value. `base` conversions are done by the caller via unit index. */
export function Quantity({ title, value, onChange, units, unit, onUnit, computed }: {
  title: string; value: number; onChange: (v: number) => void; units?: Unit[]; unit?: number; onUnit?: (i: number) => void; computed?: number | null
}) {
  return <div class="row" style={{ justifyContent: 'space-between', padding: '3px 0' }}>
    <span>{title}</span>
    <span class="row gap8">
      {computed !== undefined && computed !== null ? <b class="mono" style={{ minWidth: 120, textAlign: 'right', userSelect: 'text' }}>{formatNumber(computed)}</b>
        : <NumInput value={value} onChange={onChange} width={120} label={title} />}
      {units && units.length > 0 && <select aria-label={t('{title} unit', { title: t(title) })} value={unit ?? 0} onChange={e => onUnit?.(Number((e.target as HTMLSelectElement).value))} style={{ width: 92 }}>{units.map((u, i) => <option key={u.name} value={i}>{tc('unit', u.name)}</option>)}</select>}
    </span></div>
}
export { fromBase, toBase }

import { useEffect, useRef } from 'preact/hooks'
/** Tracks an element's content size with a ResizeObserver. */
export function useElementSize<T extends HTMLElement>(): [{ current: T | null }, { w: number; h: number }] {
  const ref = useRef<T>(null); const [size, setSize] = useState({ w: 0, h: 0 })
  useEffect(() => {
    const el = ref.current; if (!el) return
    const ro = new ResizeObserver(() => setSize({ w: el.clientWidth, h: el.clientHeight })); ro.observe(el); setSize({ w: el.clientWidth, h: el.clientHeight })
    return () => ro.disconnect()
  }, [])
  return [ref, size]
}
