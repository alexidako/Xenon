import { useState } from 'preact/hooks'
import { Canvas, cssVar } from './canvas'

export interface Pt { x: number; y: number; label?: string }

/** "Nice" tick values spanning [lo, hi]. */
export function niceTicks(lo: number, hi: number, target = 6): number[] {
  if (!(hi > lo)) return [lo]
  const raw = (hi - lo) / target, mag = Math.pow(10, Math.floor(Math.log10(raw))), f = raw / mag
  const step = (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10) * mag
  const out: number[] = []
  for (let v = Math.ceil(lo / step) * step; v <= hi + step * 1e-9; v += step) out.push(Number(v.toPrecision(12)))
  return out
}
const tickText = (v: number) => Math.abs(v) >= 1e5 || (Math.abs(v) < 1e-3 && v !== 0) ? v.toExponential(1) : String(Number(v.toPrecision(6)))

/** A simple scatter/line chart on a canvas with axes, optional labels and hover readout. */
export function ScatterChart({ points, xLabel, yLabel, line, dots, labels, height = 420 }: {
  points: Pt[]; xLabel: string; yLabel: string; line: boolean; dots: boolean; labels: boolean; height?: number
}) {
  const [hover, setHover] = useState<Pt | null>(null)
  const m = { l: 64, r: 20, t: 16, b: 46 }
  const xs = points.map(p => p.x), ys = points.map(p => p.y)
  const xlo = Math.min(...xs), xhi = Math.max(Math.max(...xs), xlo + 1)
  let ylo = Math.min(...ys), yhi = Math.max(...ys); if (!(yhi > ylo)) { yhi = ylo + 1 }
  const pad = (yhi - ylo) * 0.06; ylo -= pad; yhi += pad
  const geom = (w: number, h: number) => ({ sx: (x: number) => m.l + (x - xlo) / (xhi - xlo) * (w - m.l - m.r), sy: (y: number) => h - m.b - (y - ylo) / (yhi - ylo) * (h - m.t - m.b) })
  let canvas: HTMLCanvasElement | null = null
  return <div style={{ position: 'relative', height }}>
    <Canvas style={{ width: '100%', height: '100%' }} label={`${yLabel} against ${xLabel}`} onRef={c => { canvas = c }} deps={[points, xLabel, yLabel, line, dots, labels, hover]} draw={(ctx, w, h) => {
      const text = cssVar('--text2') || '#888', grid = cssVar('--line') || '#ddd', accent = cssVar('--accent') || '#2f6bff'
      const { sx, sy } = geom(w, h)
      ctx.font = '11px system-ui'; ctx.fillStyle = text; ctx.strokeStyle = grid; ctx.lineWidth = 1
      for (const t of niceTicks(ylo, yhi)) { const y = sy(t); ctx.beginPath(); ctx.moveTo(m.l, y); ctx.lineTo(w - m.r, y); ctx.stroke(); ctx.textAlign = 'right'; ctx.textBaseline = 'middle'; ctx.fillText(tickText(t), m.l - 6, y) }
      for (const t of niceTicks(xlo, xhi, 8)) { const x = sx(t); ctx.beginPath(); ctx.moveTo(x, m.t); ctx.lineTo(x, h - m.b); ctx.stroke(); ctx.textAlign = 'center'; ctx.textBaseline = 'top'; ctx.fillText(tickText(t), x, h - m.b + 5) }
      ctx.font = '12px system-ui'; ctx.textAlign = 'center'; ctx.fillText(xLabel, (m.l + w - m.r) / 2, h - 16)
      ctx.save(); ctx.translate(14, (m.t + h - m.b) / 2); ctx.rotate(-Math.PI / 2); ctx.fillText(yLabel, 0, 0); ctx.restore()
      if (line && points.length > 1) { ctx.strokeStyle = accent; ctx.globalAlpha = 0.6; ctx.lineWidth = 1.5; ctx.beginPath(); points.forEach((p, i) => i ? ctx.lineTo(sx(p.x), sy(p.y)) : ctx.moveTo(sx(p.x), sy(p.y))); ctx.stroke(); ctx.globalAlpha = 1 }
      for (const p of points) {
        const x = sx(p.x), y = sy(p.y)
        if (dots) { ctx.fillStyle = p === hover ? '#ff9f0a' : accent; ctx.beginPath(); ctx.arc(x, y, p === hover ? 5 : 3.2, 0, 7); ctx.fill() }
        if (labels && p.label) { ctx.fillStyle = text; ctx.font = '9px system-ui'; ctx.textAlign = 'center'; ctx.textBaseline = 'bottom'; ctx.fillText(p.label, x, y - 5) }
      }
    }} />
    <div style={{ position: 'absolute', inset: 0 }} onMouseMove={e => {
      const r = (e.currentTarget as HTMLElement).getBoundingClientRect(), { sx, sy } = geom(r.width, r.height)
      const mx = e.clientX - r.left, my = e.clientY - r.top
      let best: Pt | null = null, bd = 14 * 14
      for (const p of points) { const d = (sx(p.x) - mx) ** 2 + (sy(p.y) - my) ** 2; if (d < bd) { bd = d; best = p } }
      setHover(best)
    }} onMouseLeave={() => setHover(null)} />
    {hover && <div class="card small" style={{ position: 'absolute', right: 24, top: 10, pointerEvents: 'none' }}><b>{hover.label}</b> {xLabel}: {tickText(hover.x)} · {yLabel}: {tickText(hover.y)}</div>}
  </div>
}

