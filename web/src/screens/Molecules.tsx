import { useEffect, useMemo, useRef, useState } from 'preact/hooks'
import { Molecule, moleculeLibrary, formulaOf, massOf, loadMolecule, exportMolecule, Format } from '../lib/molecule'
import { analyzeMolecule } from '../lib/vbt'
import { formulaText } from '../lib/markup'
import { formatNumber } from '../lib/format'
import { OverlayMode, overlayModes } from '../lib/molorb'
import { buildMoleculeScene, molStyles, MolStyle } from '../lib/molscene'
import { optimizeAsync } from '../lib/optimizeAsync'
import { downloadText } from '../lib/export'
import { userMolecules, removeUserMolecule } from '../lib/usermol'
import { jump } from '../lib/nav'
import { useStore } from '../lib/store'
import { Page, Segmented, Select, Check } from '../ui/kit'
import { Scene3D } from '../ui/Scene3D'
import { t, tc } from '../i18n'

export function MoleculesScreen() {
  const user = useStore(userMolecules), j = useStore(jump)
  const [imported, setImported] = useState<Molecule[]>([]), [optimized, setOptimized] = useState<Record<string, Molecule>>({})
  const [sel, setSel] = useState<string>(moleculeLibrary[0]?.name ?? '')
  const [style, setStyle] = useState<MolStyle>('Ball & stick'), [orbitals, setOrbitals] = useState<OverlayMode>('Off'), [angles, setAngles] = useState(false)
  const [shown, setShown] = useState<Set<number>>(new Set()), [reset, setReset] = useState(0), [msg, setMsg] = useState(''), [busy, setBusy] = useState(false)
  const [confirming, setConfirming] = useState<Molecule | null>(null)
  const file = useRef<HTMLInputElement>(null)
  const all = useMemo(() => [...user.items, ...imported, ...moleculeLibrary], [user.items, imported])
  const names = all.map(m => m.name)
  useEffect(() => { if (user.focus && names.includes(user.focus)) { setSel(user.focus); userMolecules.set(s => ({ ...s, focus: null })) } }, [user.focus])
  useEffect(() => { if (j.molecule && names.includes(j.molecule)) { setSel(j.molecule); jump.set(x => ({ ...x, molecule: null })) } }, [j.molecule])
  const base = all.find(m => m.name === sel) ?? all[0]
  /** Molecules you made in the editor or opened from a file can be deleted; the bundled ones cannot. */
  const isCustom = (m?: Molecule) => !!m && (user.items.includes(m) || imported.includes(m))
  const current = base ? optimized[base.name] ?? base : undefined
  useEffect(() => { setShown(new Set()) }, [sel])

  const heavy = useMemo(() => current ? analyzeMolecule(current).atoms.filter(a => a.element?.symbol !== 'H') : [], [current])
  const key = `${current?.name}|${style}|${orbitals}|${[...shown].sort()}|${angles}|${current ? optimized[current.name] ? 1 : 0 : 0}`
  const scene = useMemo(() => current ? buildMoleculeScene(current, { style, orbitals, atoms: shown, angles }) : null, [key])

  const optimize = async () => {
    if (!current || !base) return
    setBusy(true); setMsg(t('Searching for the lowest-energy shape…'))
    const r = await optimizeAsync(current)
    setOptimized(o => ({ ...o, [base.name]: r.molecule })); setBusy(false); setReset(n => n + 1)
    setMsg(t('Lowest-energy shape: {before} → {after} kcal/mol ({n} starting shapes tried)', { before: r.energyBefore.toFixed(1), after: r.energyAfter.toFixed(1), n: r.starts }))
  }
  const onFile = async (e: Event) => {
    const f = (e.target as HTMLInputElement).files?.[0]; if (!f) return
    const m = loadMolecule(await f.text(), f.name)
    if (m) { setImported(x => [m, ...x]); setSel(m.name); setMsg('') } else setMsg(t('Could not read {name}', { name: f.name }))
    ;(e.target as HTMLInputElement).value = ''
  }
  const save = async (f: Format) => { if (!current) return; const file = `${current.name.replace(/ /g, '_')}.${f}`; setMsg((await downloadText(file, exportMolecule(current, f))) ? t('Saved {file}', { file }) : t('Not saved')) }
  const remove = (m: Molecule) => {
    const i = all.indexOf(m), neighbour = all[i + 1] ?? all[i - 1]
    removeUserMolecule(m); setImported(x => x.filter(y => y !== m))
    // an optimization is stored under the name; drop it unless another molecule still uses that name
    if (!all.some(o => o !== m && o.name === m.name)) setOptimized(o => { const n = { ...o }; delete n[m.name]; return n })
    if (neighbour) setSel(neighbour.name)
    setConfirming(null); setShown(new Set()); setMsg(`Deleted “${m.name}”`)
  }
  const toggleAtom = (i: number) => { const n = new Set(shown); n.has(i) ? n.delete(i) : n.add(i); setShown(n) }

  return <Page title={t("Molecules")}>
    <div class="split" style={{ gridTemplateColumns: '220px 1fr' }}>
      <div class="list" role="listbox" aria-label={t("Molecules")} onKeyDown={e => { if ((e.key === 'Delete' || e.key === 'Backspace') && isCustom(base)) { e.preventDefault(); setConfirming(base) } }}>{all.map((m, i) => <button key={i} role="option" aria-selected={m === base} class={m === base ? 'on' : ''} onClick={() => { setSel(m.name); setConfirming(null) }}>{t(m.name)}{optimized[m.name] && <span class="dim small">{t("optimized")}</span>}{isCustom(m) && <span class="dim small" title={t("Made by you")} aria-label={t("made by you")} style={{ marginLeft: 'auto' }}>{t("● yours")}</span>}</button>)}</div>
      <div class="col" style={{ gap: 0, minHeight: 0 }}>
        <div class="toolbar" style={{ flexDirection: 'column', alignItems: 'stretch' }}>
          <div class="row wrap gap16"><Segmented value={style} options={molStyles} onChange={setStyle} label={t("Style")} />
            <label class="row gap8" title={t("Show the σ bonds, lone pairs and π bonds as orbital lobes")}>{t("Orbitals")} <Select<OverlayMode> value={orbitals} options={overlayModes} onChange={setOrbitals} label={t("Orbitals")} /></label>
            <span title={t("Draw an arc and the angle in degrees at every pair of bonds")}><Check checked={angles} onChange={setAngles}>{t("Bond angles")}</Check></span></div>
          <div class="row wrap gap8"><button class="btn" title={t("Drag to rotate · scroll or pinch to zoom · double-click to reset")} onClick={() => setReset(n => n + 1)}>{t("↺ Reset view")}</button>
            {current && base && optimized[base.name] && <button class="btn" title={t("Go back to the geometry the file came with")} onClick={() => { setOptimized(o => { const n = { ...o }; delete n[base.name]; return n }); setMsg(t('Original geometry restored')) }}>{t("Revert")}</button>}
            <button class="btn" disabled={busy || !current || current.atoms.length < 2} onClick={optimize}
              title={t("Rearrange the atoms into the most stable 3D shape: it tries many starting shapes (every rotatable bond, ring puckers) and keeps the lowest-energy one. Uses a simplified force field, not quantum chemistry.")}>{busy ? t('Optimizing…') : t('✦ Optimize geometry')}</button>
            {isCustom(base) && <button class="btn danger" title={t("Delete this molecule from the list. Molecules you made yourself can be deleted; the built-in ones cannot.")} onClick={() => setConfirming(base!)}>{t("🗑 Delete")}</button>}
            <span class="grow" /><button class="btn" onClick={() => file.current?.click()}>{t("Open file…")}</button><input ref={file} type="file" accept=".cml,.mol,.sdf,.xyz" hidden onChange={onFile} />
            <select aria-label={t("Convert")} value="" disabled={!current} onChange={e => { const v = (e.target as HTMLSelectElement).value as Format; if (v) save(v) }}><option value="">{t("Convert…")}</option>{(['cml', 'mol', 'xyz'] as Format[]).map(f => <option key={f} value={f}>{t('Save as .{ext}', { ext: f })}</option>)}</select></div>
        </div>
        {confirming && <div class="row wrap gap8 banner" role="alertdialog" aria-label={`Delete ${confirming.name}?`} style={{ borderTop: 0, background: 'rgba(229,72,77,.12)' }}>
          <b>{t('Delete “{name}”?', { name: t(confirming.name) })}</b><span class="dim small">{t("It disappears from the Molecules and Valence Bond lists and can't be brought back. Use Convert… first if you want a file copy.")}</span>
          <span class="grow" /><button class="btn" autoFocus onClick={() => setConfirming(null)}>{t("Cancel")}</button><button class="btn danger" onClick={() => remove(confirming)}>{t("Delete")}</button></div>}
        {(orbitals !== 'Off' || angles) && current && <div class="row wrap gap8 banner" style={{ borderTop: 0 }}><span class="small dim">{orbitals !== 'Off' && angles ? t('Show orbitals and angles of') : angles ? t('Show angles of') : t('Show orbitals of')}</span>
          <button class={'chip' + (shown.size === 0 ? ' on' : '')} onClick={() => setShown(new Set())}>{t("All")}</button>
          {heavy.map(a => <button key={a.index} class={'chip' + (shown.has(a.index) ? ' on' : '')} onClick={() => toggleAtom(a.index)}>{a.label}</button>)}</div>}
        <div style={{ flex: 1, minHeight: 0 }}>{scene && current ? <Scene3D build={() => scene.group} distance={scene.distance} resetToken={reset} sceneKey={key} label={t('3D model of {name}', { name: t(current.name) })} /> : <div class="dim center pad">{t("No molecule loaded")}</div>}</div>
        {current && <div class="row gap16 pad" style={{ padding: '10px 14px', borderTop: '1px solid var(--line)' }}><b>{t(current.name)}</b><span class="mono">{formulaText(formulaOf(current))}</span><span>{formatNumber(massOf(current))} {tc('unit', 'u')}</span>
          <span class="dim">{t('{atoms} atoms, {bonds} bonds', { atoms: current.atoms.length, bonds: current.bonds.length })}</span><span class="grow" />{msg && <span class="small dim" role="status">{msg}</span>}</div>}
      </div>
    </div>
  </Page>
}
