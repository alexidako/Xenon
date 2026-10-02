import { useMemo, useState } from 'preact/hooks'
import { elements, isotopesByElement, elementByZ, halfLifeText, Isotope } from '../lib/element'
import { parseFormula, countMass, builtInAliases, userAliases, setUserAliases, allAliases } from '../lib/formula'
import { formatNumber, Units, toBase, fromBase } from '../lib/format'
import { solveGas, GasSolve, soluteMassFrom, concentrations, requiredSolute, concKinds, ConcKind, SoluteKind, SolventKind, Solution, solveDecay, DecaySolve, bestTimeUnit, theoryCurve, fitTitration } from '../lib/calc'
import { Card, KV, Page, Quantity, Segmented, Select, NumInput, Field } from '../ui/kit'
import { SeriesChart } from '../ui/chart'
import { t, tc } from '../i18n'

const kinds = ['Molecular mass', 'Gas', 'Concentration', 'Nuclear decay', 'Titration'] as const
type Kind = typeof kinds[number]
const Warn = ({ children }: { children: string }) => <div class="warn" role="alert">⚠ {children}</div>

export function CalculatorsScreen() {
  const [kind, setKind] = useState<Kind>('Molecular mass')
  return <Page title={t("Calculators")} toolbar={<Segmented value={kind} options={kinds} onChange={setKind} label={t("Calculator")} />}>
    <div class="scroll pad" style={{ maxWidth: kind === 'Titration' ? 'none' : 720 }}>
      {kind === 'Molecular mass' && <MolMass />}{kind === 'Gas' && <Gas />}{kind === 'Concentration' && <Concentration />}{kind === 'Nuclear decay' && <Nuclear />}{kind === 'Titration' && <Titration />}
    </div></Page>
}

function MolMass() {
  const [formula, setFormula] = useState('Ca(OH)2'), [alias, setAlias] = useState(''), [exp, setExp] = useState(''), [msg, setMsg] = useState(''), [, bump] = useState(0)
  const parsed = parseFormula(formula), total = parsed?.reduce((s, c) => s + countMass(c), 0) ?? 0
  const aliases = allAliases(), user = userAliases()
  const add = () => {
    if (alias.length < 2) return setMsg(t('A symbol needs two or more letters.'))
    if (parseFormula(alias)) return setMsg(t('That symbol is already used.'))
    if (!parseFormula(exp)) return setMsg(t('The expansion is not a valid formula.'))
    setUserAliases({ ...user, [alias]: exp }); setAlias(''); setExp(''); setMsg(t('Added.')); bump(n => n + 1)
  }
  return <div class="col">
    <Card title={t("Formula")}><div class="col gap8"><input type="text" class="mono" style={{ fontSize: 18 }} aria-label={t("Formula")} placeholder={t("e.g. Ca(OH)2 or EtOH")} value={formula} onInput={e => setFormula((e.target as HTMLInputElement).value)} />
      <div class="small dim">{t("Use element symbols, parentheses and counts. Aliases such as Et, Me and Ph are expanded.")}</div></div></Card>
    {parsed ? <Card title={t("Result")}><div class="col">
      <div class="row" style={{ justifyContent: 'space-between' }}><span>{t("Molecular mass")}</span><b style={{ fontSize: 22, userSelect: 'text' }}>{Number(total.toFixed(4)).toLocaleString('en-US', { maximumFractionDigits: 4 })} {tc('unit', 'u')}</b></div>
      <table class="t"><thead><tr><th>{t("Element")}</th><th>{t("Count")}</th><th>{t("Atomic mass")}</th><th>{t("Mass")}</th><th>{t("Share")}</th></tr></thead><tbody>
        {parsed.map(c => <tr key={c.element.z}><td>{t(c.element.name)}</td><td class="mono">{c.count}</td><td class="mono">{formatNumber(c.element.mass ?? 0)}</td><td class="mono">{formatNumber(countMass(c))}</td><td class="mono">{(total > 0 ? countMass(c) / total * 100 : 0).toFixed(2)} %</td></tr>)}</tbody></table></div></Card>
      : <Warn>{t("Invalid input")}</Warn>}
    <Card title={t("Aliases")}><div class="col">
      {Object.keys(aliases).sort().map(k => <div key={k} class="row" style={{ justifyContent: 'space-between' }}><span>{k}</span><span class="row gap8"><span class="mono">{aliases[k]}</span>
        {!(k in builtInAliases) && user[k] != null && <button class="btn small danger" aria-label={t('Remove {name}', { name: k })} onClick={() => { const u = { ...user }; delete u[k]; setUserAliases(u); bump(n => n + 1) }}>{t("Remove")}</button>}</span></div>)}
      <div class="row gap8"><input type="text" placeholder={t("Symbol")} aria-label={t("Alias symbol")} style={{ width: 100 }} value={alias} onInput={e => setAlias((e.target as HTMLInputElement).value)} />
        <input type="text" placeholder={t("Expansion, e.g. C2H5")} aria-label={t("Alias expansion")} style={{ flex: 1 }} value={exp} onInput={e => setExp((e.target as HTMLInputElement).value)} /><button class="btn" onClick={add}>{t("Add")}</button></div>
      {msg && <div class="small dim">{msg}</div>}</div></Card>
  </div>
}

