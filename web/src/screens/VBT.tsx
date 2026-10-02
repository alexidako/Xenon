import { useEffect, useMemo, useState } from 'preact/hooks'
import { elements, elementBySymbol } from '../lib/element'
import { Hybridization, analyzeMolecule, chargeText, Box } from '../lib/vbt'
import { moleculeLibrary, formulaOf, Molecule } from '../lib/molecule'
import { formulaText } from '../lib/markup'
import { resonancePresets, resonanceStructures, hybridOrders, averageCharges, ResonanceInput, LewisStructure } from '../lib/resonance'
import { userMolecules } from '../lib/usermol'
import { useStore } from '../lib/store'
import { Canvas, cssVar } from '../ui/canvas'
import { Card, Page, Segmented } from '../ui/kit'
import { t } from '../i18n'

const modes = ['Molecules', 'Predict', 'Resonance'] as const
type Mode = typeof modes[number]

export function VBTScreen() {
  const [mode, setMode] = useState<Mode>('Molecules')
  return <Page title={t("Valence Bond Theory")} toolbar={<Segmented value={mode} options={modes} onChange={setMode} label={t("Mode")} />}>
    {mode === 'Molecules' ? <MoleculeMode /> : mode === 'Predict' ? <PredictMode /> : <ResonanceMode />}</Page>
}

// MARK: shared diagram
function BoxView({ box }: { box: Box }) {
  const col = box.kind === 'hybridLonePair' ? '#a64dd9' : box.kind === 'hybridBond' ? '#3b82f6' : box.kind === 'piP' || box.kind === 'piD' ? '#f59e0b' : 'var(--text2)'
  return <div class="col gap4" style={{ alignItems: 'center' }}><div class="boxes"><div class="obox" aria-label={t('{label}: {n} electrons', { label: box.label, n: box.electrons })} style={{ width: 44, height: 40, borderRadius: 4, border: `1.5px solid ${col}`, fontSize: 17, fontWeight: 700 }}>{box.electrons >= 1 ? '↑' : ''}{box.electrons >= 2 ? '↓' : ''}</div></div><span class="small dim" style={{ fontSize: 10 }}>{box.label}</span></div>
}
export function AtomDiagram({ h, title }: { h: Hybridization; title?: string }) {
  const rows: [string, string][] = [
    ['Electron domains', t('{n} ({sigma} σ bonds + {lp} lone pairs)', { n: h.steric, sigma: h.sigma, lp: h.lonePairs })], ['Electron geometry', h.electronGeometry ? t(h.electronGeometry) : '—'],
    ['Molecular shape', h.shape ? t(h.shape.name) : '—'], ['Ideal bond angle', h.shape ? t(h.shape.angle) : '—'], ['π bonds', String(h.pi)],
    ['Valence electrons', h.charge === 0 ? String(h.valence) : t('{n} (formal charge {charge})', { n: h.valence, charge: (h.charge > 0 ? '+' : '−') + Math.abs(h.charge) })]]
  let explanation = t('Each σ bond is an end-to-end overlap of an {hybrid} orbital with an orbital from the bonded atom.', { hybrid: h.hybridName ?? 'hybrid' })
  if (h.lonePairs > 0) explanation += ' ' + t('Lone pairs sit in hybrid orbitals too, and because they take up more room than bonding pairs they squeeze the bond angles below the ideal value.')
  if (h.pi > 0) explanation += ' ' + (h.pi === 1 ? t('The π bond comes from side-on overlap of an unhybridized {shell}p orbital.', { shell: h.shell }) : t('The {n} π bonds come from side-on overlap of unhybridized {shell}p orbitals.', { n: h.pi, shell: h.shell }))
  const boxes = (title: string, bs: Box[]) => <div class="col gap4"><span class="label">{title}</span><div class="row" style={{ alignItems: 'flex-start', gap: 6 }}>{bs.map((b, i) => <BoxView key={i} box={b} />)}</div></div>
  return <div class="col" style={{ gap: 16 }}>
    <div class="row wrap gap16" style={{ alignItems: 'flex-start' }}>
      <div class="col gap4"><span class="small dim">{title ?? t(h.element.name)}</span><span style={{ fontSize: 44, fontWeight: 700 }}>{h.hybridName}</span><span class="dim">{t("hybridized")}</span></div>
      <div class="kv">{rows.flatMap(([k, v]) => [<div key={k}>{t(k)}</div>, <b key={k + 'v'} style={{ fontWeight: 600, color: 'var(--text)' }}>{v}</b>])}</div></div>
    <Card title={t("Orbital diagram")}><div class="col" style={{ gap: 14 }}>{boxes(t('Ground state'), h.groundState)}
      <div class="row gap8 dim"><span>↓</span><span>{h.needsPromotion ? (h.mix.d > 0 ? t('promote electrons, then mix s, p, d orbitals') : t('promote electrons, then mix s, p orbitals')) : t('mix the s and p orbitals')}</span></div>{boxes(t('After hybridization'), h.hybridized)}</div></Card>
    <div class="dim">{explanation}</div></div>
}

