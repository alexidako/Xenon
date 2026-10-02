import { useEffect, useRef, useState } from 'preact/hooks'
import { elements } from '../lib/element'
import { EditorModel, Tool } from '../lib/editormodel'
import { templateNames, valences, Sketch, SketchAtom } from '../lib/sketch'
import { exportMolecule, Format } from '../lib/molecule'
import { downloadText } from '../lib/export'
import { addUserMolecule } from '../lib/usermol'
import { go } from '../lib/nav'
import { formulaText } from '../lib/markup'
import { formatNumber } from '../lib/format'
import { Canvas } from '../ui/canvas'
import { Card, Page, Segmented } from '../ui/kit'

/** Shared so the drawing survives switching to another screen and back. */
const model = new EditorModel()
const quick = ['C', 'H', 'N', 'O', 'S', 'P', 'F', 'Cl', 'Br', 'I'], more = elements.filter(e => valences[e.symbol]).map(e => e.symbol)
const tools: Tool[] = ['Draw', 'Move', 'Erase']

function labelColor(symbol: string): string {
  if (symbol === 'C') return 'rgb(224,224,224)'
  const e = elements.find(x => x.symbol === symbol); if (!e || e.color.length !== 3) return '#fff'
  return `rgb(${e.color.map(v => Math.round(Math.max(0.3, v) * 255)).join(',')})`
}
const subs = '₀₁₂₃₄₅₆₇₈₉'
const atomLabel = (s: Sketch, a: SketchAtom) => { const h = s.implicitHydrogens(a.id) ?? 0; return a.symbol + (a.symbol === 'H' || h === 0 ? '' : h === 1 ? 'H' : 'H' + [...String(h)].map(d => subs[Number(d)]).join('')) }