function Gas() {
  const [solve, setSolve] = useState<GasSolve>('Volume')
  const [pressure, setP] = useState(1), [uP, setUP] = useState(0), [volume, setV] = useState(22.4), [uV, setUV] = useState(0), [temp, setT] = useState(273), [uT, setUT] = useState(0)
  const [moles, setMoles] = useState(1), [mass, setMass] = useState(2.016), [uM, setUM] = useState(0), [molarMass, setMM] = useState(2.016), [byMass, setByMass] = useState(false)
  const [a, setA] = useState(0), [b, setB] = useState(0), [uB, setUB] = useState(0)
  const n = byMass ? toBase(Units.mass[uM], mass) / molarMass : moles
  const g = { P: toBase(Units.pressure[uP], pressure), V: toBase(Units.volume[uV], volume), T: toBase(Units.temperature[uT], temp), n, a, b: toBase(Units.volume[uB], b) }
  const raw = solveGas(solve, g)
  const result = raw == null ? null : solve === 'Pressure' ? fromBase(Units.pressure[uP], raw) : solve === 'Volume' ? fromBase(Units.volume[uV], raw) : solve === 'Temperature' ? fromBase(Units.temperature[uT], raw) : raw
  return <div class="col">
    <Segmented value={solve} options={['Volume', 'Pressure', 'Temperature', 'Amount'] as const} onChange={setSolve} label={t("Solve for")} />
    <Card title={t("Gas")}>
      <Quantity title={t("Molar mass (g/mol)")} value={molarMass} onChange={setMM} />
      {solve !== 'Amount' ? <><div style={{ margin: '6px 0' }}><Segmented small value={byMass ? 'Mass' : 'Moles'} options={['Moles', 'Mass'] as const} onChange={v => setByMass(v === 'Mass')} label={t("Amount given as")} /></div>
        {byMass ? <Quantity title={t("Mass")} value={mass} onChange={setMass} units={Units.mass} unit={uM} onUnit={setUM} /> : <Quantity title={t("Moles")} value={moles} onChange={setMoles} />}</>
        : result != null && <><Quantity title={t("Moles")} value={moles} onChange={setMoles} computed={result} /><Quantity title={t("Mass (g)")} value={mass} onChange={setMass} computed={result * molarMass} /></>}
    </Card>
    <Card title={t("State")}>
      <Quantity title={t("Pressure")} value={pressure} onChange={setP} units={Units.pressure} unit={uP} onUnit={setUP} computed={solve === 'Pressure' ? result : undefined} />
      <Quantity title={t("Volume")} value={volume} onChange={setV} units={Units.volume} unit={uV} onUnit={setUV} computed={solve === 'Volume' ? result : undefined} />
      <Quantity title={t("Temperature")} value={temp} onChange={setT} units={Units.temperature} unit={uT} onUnit={setUT} computed={solve === 'Temperature' ? result : undefined} /></Card>
    <Card title={t("Van der Waals constants (0 = ideal gas)")}><Quantity title={t("a (L²·atm/mol²)")} value={a} onChange={setA} /><Quantity title={t("b (per mole)")} value={b} onChange={setB} units={Units.volume} unit={uB} onUnit={setUB} /></Card>
    {result == null && <Warn>{t("Not solvable with these values (check for zero or negative inputs).")}</Warn>}
  </div>
}