// MARK: predict
const presets: [string, string, number, number][] = [['CH₄ – carbon', 'C', 4, 0], ['NH₃ – nitrogen', 'N', 3, 0], ['H₂O – oxygen', 'O', 2, 0], ['BF₃ – boron', 'B', 3, 0], ['BeCl₂ – beryllium', 'Be', 2, 0], ['C₂H₄ – carbon', 'C', 3, 1],
  ['CO₂ – carbon', 'C', 2, 2], ['SO₂ – sulfur', 'S', 2, 2], ['SF₄ – sulfur', 'S', 4, 0], ['ClF₃ – chlorine', 'Cl', 3, 0], ['PCl₅ – phosphorus', 'P', 5, 0], ['SF₆ – sulfur', 'S', 6, 0], ['XeF₄ – xenon', 'Xe', 4, 0]]
const mainGroup = elements.filter(e => Hybridization.valenceElectrons(e) != null && e.z !== 1)
function Stepper({ label, value, min, max, onChange }: { label: string; value: number; min: number; max: number; onChange: (v: number) => void }) {
  return <span class="row gap8" role="group" aria-label={label}>{label}: <b>{value}</b><button class="btn small" aria-label={t('Decrease {label}', { label })} disabled={value <= min} onClick={() => onChange(value - 1)}>−</button><button class="btn small" aria-label={t('Increase {label}', { label })} disabled={value >= max} onClick={() => onChange(value + 1)}>+</button></span>
}
function PredictMode() {
  const [symbol, setSymbol] = useState('C'), [sigma, setSigma] = useState(4), [pi, setPi] = useState(0)
  const e = elementBySymbol.get(symbol), r = e ? Hybridization.make(e, sigma, pi) : null
  return <div class="scroll pad col" style={{ maxWidth: 900 }}>
    <div class="dim">{t("Choose a central atom and how many bonds it makes. Theory works out the lone pairs, hybridization and shape.")}</div>
    <div class="row wrap gap16"><select aria-label={t("Atom")} value={symbol} onChange={ev => setSymbol((ev.target as HTMLSelectElement).value)}>{mainGroup.map(x => <option key={x.symbol} value={x.symbol}>{x.symbol} – {t(x.name)}</option>)}</select>
      <Stepper label={t("σ bonds")} value={sigma} min={0} max={7} onChange={setSigma} /><Stepper label={t("π bonds")} value={pi} min={0} max={4} onChange={setPi} />
      <select aria-label={t("Examples")} value="" onChange={ev => { const p = presets.find(x => x[0] === (ev.target as HTMLSelectElement).value); if (p) { setSymbol(p[1]); setSigma(p[2]); setPi(p[3]) } }}><option value="">{t("Examples")}</option>{presets.map(p => <option key={p[0]} value={p[0]}>{t(p[0])}</option>)}</select></div>
    {r && r.hybridName ? <AtomDiagram h={r} /> : e && Hybridization.valenceElectrons(e) != null && <div class="warn" role="alert">⚠ {r == null ? t('{symbol} has {v} valence electrons. {sigma} σ + {pi} π bonds use {used}, and the rest must pair up as lone pairs, so this bonding is not possible for a neutral atom.', { symbol: e.symbol, v: Hybridization.valenceElectrons(e)!, sigma, pi, used: sigma + pi }) : t('At least two electron domains (bonds plus lone pairs) are needed to hybridize.')}</div>}
  </div>
}

