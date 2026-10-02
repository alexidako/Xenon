import { useEffect, useMemo, useRef, useState } from 'preact/hooks'
import { Molecule, moleculeLibrary, formulaOf, massOf, loadMolecule, exportMolecule, Format } from '../lib/molecule'
import { analyzeMolecule } from '../lib/vbt'
import { formulaText } from '../lib/markup'
import { formatNumber } from '../lib/format'
import { OverlayMode, overlayModes } from '../lib/molorb'
import { buildMoleculeScene, molStyles, MolStyle } from '../lib/molscene'
import { optimizeAsync } from '../lib/optimizeAsync'
import { downloadText } from '../lib/export'
import { userMolecules } from '../lib/usermol'
import { jump } from '../lib/nav'
import { useStore } from '../lib/store'
import { Page, Segmented, Select, Check } from '../ui/kit'
import { Scene3D } from '../ui/Scene3D'

export function MoleculesScreen() {
  const user = useStore(userMolecules), j = useStore(jump)
  const [imported, setImported] = useState<Molecule[]>([]), [optimized, setOptimized] = useState<Record<string, Molecule>>({})
  const [sel, setSel] = useState<string>(moleculeLibrary[0]?.name ?? '')
  const [style, setStyle] = useState<MolStyle>('Ball & stick'), [orbitals, setOrbitals] = useState<OverlayMode>('Off'), [angles, setAngles] = useState(false)
  const [shown, setShown] = useState<Set<number>>(new Set()), [reset, setReset] = useState(0), [msg, setMsg] = useState(''), [busy, setBusy] = useState(false)
  const file = useRef<HTMLInputElement>(null)
  const all = useMemo(() => [...user.items, ...imported, ...moleculeLibrary], [user.items, imported])
  const names = all.map(m => m.name)
  useEffect(() => { if (user.focus && names.includes(user.focus)) { setSel(user.focus); userMolecules.set(s => ({ ...s, focus: null })) } }, [user.focus])
  useEffect(() => { if (j.molecule && names.includes(j.molecule)) { setSel(j.molecule); jump.set(x => ({ ...x, molecule: null })) } }, [j.molecule])
  const base = all.find(m => m.name === sel) ?? all[0]
  const current = base ? optimized[base.name] ?? base : undefined
  useEffect(() => { setShown(new Set()) }, [sel])

  const heavy = useMemo(() => current ? analyzeMolecule(current).atoms.filter(a => a.element?.symbol !== 'H') : [], [current])
  const key = `${current?.name}|${style}|${orbitals}|${[...shown].sort()}|${angles}|${current ? optimized[current.name] ? 1 : 0 : 0}`
  const scene = useMemo(() => current ? buildMoleculeScene(current, { style, orbitals, atoms: shown, angles }) : null, [key])

  const optimize = async () => {
    if (!current || !base) return
    setBusy(true); setMsg('Searching for the lowest-energy shape…')
    const r = await optimizeAsync(current)
    setOptimized(o => ({ ...o, [base.name]: r.molecule })); setBusy(false); setReset(n => n + 1)
    setMsg(`Lowest-energy shape: ${r.energyBefore.toFixed(1)} → ${r.energyAfter.toFixed(1)} kcal/mol (${r.starts} starting shapes tried)`)
  }
  const onFile = async (e: Event) => {
    const f = (e.target as HTMLInputElement).files?.[0]; if (!f) return
    const m = loadMolecule(await f.text(), f.name)
    if (m) { setImported(x => [m, ...x]); setSel(m.name); setMsg('') } else setMsg(`Could not read ${f.name}`)
    ;(e.target as HTMLInputElement).value = ''
  }
  const save = async (f: Format) => { if (!current) return; const file = `${current.name.replace(/ /g, '_')}.${f}`; setMsg((await downloadText(file, exportMolecule(current, f))) ? `Saved ${file}` : 'Not saved') }
  const toggleAtom = (i: number) => { const n = new Set(shown); n.has(i) ? n.delete(i) : n.add(i); setShown(n) }

  return <Page title="Molecules">
    <div class="split" style={{ gridTemplateColumns: '220px 1fr' }}>
      <div class="list" role="listbox" aria-label="Molecules">{all.map(m => <button key={m.name} role="option" aria-selected={m.name === sel} class={m.name === sel ? 'on' : ''} onClick={() => setSel(m.name)}>{m.name}{optimized[m.name] && <span class="dim small">optimized</span>}</button>)}</div>
      <div class="col" style={{ gap: 0, minHeight: 0 }}>
        <div class="toolbar" style={{ flexDirection: 'column', alignItems: 'stretch' }}>
          <div class="row wrap gap16"><Segmented value={style} options={molStyles} onChange={setStyle} label="Style" />
            <label class="row gap8" title="Show the σ bonds, lone pairs and π bonds as orbital lobes">Orbitals <Select<OverlayMode> value={orbitals} options={overlayModes} onChange={setOrbitals} label="Orbitals" /></label>
            <span title="Draw an arc and the angle in degrees at every pair of bonds"><Check checked={angles} onChange={setAngles}>Bond angles</Check></span></div>
          <div class="row wrap gap8"><button class="btn" title="Drag to rotate · scroll or pinch to zoom · double-click to reset" onClick={() => setReset(n => n + 1)}>↺ Reset view</button>
            {current && base && optimized[base.name] && <button class="btn" title="Go back to the geometry the file came with" onClick={() => { setOptimized(o => { const n = { ...o }; delete n[base.name]; return n }); setMsg('Original geometry restored') }}>Revert</button>}
            <button class="btn" disabled={busy || !current || current.atoms.length < 2} onClick={optimize}
              title="Rearrange the atoms into the most stable 3D shape: it tries many starting shapes (every rotatable bond, ring puckers) and keeps the lowest-energy one. Uses a simplified force field, not quantum chemistry.">{busy ? 'Optimizing…' : '✦ Optimize geometry'}</button>
            <span class="grow" /><button class="btn" onClick={() => file.current?.click()}>Open file…</button><input ref={file} type="file" accept=".cml,.mol,.sdf,.xyz" hidden onChange={onFile} />
            <select aria-label="Convert" value="" disabled={!current} onChange={e => { const v = (e.target as HTMLSelectElement).value as Format; if (v) save(v) }}><option value="">Convert…</option>{(['cml', 'mol', 'xyz'] as Format[]).map(f => <option key={f} value={f}>Save as .{f}</option>)}</select></div>
        </div>
        {(orbitals !== 'Off' || angles) && current && <div class="row wrap gap8 banner" style={{ borderTop: 0 }}><span class="small dim">{orbitals !== 'Off' && angles ? 'Show orbitals and angles of' : angles ? 'Show angles of' : 'Show orbitals of'}</span>
          <button class={'chip' + (shown.size === 0 ? ' on' : '')} onClick={() => setShown(new Set())}>All</button>
          {heavy.map(a => <button key={a.index} class={'chip' + (shown.has(a.index) ? ' on' : '')} onClick={() => toggleAtom(a.index)}>{a.label}</button>)}</div>}
        <div style={{ flex: 1, minHeight: 0 }}>{scene && current ? <Scene3D build={() => scene.group} distance={scene.distance} resetToken={reset} sceneKey={key} label={`3D model of ${current.name}`} /> : <div class="dim center pad">No molecule loaded</div>}</div>
        {current && <div class="row gap16 pad" style={{ padding: '10px 14px', borderTop: '1px solid var(--line)' }}><b>{current.name}</b><span class="mono">{formulaText(formulaOf(current))}</span><span>{formatNumber(massOf(current))} u</span>
          <span class="dim">{current.atoms.length} atoms, {current.bonds.length} bonds</span><span class="grow" />{msg && <span class="small dim" role="status">{msg}</span>}</div>}
      </div>
    </div>
  </Page>
}