function Concentration() {
  const [mode, setMode] = useState<'Find concentration' | 'Find amount of solute'>('Find concentration')
  const [soluteKind, setSK] = useState<SoluteKind>('Mass (g)'), [amount, setAmount] = useState(117)
  const [molarMass, setMM] = useState(58.5), [eqMass, setEq] = useState(58.5), [sd, setSD] = useState(2.17)
  const [solventKind, setVK] = useState<SolventKind>('Volume (L)'), [vAmount, setVA] = useState(1), [vMM, setVMM] = useState(18.015), [vd, setVD] = useState(1)
  const [target, setTarget] = useState(2), [targetKind, setTK] = useState<ConcKind>('Molarity (mol/L)')
  const s: Solution = { molarMass, eqMass, soluteDensity: sd, solventKind, solventAmount: vAmount, solventMolarMass: vMM, solventDensity: vd }
  const req = requiredSolute(targetKind, target, s)
  return <div class="col">
    <Segmented value={mode} options={['Find concentration', 'Find amount of solute'] as const} onChange={setMode} label={t("Mode")} />
    <Card title={t("Solute")}>{mode === 'Find concentration' && <><Field label={t("Amount given as")}><Select value={soluteKind} options={['Mass (g)', 'Volume (L)', 'Moles'] as const} onChange={setSK} /></Field><Quantity title={t("Amount")} value={amount} onChange={setAmount} /></>}
      <Quantity title={t("Molar mass (g/mol)")} value={molarMass} onChange={setMM} /><Quantity title={t("Equivalent mass (g/eq)")} value={eqMass} onChange={setEq} /><Quantity title={t("Density (g/mL)")} value={sd} onChange={setSD} /></Card>
    <Card title={t("Solvent")}><Field label={t("Amount given as")}><Select value={solventKind} options={['Volume (L)', 'Mass (g)', 'Moles'] as const} onChange={setVK} /></Field>
      <Quantity title={t("Amount")} value={vAmount} onChange={setVA} /><Quantity title={t("Molar mass (g/mol)")} value={vMM} onChange={setVMM} /><Quantity title={t("Density (g/mL)")} value={vd} onChange={setVD} /></Card>
    {mode === 'Find concentration' ? <Card title={t("Concentration")}><div class="col gap4">
      {concentrations(soluteMassFrom(amount, soluteKind, s), s).map(([k, v]) => <div key={k} class="row" style={{ justifyContent: 'space-between' }}><span>{t(k)}</span><b class="mono">{formatNumber(v)}</b></div>)}
      <div class="small dim">{t("Molarity and normality are per volume of solvent, as in Kalzium.")}</div></div></Card>
      : <><Card title={t("Target")}><Field label={t("Concentration unit")}><Select value={targetKind} options={concKinds} onChange={setTK} /></Field><Quantity title={t("Concentration")} value={target} onChange={setTarget} /></Card>
        <Card title={t("Required solute")}>{req != null && Number.isFinite(req) && req >= 0 ? <div class="col gap4">
          {([['Mass (g)', req], ['Moles', req / molarMass], ['Volume (L)', req / (sd * 1000)]] as [string, number][]).map(([k, v]) => <div key={k} class="row" style={{ justifyContent: 'space-between' }}><span>{t(k)}</span><b class="mono">{formatNumber(v)}</b></div>)}</div>
          : <Warn>{t("Percentages must be below 100 and values positive.")}</Warn>}</Card></>}
  </div>
}