// MARK: molecules
function MoleculeMode() {
  const user = useStore(userMolecules), all = useMemo(() => [...user.items, ...moleculeLibrary], [user.items])
  const [sel, setSel] = useState(all[0]?.name ?? ''), [atom, setAtom] = useState<number | null>(null)
  useEffect(() => { if (user.focus) { setSel(user.focus); setAtom(null); userMolecules.set(s => ({ ...s, focus: null })) } }, [user.focus])
  const m: Molecule | undefined = all.find(x => x.name === sel) ?? all[0]
  return <div class="split" style={{ gridTemplateColumns: '210px 1fr' }}>
    <div class="list" role="listbox" aria-label={t("Molecules")}>{all.map(x => <button key={x.name} role="option" aria-selected={x.name === sel} class={x.name === sel ? 'on' : ''} onClick={() => { setSel(x.name); setAtom(null) }}>{t(x.name)}</button>)}</div>
    <div class="scroll pad">{m ? <MoleculeDetail m={m} atom={atom} setAtom={setAtom} /> : <div class="dim">{t("No molecule")}</div>}</div></div>
}
function MoleculeDetail({ m, atom, setAtom }: { m: Molecule; atom: number | null; setAtom: (i: number) => void }) {
  const a = useMemo(() => analyzeMolecule(m), [m]), heavy = a.atoms.filter(x => x.element?.symbol !== 'H')
  const chosen = heavy.find(x => x.index === atom) ?? heavy.find(x => x.hybrid?.hybridName != null) ?? heavy[0]
  return <div class="col" style={{ maxWidth: 900 }}>
    <div class="row" style={{ alignItems: 'baseline', gap: 12 }}><h1>{t(m.name)}</h1><span class="mono dim" style={{ fontSize: 17 }}>{formulaText(formulaOf(m))}</span></div>
    <div class="dim">{t("Pick an atom to see how its orbitals hybridize.")}</div>
    <div class="row wrap gap8">{heavy.map(x => <button key={x.index} class={'btn' + (x.index === chosen?.index ? ' primary' : '')} style={{ padding: '3px 10px', lineHeight: 1.2 }} onClick={() => setAtom(x.index)}><div class="bold">{x.label}</div><div style={{ fontSize: 10 }}>{(x.hybrid?.hybridName ?? '—') + (x.hybrid ? chargeText(x.hybrid.charge) : '')}</div></button>)}</div>
    {chosen && (chosen.hybrid?.hybridName ? <><AtomDiagram h={chosen.hybrid} title={chosen.label} />
      {chosen.measuredAngles.length > 0 && <Card title={t("Bond angles in this structure")}><div class="col gap4"><span class="dim">{t('Predicted: {angle}', { angle: chosen.hybrid.shape ? t(chosen.hybrid.shape.angle) : '—' })}</span><span class="mono">{t('Measured from the 3D file: {angles}', { angles: chosen.measuredAngles.map(x => x.toFixed(1) + '°').join(', ') })}</span></div></Card>}</>
      : <div class="dim">ⓘ {chosen.note ?? t("Hybridization isn't defined for this atom.")}</div>)}
    <Card title={t("Every bond")}><table class="t"><tbody>{a.bonds.map(b => <tr key={b.id}><td class="mono">{b.label}</td><td>{b.detail}</td></tr>)}</tbody></table></Card>
    <div class="small dim">{t("Terminal atoms are hybridized by counting their bonds plus lone pairs, the same rule used for central atoms.")}</div></div>
}

// MARK: resonance
const frac3 = (v: number) => Math.abs(v - 2 / 3) < 0.01 ? '⅔' : Math.abs(v - 1 / 3) < 0.01 ? '⅓' : Math.abs(v - 0.5) < 0.01 ? '½' : String(Number(v.toFixed(2)))