export interface Series { name: string; color: string; points: { x: number; y: number }[]; kind: 'line' | 'points' }
/** Several named series on shared, fixed axes (for the titration plot). */
export function SeriesChart({ series, xRange, yRange, height = 320 }: { series: Series[]; xRange: [number, number]; yRange: [number, number]; height?: number }) {
  const m = { l: 56, r: 16, t: 12, b: 36 }
  const [x0, x1] = [xRange[0], Math.max(xRange[1], xRange[0] + 1)], [y0, y1] = [yRange[0], Math.max(yRange[1], yRange[0] + 1)]
  return <div class="col gap4"><Canvas style={{ width: '100%', height }} label="Titration plot" deps={[series, x0, x1, y0, y1]} draw={(ctx, w, h) => {
    const text = cssVar('--text2') || '#888', grid = cssVar('--line') || '#ddd'
    const sx = (x: number) => m.l + (x - x0) / (x1 - x0) * (w - m.l - m.r), sy = (y: number) => h - m.b - (y - y0) / (y1 - y0) * (h - m.t - m.b)
    ctx.font = '11px system-ui'; ctx.strokeStyle = grid; ctx.fillStyle = text
    for (const t of niceTicks(y0, y1)) { ctx.beginPath(); ctx.moveTo(m.l, sy(t)); ctx.lineTo(w - m.r, sy(t)); ctx.stroke(); ctx.textAlign = 'right'; ctx.textBaseline = 'middle'; ctx.fillText(tickText(t), m.l - 6, sy(t)) }
    for (const t of niceTicks(x0, x1, 8)) { ctx.beginPath(); ctx.moveTo(sx(t), m.t); ctx.lineTo(sx(t), h - m.b); ctx.stroke(); ctx.textAlign = 'center'; ctx.textBaseline = 'top'; ctx.fillText(tickText(t), sx(t), h - m.b + 5) }
    ctx.save(); ctx.beginPath(); ctx.rect(m.l, m.t, w - m.l - m.r, h - m.t - m.b); ctx.clip()
    for (const s of series) {
      ctx.strokeStyle = ctx.fillStyle = s.color
      if (s.kind === 'line') { ctx.lineWidth = 2; ctx.beginPath(); s.points.forEach((p, i) => i ? ctx.lineTo(sx(p.x), sy(p.y)) : ctx.moveTo(sx(p.x), sy(p.y))); ctx.stroke() }
      else for (const p of s.points) { ctx.beginPath(); ctx.arc(sx(p.x), sy(p.y), 4, 0, 7); ctx.fill() }
    }
    ctx.restore()
  }} />
    <div class="row gap16 small">{series.map(s => <span key={s.name}><span class="swatch" style={{ background: s.color }} />{s.name}</span>)}</div></div>
}
