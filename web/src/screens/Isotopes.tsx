import { useMemo, useState } from 'preact/hooks'
import { isotopes, Isotope, elementByZ, decayLabel, halfLifeText } from '../lib/element'
import { gradientColor } from '../lib/overlay'
import { formatNumber } from '../lib/format'
import { Canvas, cssVar } from '../ui/canvas'
import { Check, KV, Page, Segmented, Slider, useElementSize } from '../ui/kit'
import { t } from '../i18n'

const modes = ['Decay type', 'Half-life', 'Natural abundance'] as const
type Mode = typeof modes[number]
const classes: [string, string][] = [['Stable / natural', 'rgb(242,242,242)'], ['β⁻ decay', 'rgb(89,140,242)'], ['β⁺ / electron capture', 'rgb(235,89,89)'], ['α decay', 'rgb(250,209,64)'], ['Proton emission', 'rgb(242,140,51)'],
  ['Neutron emission', 'rgb(89,204,217)'], ['Fission', 'rgb(115,191,102)'], ['Decay mode unknown', 'rgb(128,128,128)'], ['No data', 'rgb(71,71,71)']]

export function decayClass(i: Isotope): number {
  if (i.halfLife == null) return i.abundance != null ? 0 : 8
  const m = i.decays[0]?.mode; if (!m) return 7
  if (m.includes('fission')) return 6
  if (m === 'alpha' || (m.includes('alpha') && !m.startsWith('beta') && !m.startsWith('ec'))) return 3
  if (m.startsWith('betaminus') || m.startsWith('2betaminus')) return 1
  if (m.startsWith('betaplus') || m.startsWith('ec') || m.startsWith('2betaplus') || m.startsWith('2ec')) return 2
  if (m.includes('proton')) return 4
  if (m.includes('neutron')) return 5
  return 7
}
function colorOf(i: Isotope, mode: Mode): string {
  if (mode === 'Decay type') return classes[decayClass(i)][1]
  if (mode === 'Half-life') return i.halfLife == null || i.halfLife <= 0 ? (i.abundance != null ? classes[0][1] : classes[8][1]) : gradientColor((Math.log10(i.halfLife) + 22) / 52)
  return i.abundance == null ? 'rgb(64,64,64)' : gradientColor(i.abundance / 100)
}
const maxN = Math.max(...isotopes.map(i => i.a - i.z)), maxZ = Math.max(...isotopes.map(i => i.z))
const lookup = new Map(isotopes.map(i => [(i.a - i.z) * 1000 + i.z, i]))
const magic = [2, 8, 20, 28, 50, 82, 126], margin = 34