export function LewisCanvas({ input, orders, lonePairs, charges, showLonePairs, width, height }: { input: ResonanceInput; orders: number[]; lonePairs: number[]; charges: number[]; showLonePairs: boolean; width: number; height: number }) {
  return <Canvas class="lewis" style={{ width, height }} label={t('Lewis structure of {name}', { name: t(input.name) })} deps={[input, orders, lonePairs, charges, showLonePairs]} draw={(ctx, w, h) => {
    const text = cssVar('--text') || '#111', accent = cssVar('--accent') || '#2f6bff'
    const xs = input.atoms.map(a => a.x), ys = input.atoms.map(a => a.y), minX = Math.min(...xs), maxX = Math.max(...xs), minY = Math.min(...ys), maxY = Math.max(...ys)
    const span = Math.max(maxX - minX, maxY - minY, 0.5), scale = Math.min(w, h) * 0.62 / span, cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
    const pos = (i: number) => ({ x: w / 2 + (input.atoms[i].x - cx) * scale, y: h / 2 + (input.atoms[i].y - cy) * scale })
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'
    input.bonds.forEach((b, k) => {
      const p = pos(b[0]), q = pos(b[1]), dx = q.x - p.x, dy = q.y - p.y, len = Math.max(1, Math.hypot(dx, dy)), ux = dx / len, uy = dy / len
      const trim = input.atoms[b[0]].symbol === 'H' || input.atoms[b[1]].symbol === 'H' ? 9 : 12, order = orders[k] ?? 1, whole = Math.floor(order), fr = order - whole
      const lines = Math.max(1, Math.round(order) === order ? order : whole + 1)
      for (let l = 0; l < lines; l++) {
        const off = (l - (lines - 1) / 2) * 5, dashed = fr > 0.001 && l === lines - 1
        ctx.strokeStyle = text; ctx.globalAlpha = dashed ? 0.55 : 0.9; ctx.lineWidth = 2; ctx.lineCap = 'round'; ctx.setLineDash(dashed ? [4, 3] : [])
        ctx.beginPath(); ctx.moveTo(p.x + ux * trim - uy * off, p.y + uy * trim + ux * off); ctx.lineTo(q.x - ux * trim - uy * off, q.y - uy * trim + ux * off); ctx.stroke()
      }
      ctx.globalAlpha = 1; ctx.setLineDash([])
      if (Math.round(order) !== order) { ctx.fillStyle = accent; ctx.font = '10px system-ui'; ctx.fillText(order.toFixed(2), (p.x + q.x) / 2 - uy * 13, (p.y + q.y) / 2 + ux * 13) }
    })
    input.atoms.forEach((at, i) => {
      const p = pos(i); ctx.fillStyle = text; ctx.font = 'bold 19px system-ui'; ctx.fillText(at.symbol, p.x, p.y)
      if (showLonePairs && lonePairs[i] != null && at.symbol !== 'H') {
        let ax = 0, ay = 0; for (const b of input.bonds) if (b[0] === i || b[1] === i) { const q = pos(b[0] === i ? b[1] : b[0]); ax += p.x - q.x; ay += p.y - q.y }
        const base = Math.atan2(ay, ax), n = lonePairs[i]
        for (let k = 0; k < n; k++) {
          const a = base + (n === 1 ? 0 : (k - (n - 1) / 2) * 0.95), c = { x: p.x + Math.cos(a) * 19, y: p.y + Math.sin(a) * 19 }, px = -Math.sin(a) * 3, py = Math.cos(a) * 3
          for (const s of [-1, 1]) { ctx.beginPath(); ctx.arc(c.x + px * s, c.y + py * s, 1.8, 0, 7); ctx.fill() }
        }
      }
      const ch = charges[i]
      if (ch != null && Math.abs(ch) > 0.001) {
        const label = Math.round(ch) === ch ? (Math.abs(ch) === 1 ? (ch > 0 ? '+' : '−') : `${Math.abs(ch)}${ch > 0 ? '+' : '−'}`) : (ch > 0 ? '+' : '−') + frac3(Math.abs(ch)), corner = { x: p.x + 15, y: p.y - 15 }
        ctx.strokeStyle = ctx.fillStyle = ch > 0 ? '#3b82f6' : '#e5484d'; ctx.lineWidth = 1.3; ctx.beginPath(); ctx.arc(corner.x, corner.y, 8, 0, 7); ctx.stroke(); ctx.font = 'bold 9px system-ui'; ctx.fillText(label, corner.x, corner.y)
      }
    })
  }} />
}