function Nuclear() {
  const [z, setZ] = useState(92)
  const list = useMemo(() => (isotopesByElement.get(z) ?? []).filter(i => i.halfLife != null), [z])
  const [iso, setIso] = useState<number>(238)
  const [solve, setSolve] = useState<DecaySolve>('Time')
  const [hl, setHl] = useState(4.468), [uHl, setUHl] = useState(0), [init, setInit] = useState(6), [uInit, setUInit] = useState(0), [fin, setFin] = useState(3), [uFin, setUFin] = useState(0)
  const [time, setTime] = useState(4.468e9), [uTime, setUTime] = useState(0), [moles, setMoles] = useState(false)
  const isotope: Isotope | undefined = list.find(i => i.a === iso) ?? list[0]
  const atomicMass = isotope?.mass ?? isotope?.a ?? 1
  const useHalfLife = (i: Isotope) => { if (i.halfLife == null) return; const idx = bestTimeUnit(i.halfLife); setUHl(idx); setHl(Number(fromBase(Units.time[idx], i.halfLife).toPrecision(8))) }
  const hlS = toBase(Units.time[uHl], hl), elapsed = toBase(Units.time[uTime], time)
  const grams = (v: number, u: number) => moles ? v * atomicMass : toBase(Units.mass[u], v)
  const show = (g: number, u: number) => moles ? g / atomicMass : fromBase(Units.mass[u], g)
  const raw = solveDecay(solve, hlS, grams(init, uInit), grams(fin, uFin), elapsed)
  const result = raw == null ? null : solve === 'Time' ? fromBase(Units.time[uTime], raw) : solve === 'Final amount' ? show(raw, uFin) : show(raw, uInit)
  const massUnits = moles ? [] : Units.mass
  return <div class="col">
    <Card title={t("Isotope")}><div class="col">
      <Field label={t("Element")}><select value={z} onChange={e => { const nz = Number((e.target as HTMLSelectElement).value); setZ(nz); const f = (isotopesByElement.get(nz) ?? []).find(i => i.halfLife != null); if (f) { setIso(f.a); useHalfLife(f) } }}>{elements.map(e => <option key={e.z} value={e.z}>{e.z}  {t(e.name)}</option>)}</select></Field>
      <Field label={t("Isotope")}><select value={isotope?.a} onChange={e => { const a = Number((e.target as HTMLSelectElement).value); setIso(a); const f = list.find(i => i.a === a); if (f) useHalfLife(f) }}>{list.map(i => <option key={i.a} value={i.a}>{i.a}{elementByZ.get(z)!.symbol}  ({halfLifeText(i)})</option>)}</select></Field>
      <Quantity title={t("Half-life")} value={hl} onChange={setHl} units={Units.time} unit={uHl} onUnit={setUHl} /></div></Card>
    <Segmented value={solve} options={['Final amount', 'Initial amount', 'Time'] as const} onChange={setSolve} label={t("Solve for")} />
    <Segmented small value={moles ? 'Moles' : 'Mass'} options={['Mass', 'Moles'] as const} onChange={v => setMoles(v === 'Moles')} label={t("Amounts in")} />
    <Card title={t("Amounts")}>
      <Quantity title={t("Initial amount")} value={init} onChange={setInit} units={massUnits} unit={uInit} onUnit={setUInit} computed={solve === 'Initial amount' ? result : undefined} />
      <Quantity title={t("Final amount")} value={fin} onChange={setFin} units={massUnits} unit={uFin} onUnit={setUFin} computed={solve === 'Final amount' ? result : undefined} />
      <Quantity title={t("Elapsed time")} value={time} onChange={setTime} units={Units.time} unit={uTime} onUnit={setUTime} computed={solve === 'Time' ? result : undefined} />
      {solve !== 'Time' && <><div class="row" style={{ justifyContent: 'space-between' }}><span>{t("In half-lives")}</span><input type="range" aria-label={t("In half-lives")} min={0} max={10} step={0.01} style={{ width: 220 }} value={elapsed / Math.max(hlS, 1e-300)} onInput={e => setTime(fromBase(Units.time[uTime], Number((e.target as HTMLInputElement).value) * hlS))} /></div>
        <div class="row" style={{ justifyContent: 'space-between' }}><span>{t("Fraction remaining")}</span><span class="mono">{Number((100 / Math.pow(2, elapsed / Math.max(hlS, 1e-300))).toFixed(3))} %</span></div></>}</Card>
    {result == null && <Warn>{t("Enter positive amounts (final ≤ initial) and a non-zero half-life.")}</Warn>}
  </div>
}

