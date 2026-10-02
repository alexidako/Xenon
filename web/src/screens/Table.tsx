import { useEffect, useMemo, useState } from 'preact/hooks'
import { Element, elements, gridPosition, discoveryYear, familyInfo } from '../lib/element'
import { runQuery } from '../lib/query'
import { Numeration, numerations, numerationItems, Overlay, schemeNames, gradientNames, isGradient, overlayRange, overlayColor, overlayLegend, overlayNote,
  overlayDisplay, gradientColor } from '../lib/overlay'
import { t } from '../i18n'
import { prefs, temperatureText } from '../lib/prefs'
import { useStore } from '../lib/store'
import { jump } from '../lib/nav'
import { elementIconUrl } from '../lib/reference'
import { Page, Select, Slider, Check, useElementSize } from '../ui/kit'
import { ElementDetail } from './ElementDetail'

export function TableScreen() {
  const [selection, setSelection] = useState<Element>(elements[0])
  const [overlay, setOverlay] = useState<Overlay>('Family')
  const [numeration, setNumeration] = useState<Numeration>('No numeration')
  const [temp, setTemp] = useState(298), [year, setYear] = useState(2020)
  const [query, setQuery] = useState(''), [legend, setLegend] = useState(true)
  const j = useStore(jump); useStore(prefs)
  useEffect(() => { if (j.element != null) { const e = elements.find(x => x.z === j.element); if (e) setSelection(e); jump.set(x => ({ ...x, element: null })) } }, [j.element])

  const q = query.trim()
  const nl = useMemo(() => q.length >= 3 ? runQuery(q) : null, [q])
  const matchSet = nl ? new Set(nl.matches.map(e => e.z)) : null
  const range = useMemo(() => overlayRange(overlay), [overlay])
  const yearRange = overlayRange('Discovery date')
  const [boxRef, box] = useElementSize<HTMLDivElement>()

  return <Page title={t("Periodic Table")} toolbar={<>
    <label class="row gap8">{t("Color by")} <Select<Overlay> label={t("Color by")} value={overlay} options={[...schemeNames, ...gradientNames, 'State of matter']} onChange={setOverlay} /></label>
    <label class="row gap8">{t("Numeration")} <Select<Numeration> label={t("Numeration")} value={numeration} options={numerations} onChange={setNumeration} /></label>
    {overlay === 'State of matter' && <><Slider label={t("Temperature")} value={temp} min={0} max={6000} onChange={setTemp} /><span class="mono nowrap">{temperatureText(temp)}</span></>}
    {overlay === 'Discovery date' && <><Slider label={t("Discovery year")} value={year} min={yearRange[0]} max={yearRange[1]} onChange={setYear} /><span class="mono nowrap">{t('up to {year}', { year: Math.round(year) })}</span></>}
    <span class="grow" />
    <input type="search" aria-label={t("Search")} placeholder={t("Search or ask a question")} value={query} onInput={e => setQuery((e.target as HTMLInputElement).value)} style={{ width: 240 }} />
    <Check checked={legend} onChange={setLegend}>{t("Legend")}</Check>
  </>}>
    <div class="split" style={{ gridTemplateColumns: 'minmax(0,1fr) minmax(380px, 460px)' }}>
      <div class="col" style={{ gap: 0, minWidth: 0, minHeight: 0 }}>
        {nl && <QueryBanner result={nl} select={setSelection} />}
        {legend && <Legend overlay={overlay} range={range} />}
        <div class="scroll" style={{ flex: 1 }} ref={boxRef as never}>
          <PeriodicTable box={box} selection={selection} select={setSelection} overlay={overlay} temp={temp} range={range} numeration={numeration}
            query={q} matchSet={matchSet} yearLimit={overlay === 'Discovery date' ? year : null} />
        </div>
      </div>
      <aside class="inspector" aria-label={t("Element details")}><ElementDetail element={selection} /></aside>
    </div>
  </Page>
}