function ResonanceMode() {
  const [name, setName] = useState('Nitrate')
  const input = resonancePresets.find(p => p.name === name) ?? resonancePresets[0], ss: LewisStructure[] = resonanceStructures(input) ?? []
  const nb: number[][] = input.atoms.map(() => []); for (const [a, b] of input.bonds) { nb[a].push(b); nb[b].push(a) }
  const electrons = input.atoms.reduce((s, a) => s + (Hybridization.valenceElectrons(elementBySymbol.get(a.symbol)!) ?? 0), 0) - input.charge
  return <div class="split" style={{ gridTemplateColumns: '250px 1fr' }}>
    <div class="list" role="listbox" aria-label={t("Species")}>{resonancePresets.map(p => <button key={p.name} role="option" aria-selected={p.name === name} class={p.name === name ? 'on' : ''} onClick={() => setName(p.name)}>{t(p.name)}<span class="grow" /><span class="dim">{p.formula}</span></button>)}</div>
    <div class="scroll pad col" style={{ maxWidth: 900 }}>
      <div class="row" style={{ alignItems: 'baseline', gap: 10 }}><h1>{t(input.name)}</h1><span class="dim" style={{ fontSize: 20 }}>{input.formula}</span></div>
      {!ss.length ? <div class="warn">{t("⚠ No valid Lewis structure found.")}</div> : <>
        <div class="dim">{t('{n} valence electrons in total ({charge}). The structures shown are all the ways to place the bonds and lone pairs that keep formal charges as small as possible while giving each second-period atom a full octet.', { n: electrons, charge: input.charge === 0 ? t('neutral') : t('charge {c}', { c: (input.charge > 0 ? '+' : '−') + Math.abs(input.charge) }) })}</div>
        <h3>{ss.length === 1 ? t('Lewis structure') : t('{n} resonance structures', { n: ss.length })}</h3>
        <div class="row wrap gap16" style={{ alignItems: 'flex-start' }}>{ss.map((s, i) => <div key={i} class="col gap4" style={{ alignItems: 'center' }}><LewisCanvas input={input} orders={s.orders} lonePairs={s.lonePairs} charges={s.charges} showLonePairs width={190} height={170} />{ss.length > 1 && <span class="small dim">{t('Structure {n}', { n: i + 1 })}</span>}</div>)}</div>
        {ss.length > 1 && <><h3>{t("The real molecule is a blend of all of them, a resonance hybrid:")}</h3><LewisCanvas input={input} orders={hybridOrders(ss)} lonePairs={[]} charges={averageCharges(ss)} showLonePairs={false} width={260} height={230} />
          <div class="small dim">{t("Numbers on the bonds are average bond orders; charges are averaged over the structures. Equal bond lengths in the real molecule show that the structures are not flipping back and forth.")}</div></>}
        <Card title={t("Hybridization of each atom")}><table class="t"><thead><tr><th>{t("Atom")}</th><th>{t("Bonds (σ)")}</th><th>{t("Lone pairs")}</th><th>{t("Hybridization")}</th></tr></thead><tbody>
          {input.atoms.map((a, i) => ({ a, i })).filter(x => x.a.symbol !== 'H').map(({ a, i }) => {
            const pis = ss.map(s => input.bonds.reduce((t, b, k) => (b[0] === i || b[1] === i ? t + s.orders[k] - 1 : t), 0)), deloc = new Set(pis).size > 1
            const h = Hybridization.make(elementBySymbol.get(a.symbol)!, nb[i].length, pis[0], ss[0].charges[i]), lps = [...new Set(ss.map(s => s.lonePairs[i]))].sort()
            return <tr key={i}><td class="bold">{a.symbol}{i + 1}</td><td>{nb[i].length}</td><td>{lps.join(' or ')}</td><td>{deloc ? t('sp² (one p orbital is part of the π system shared by the structures)') : h?.hybridName ? h.hybridName + (h.charge === 0 ? '' : ' ' + t('(formal charge {charge})', { charge: (h.charge > 0 ? '+' : '−') + Math.abs(h.charge) })) : '—'}</td></tr> })}</tbody></table></Card></>}
    </div></div>
}