interface Row { name: string; text: string }
function Titration() {
  const blank = (n: number): Row[] => Array.from({ length: n }, () => ({ name: '', text: '' }))
  const [eqs, setEqs] = useState<Row[]>(blank(6)), [pts, setPts] = useState<{ y: string; x: string }[]>(Array.from({ length: 8 }, () => ({ y: '', x: '' })))
  const [xVar, setXVar] = useState(''), [yVar, setYVar] = useState(''), [xMin, setXMin] = useState(0), [xMax, setXMax] = useState(60), [yMin, setYMin] = useState(0), [yMax, setYMax] = useState(14)
  const num = (s: string) => { const v = Number(s.replace(',', '.')); return s.trim() !== '' && Number.isFinite(v) ? v : null }
  const exp = pts.flatMap(p => { const x = num(p.x), y = num(p.y); return x != null && y != null ? [{ x, y }] : [] })
  const theory = theoryCurve(eqs, xVar, yVar, xMin, xMax), fit = fitTitration(exp)
  const series = [
    ...(theory ? [{ name: t('Theory'), color: '#e5484d', kind: 'line' as const, points: theory.samples }] : []),
    ...(exp.length ? [{ name: t('Experiment'), color: '#3b82f6', kind: 'points' as const, points: exp }] : []),
    ...(fit ? [{ name: t('Fit'), color: '#30a46c', kind: 'line' as const, points: Array.from({ length: 241 }, (_, i) => { const x = xMin + (xMax - xMin) * i / 240; return { x, y: fit.a * Math.tanh(fit.b * (x + fit.c)) + fit.d } }) }] : []),
  ]
  const example = () => {
    setEqs([['A', '(C*D)/(B*K)'], ['K', '10^-3'], ['C', 'OH'], ['OH', '(10^-14)/H'], ['H', '10^-4'], ['B', '6*(10^-2)']].map(([name, text]) => ({ name, text })))
    setXVar('D'); setYVar('A'); setXMin(0); setXMax(60); setYMin(0); setYMax(14)
    setPts([['7,19', '30'], ['7,64', '30,5'], ['10,02', '31'], ['10,45', '31,5']].map(([y, x]) => ({ y, x })).concat(Array.from({ length: 4 }, () => ({ y: '', x: '' }))))
  }
  const edit = <T,>(arr: T[], set: (a: T[]) => void, i: number, patch: Partial<T>) => set(arr.map((r, j) => j === i ? { ...r, ...patch } : r))
  return <div class="split" style={{ gridTemplateColumns: 'minmax(320px, 400px) 1fr', gap: 20 }}>
    <div class="col">
      <Card title={t("Equations (name = expression)")}><div class="col gap4">{eqs.map((e, i) => <div key={i} class="row gap8"><input type="text" placeholder={t("Var")} aria-label={t('Equation {n} name', { n: i + 1 })} style={{ width: 64 }} value={e.name} onInput={ev => edit(eqs, setEqs, i, { name: (ev.target as HTMLInputElement).value })} />=
        <input type="text" placeholder={t("e.g. (C*D)/(B*K)")} aria-label={t('Equation {n} expression', { n: i + 1 })} style={{ flex: 1 }} value={e.text} onInput={ev => edit(eqs, setEqs, i, { text: (ev.target as HTMLInputElement).value })} /></div>)}
        <div><button class="btn small" onClick={() => setEqs([...eqs, ...blank(1)])}>{t("Add row")}</button></div>
        <div class="small dim">{t("Operators + − * / ^ and ( ). Functions: sqrt, ln, log, exp, abs, sin, cos, tan, tanh.")}</div></div></Card>
      <Card title={t("Axes")}><div class="col gap8"><Field label={t("X variable")}><input type="text" value={xVar} onInput={e => setXVar((e.target as HTMLInputElement).value)} /></Field><Field label={t("Y variable")}><input type="text" value={yVar} onInput={e => setYVar((e.target as HTMLInputElement).value)} /></Field>
        <div class="row gap8">{t("X range")} <NumInput width={70} label={t("X min")} value={xMin} onChange={setXMin} /> {t("to")} <NumInput width={70} label={t("X max")} value={xMax} onChange={setXMax} /></div>
        <div class="row gap8">{t("Y range")} <NumInput width={70} label={t("Y min")} value={yMin} onChange={setYMin} /> {t("to")} <NumInput width={70} label={t("Y max")} value={yMax} onChange={setYMax} /></div></div></Card>
      <Card title={t("Experimental points (y, x)")}><div class="col gap4">{pts.map((p, i) => <div key={i} class="row gap8"><input type="text" placeholder={t("y")} aria-label={t('Point {n} y', { n: i + 1 })} value={p.y} onInput={e => edit(pts, setPts, i, { y: (e.target as HTMLInputElement).value })} /><input type="text" placeholder={t("x")} aria-label={t('Point {n} x', { n: i + 1 })} value={p.x} onInput={e => edit(pts, setPts, i, { x: (e.target as HTMLInputElement).value })} /></div>)}
        <div><button class="btn small" onClick={() => setPts([...pts, { y: '', x: '' }])}>{t("Add row")}</button></div></div></Card>
      <div class="row gap8"><button class="btn" onClick={example}>{t("Load example")}</button><button class="btn danger" onClick={() => { setEqs(blank(6)); setPts(Array.from({ length: 8 }, () => ({ y: '', x: '' }))); setXVar(''); setYVar('') }}>{t("Clear")}</button></div>
    </div>
    <div class="col"><SeriesChart series={series} xRange={[xMin, xMax]} yRange={[yMin, yMax]} />
      {theory && <div>{t('Theoretical curve: {formula}', { formula: theory.formula })}</div>}
      {fit ? <><div>{t('Approximated curve: {a}·tanh({b}·(x + {c})) + {d}', { a: formatNumber(fit.a), b: formatNumber(fit.b), c: formatNumber(fit.c), d: formatNumber(fit.d) })}</div><h3>{t('Equivalence point: x = {x}', { x: formatNumber(fit.equivalence) })}</h3></>
        : exp.length > 0 && <div class="dim">{t("Enter at least three experimental points, in increasing x order, to fit a curve.")}</div>}</div>
  </div>
}