export function EditorScreen() {
  const [rev, force] = useState(0), redraw = () => force(n => n + 1)
  const [name, setName] = useState(model.customName), drag = useRef<{ start: { x: number; y: number }; atom?: SketchAtom; bond?: number; now: { x: number; y: number }; grab: { x: number; y: number }; active: boolean } | null>(null)
  const box = useRef<HTMLCanvasElement | null>(null)
  const s = model.sketch, problems = s.problems

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.metaKey || e.ctrlKey) || e.key.toLowerCase() !== 'z') return
      if ((e.target as HTMLElement)?.tagName === 'INPUT') return
      e.preventDefault(); if (e.shiftKey) model.redo(); else model.undo(); redraw()
    }
    addEventListener('keydown', onKey); return () => removeEventListener('keydown', onKey)
  }, [])

  const pt = (e: PointerEvent) => { const r = box.current!.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top } }
  const down = (e: PointerEvent) => {
    const p = pt(e), atom = model.atomAt(p.x, p.y), bond = atom ? undefined : model.bondAt(p.x, p.y)
    box.current!.setPointerCapture(e.pointerId)
    drag.current = { start: p, atom, bond: bond?.id, now: p, grab: atom ? { x: atom.x - p.x, y: atom.y - p.y } : { x: 0, y: 0 }, active: true }
    if (model.tool === 'Move' && atom) model.snapshot()
    redraw()
  }
  const move = (e: PointerEvent) => {
    const d = drag.current; if (!d) return
    const p = pt(e); d.now = p
    if (model.tool === 'Move' && d.atom) model.move(d.atom.id, p.x + d.grab.x, p.y + d.grab.y)
    redraw()
  }
  const up = (e: PointerEvent) => {
    const d = drag.current; if (!d) return; drag.current = null
    const p = pt(e), moved = Math.hypot(p.x - d.start.x, p.y - d.start.y)
    if (model.tool === 'Erase') { if (d.atom) { model.snapshot(); model.removeAtom(d.atom.id) } else if (d.bond != null) { model.snapshot(); model.removeBond(d.bond) } }
    else if (model.tool === 'Draw') {
      if (d.atom) {
        if (moved < 6) { if (d.atom.symbol !== model.element) { model.snapshot(); model.setElement(d.atom.id, model.element) } }
        else {
          const other = model.atomAt(p.x, p.y)
          if (other && other.id !== d.atom.id) { model.snapshot(); model.connect(d.atom.id, other.id, model.bondOrder) }
          else { model.snapshot(); const spot = model.snapped(d.atom, p.x, p.y); const target = model.atomAt(spot.x, spot.y)?.id ?? model.addAtom(model.element, spot.x, spot.y); model.connect(d.atom.id, target, model.bondOrder) }
        }
      } else if (d.bond != null && moved < 6) { model.snapshot(); model.cycle(d.bond) }
      else if (moved < 6) { model.snapshot(); model.addAtom(model.element, p.x, p.y) }
      else { model.snapshot(); const a = model.addAtom(model.element, d.start.x, d.start.y), b = model.addAtom(model.element, p.x, p.y); model.connect(a, b, model.bondOrder) }
    }
    redraw()
  }
  const send = (to: 'molecules' | 'vbt') => { addUserMolecule(model.molecule3D()); go(to) }
  const save = (f: Format) => { const m = model.molecule3D(); downloadText(`${model.name.replace(/ /g, '_')}.${f}`, exportMolecule(m, f)) }
  const formulaHtml = s.formula.split(/(\d+)/).map((part, i) => i % 2 ? <sub key={i}>{part}</sub> : part)

  return <Page title="Molecule Editor" toolbar={<>
    <Segmented small value={model.tool} options={tools} onChange={t => { model.tool = t; redraw() }} label="Tool" />
    <span class="row gap4">{quick.map(q => <button key={q} class={'btn small' + (model.element === q && model.tool === 'Draw' ? ' primary' : '')} aria-pressed={model.element === q} onClick={() => { model.element = q; model.tool = 'Draw'; redraw() }}>{q}</button>)}
      <select aria-label="More elements" value="" onChange={e => { const v = (e.target as HTMLSelectElement).value; if (v) { model.element = v; model.tool = 'Draw'; redraw() } }}><option value="">More</option>{more.map(m => <option key={m}>{m}</option>)}</select></span>
    <span title="Order of newly drawn bonds. Click an existing bond to cycle it."><Segmented small value={['—', '=', '≡'][model.bondOrder - 1]} options={['—', '=', '≡']} onChange={v => { model.bondOrder = ['—', '=', '≡'].indexOf(v) + 1; redraw() }} label="Bond order" /></span></>}>
    <div class="split" style={{ gridTemplateColumns: 'minmax(0,1fr) 300px' }}>
      <div style={{ minHeight: 0, position: 'relative', background: '#1c1c1c' }} title="Click to place an atom, drag from an atom to make a bond, click a bond to change its order">
        <Canvas class="" style={{ width: '100%', height: '100%', touchAction: 'none', cursor: model.tool === 'Move' ? 'move' : model.tool === 'Erase' ? 'not-allowed' : 'crosshair' }} label="Molecule drawing area" onRef={c => {
          box.current = c; if (c) { c.onpointerdown = down as never; c.onpointermove = move as never; c.onpointerup = up as never }
        }} deps={[rev, model.tool, model.element]} draw={(ctx, w, h) => {
          ctx.fillStyle = '#1c1c1c'; ctx.fillRect(0, 0, w, h)
          const bad = new Set(problems.map(p => p.atom.id)); ctx.lineCap = 'round'
          for (const b of s.bonds) {
            const a = s.atom(b.a), c = s.atom(b.b); if (!a || !c) continue
            const dx = c.x - a.x, dy = c.y - a.y, len = Math.max(1, Math.hypot(dx, dy)), ux = dx / len, uy = dy / len, px = -uy, py = ux, trim = Math.min(11, len / 2 - 1)
            for (const o of b.order === 1 ? [0] : b.order === 2 ? [-3.5, 3.5] : [-5, 0, 5]) { ctx.strokeStyle = 'rgb(204,204,204)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(a.x + ux * trim + px * o, a.y + uy * trim + py * o); ctx.lineTo(c.x - ux * trim + px * o, c.y - uy * trim + py * o); ctx.stroke() }
          }
          ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.font = '600 17px system-ui'
          for (const a of s.atoms) { if (bad.has(a.id)) { ctx.fillStyle = 'rgba(255,59,48,.35)'; ctx.beginPath(); ctx.arc(a.x, a.y, 15, 0, 7); ctx.fill() } ctx.fillStyle = labelColor(a.symbol); ctx.fillText(atomLabel(s, a), a.x, a.y) }
          const d = drag.current
          if (d && model.tool === 'Draw') { const from = d.atom ? { x: d.atom.x, y: d.atom.y } : d.start; ctx.strokeStyle = 'rgba(77,134,255,.85)'; ctx.setLineDash([5, 4]); ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(from.x, from.y); ctx.lineTo(d.now.x, d.now.y); ctx.stroke(); ctx.setLineDash([]) }
          if (model.tool === 'Erase') { ctx.fillStyle = '#999'; ctx.font = '12px system-ui'; ctx.fillText('Click an atom or bond to delete it', w / 2, h - 14) }
        }} />
      </div>
      <aside class="inspector pad col">
        <input type="text" aria-label="Name" placeholder={model.name} value={name} onInput={e => { const v = (e.target as HTMLInputElement).value; setName(v); model.customName = v; redraw() }} />
        {!s.atoms.length ? <div class="dim">Click the canvas to place an atom, then drag from it to draw a bond. Pick a template to start from a common molecule.</div> : <div class="col gap4">
          <div style={{ fontSize: 30, fontWeight: 700 }} aria-label={`Formula ${s.formula}`}>{formulaHtml}</div><div class="dim" style={{ fontSize: 17 }}>{formatNumber(s.mass)} u</div><div class="dim">{s.atoms.length} atoms, {s.bonds.length} bonds</div></div>}
        {problems.map((p, i) => <div key={i} class="warn" role="alert">⚠ {p.message}</div>)}
        <Card title="Edit"><div class="col gap8"><div class="row gap8"><button class="btn" disabled={!model.canUndo} onClick={() => { model.undo(); redraw() }}>↶ Undo</button><button class="btn" disabled={!model.canRedo} onClick={() => { model.redo(); redraw() }}>↷ Redo</button></div>
          <div class="row gap8"><button class="btn" disabled={!s.atoms.length} onClick={() => { model.addHydrogens(); redraw() }}>Add hydrogens</button><button class="btn danger" disabled={!s.atoms.length} onClick={() => { model.clear(); setName(''); redraw() }}>Clear</button></div>
          <select aria-label="Start from a template" value="" onChange={e => { const v = (e.target as HTMLSelectElement).value; if (v) { const r = box.current!.getBoundingClientRect(); model.load(v, r.width / 2, r.height / 2); setName(''); redraw() } }}><option value="">Start from a template</option>{templateNames.map(t => <option key={t}>{t}</option>)}</select></div></Card>
        <Card title="Use this molecule"><div class="col gap8"><button class="btn" disabled={!s.atoms.length} onClick={() => send('molecules')}>◇ View in 3D</button><button class="btn" disabled={!s.atoms.length} onClick={() => send('vbt')}>🔗 Analyze with valence bond theory</button>
          <select aria-label="Save" value="" disabled={!s.atoms.length} onChange={e => { const v = (e.target as HTMLSelectElement).value as Format; if (v) save(v) }}><option value="">Save…</option>{(['cml', 'mol', 'xyz'] as Format[]).map(f => <option key={f} value={f}>Save as .{f}</option>)}</select></div></Card>
        <div class="small dim">3D coordinates are generated from your drawing, so angles and lengths are estimates.</div>
      </aside>
    </div>
  </Page>
}
export { formulaText }