function Legend({ overlay, range }: { overlay: Overlay; range: [number, number] }) {
  const note = overlayNote(overlay)
  if (isGradient(overlay)) return <div class="legend">
    <span class="mono">{overlayDisplay(overlay, range[0])}</span>
    <div class="gradbar" style={{ background: `linear-gradient(90deg, ${Array.from({ length: 11 }, (_, i) => gradientColor(i / 10)).join(',')})` }} />
    <span class="mono">{overlayDisplay(overlay, range[1])}</span>
  </div>
  if (note) return <div class="legend dim">{t(note)}</div>
  return <div class="legend">{overlayLegend(overlay).map(([name, color]) => <span key={name}><span class="swatch" style={{ background: color }} />{t(name)}</span>)}</div>
}

function QueryBanner({ result, select }: { result: NonNullable<ReturnType<typeof runQuery>>; select: (e: Element) => void }) {
  return <div class="banner">
    <div class={'bold ' + (result.unsupported ? 'warn' : '')}>{result.description}{!result.unsupported && <span class="dim"> · {t('{n} found', { n: result.matches.length })}</span>}</div>
    {result.matches.length > 0 && <div class="row wrap gap4" style={{ marginTop: 6 }}>
      {result.matches.map(e => <button key={e.z} class="chip mono bold" title={t(e.name)} style={{ background: familyInfo(e)?.color, color: 'rgba(0,0,0,.85)', border: 0, cursor: 'pointer' }} onClick={() => select(e)}>{e.symbol}</button>)}
    </div>}
    {!result.matches.length && !result.unsupported && <div class="dim">{t("No element matches.")}</div>}
  </div>
}

function PeriodicTable({ box, selection, select, overlay, temp, range, numeration, query, matchSet, yearLimit }: {
  box: { w: number; h: number }; selection: Element; select: (e: Element) => void; overlay: Overlay; temp: number; range: [number, number]; numeration: Numeration
  query: string; matchSet: Set<number> | null; yearLimit: number | null
}) {
  const gap = 3, fGap = 14, topInset = numeration === 'No numeration' ? 0 : 18
  // size the tiles so all 18 columns and 10 rows fit the space that is actually available
  const cell = box.w > 0 ? Math.max(18, Math.min((box.w - 34) / 18 - gap, (box.h - 34 - fGap - topInset) / 10 - gap, 72)) : 40
  const q = query.toLowerCase()
  const W = 18 * (cell + gap), H = 10 * (cell + gap) + fGap + topInset
  return <div class="ptable" style={{ width: W, height: H, fontSize: cell }} role="grid" aria-label={t("Periodic table")}>
    {numerationItems(numeration).map((l, i) => <div key={i} class="numer" style={{ left: i * (cell + gap), width: cell, top: 0, fontSize: Math.max(9, cell * 0.2) }}>{l}</div>)}
    {[[5, '57–71'], [6, '89–103']].map(([row, label]) => <div key={label} class="fplace" style={{ left: 2 * (cell + gap), top: topInset + (row as number) * (cell + gap), width: cell, height: cell, fontSize: Math.max(8, cell * 0.16) }}>{label}</div>)}
    {elements.map(e => {
      const pos = gridPosition(e.z)
      const matches = matchSet ? matchSet.has(e.z) : (!q || e.name.toLowerCase().includes(q) || e.symbol.toLowerCase().includes(q) || String(e.z) === q)
        && (yearLimit == null || (discoveryYear(e) ?? 0) <= yearLimit)
      const iconic = overlay === 'Iconic'
      return <button key={e.z} role="gridcell" class={'tile' + (selection === e ? ' sel' : '') + (matches ? '' : ' dim') + (iconic ? ' iconic' : '')}
        aria-label={t('{name}, {symbol}, atomic number {z}', { name: t(e.name), symbol: e.symbol, z: e.z })} aria-selected={selection === e}
        style={{ left: pos.col * (cell + gap), top: topInset + pos.row * (cell + gap) + (pos.row >= 8 ? fGap : 0), width: cell, height: cell,
          background: iconic ? `linear-gradient(rgba(230,230,230,.35), rgba(230,230,230,.35)), url(${elementIconUrl(e.z)}) center/cover` : overlayColor(overlay, e, temp, range) }}
        onClick={() => select(e)}>
        <span class="z">{e.z}</span><span class="sym">{e.symbol}</span><span class="nm">{t(e.name)}</span>
      </button>
    })}
  </div>
}