export function IsotopeScreen() {
  const [mode, setMode] = useState<Mode>('Decay type'), [fit, setFit] = useState(true), [cellSize, setCellSize] = useState(9), [showMagic, setMagic] = useState(true)
  const [sel, setSel] = useState<Isotope | null>(null)
  const [boxRef, box] = useElementSize<HTMLDivElement>()
  const fitCell = box.w > 0 ? Math.min((box.w - margin - 8) / (maxN + 2), (box.h - margin - 8) / (maxZ + 2)) : 6
  const c = fit ? Math.max(3, Math.floor(fitCell)) : cellSize
  const W = margin + (maxN + 2) * c, H = margin + (maxZ + 2) * c
  const el = sel ? elementByZ.get(sel.z) : undefined
  const rect = (n: number, z: number) => ({ x: margin + n * c, y: (maxZ - z + 1) * c, w: c - 0.5, h: c - 0.5 })
  return <Page title={t("Isotope Chart")} toolbar={<>
    <label class="row gap8">{t("Color by")} <Segmented small value={mode} options={modes} onChange={setMode} label={t("Color by")} /></label>
    <Check checked={fit} onChange={setFit}>{t("Fit window")}</Check>
    <label class="row gap8">{t("Zoom")} <Slider label={t("Zoom")} value={cellSize} min={4} max={22} onChange={setCellSize} width={120} /></label>
    <Check checked={showMagic} onChange={setMagic}>{t("Magic numbers")}</Check></>}>
    <div class="legend">{mode === 'Decay type' ? classes.map(([n, col]) => <span key={n}><span class="swatch" style={{ background: col }} />{t(n)}</span>)
      : <><span class="mono">{mode === 'Half-life' ? '10⁻²² s' : '0 %'}</span><div class="gradbar" style={{ background: `linear-gradient(90deg, ${Array.from({ length: 11 }, (_, i) => gradientColor(i / 10)).join(',')})` }} /><span class="mono">{mode === 'Half-life' ? '10³⁰ s' : '100 %'}</span></>}</div>
    <div class="split" style={{ gridTemplateColumns: 'minmax(0,1fr) 300px' }}>
      <div class="scroll" style={{ background: 'var(--bg)' }} ref={boxRef as never}>
        <Canvas style={{ width: W, height: H, cursor: 'crosshair' }} label={t("Chart of the nuclides: neutrons on the x axis, protons on the y axis")} deps={[mode, c, showMagic, sel]} onRef={cv => {
          if (cv) cv.onclick = e => { const r = cv.getBoundingClientRect(); const n = Math.floor((e.clientX - r.left - margin) / c), z = maxZ + 1 - Math.floor((e.clientY - r.top) / c); setSel(lookup.get(n * 1000 + z) ?? null) }
        }} draw={(ctx, w, h) => {
          const dim = cssVar('--text2') || '#888', accent = cssVar('--accent') || '#2f6bff'
          if (showMagic) for (const m of magic) {
            ctx.fillStyle = 'rgba(128,128,128,.14)'
            if (m <= maxN) ctx.fillRect(margin + m * c, 0, c, h - margin)
            if (m <= maxZ) ctx.fillRect(margin, (maxZ - m + 1) * c, w - margin, c)
          }
          for (const i of isotopes) { const r = rect(i.a - i.z, i.z); ctx.fillStyle = colorOf(i, mode); ctx.fillRect(r.x, r.y, r.w, r.h) }
          if (sel) { const r = rect(sel.a - sel.z, sel.z); ctx.strokeStyle = accent; ctx.lineWidth = 2; ctx.strokeRect(r.x - 1, r.y - 1, r.w + 2, r.h + 2) }
          ctx.fillStyle = dim; ctx.font = '10px system-ui'
          ctx.textAlign = 'right'; ctx.textBaseline = 'middle'; for (let z = 10; z <= maxZ; z += 10) { const r = rect(0, z); ctx.fillText(String(z), margin - 6, r.y + c / 2) }
          ctx.textAlign = 'center'; for (let n = 20; n <= maxN; n += 20) { const r = rect(n, 0); ctx.fillText(String(n), r.x + c / 2, h - margin + 12) }
          ctx.font = 'bold 11px system-ui'; ctx.fillText('Z', 10, 8); ctx.fillText('N', w - 10, h - margin + 12)
        }} />
      </div>
      <aside class="inspector pad" aria-label={t("Isotope details")}>{sel && el ? <div class="col">
        <h1><sup>{sel.a}</sup>{el.symbol}</h1><div class="dim">{t(el.name)}-{sel.a}</div>
        <KV rows={[['Protons', String(sel.z)], ['Neutrons', String(sel.a - sel.z)], ['Nucleons', String(sel.a)], ['Exact mass', sel.mass != null ? formatNumber(sel.mass) + ' u' : '—'],
          ['Half-life', sel.halfLife == null ? (sel.abundance != null ? t('stable') : t('unknown')) : halfLifeText(sel)], ['Abundance', sel.abundance != null ? formatNumber(sel.abundance) + ' %' : '—'],
          ['Spin', sel.spin ?? 'Unknown'], ['Magnetic moment', sel.magneticMoment != null ? formatNumber(sel.magneticMoment) : 'Unknown']]} />
        {sel.decays.length > 0 && <><h3>{t("Decay")}</h3>{sel.decays.map((d, i) => <div key={i}>{decayLabel(d.mode)}{d.percent != null ? `  ${formatNumber(d.percent)} %` : ''}{d.energy != null ? `  (${formatNumber(d.energy)} MeV)` : ''}</div>)}</>}
      </div> : <div class="dim">{t("Click an isotope for details")}</div>}</aside>
    </div>
  </Page>
}
export { useMemo }
