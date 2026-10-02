import { useState } from 'preact/hooks'
import { elementBySymbol, elements } from '../lib/element'
import { solve, solveStructured } from '../lib/solver'
import { speciesFrom, solveStoich, qunits, QUnit } from '../lib/stoich'
import { formatNumber } from '../lib/format'
import { formulaText } from '../lib/markup'
import { Card, Page, Segmented, NumInput } from '../ui/kit'
import { t, tc } from '../i18n'

const examples = ['aCH3CH2OH + bO2 -> cH2O + dCO2', 'aAl + bHCl -> cAlCl3 + dH2', 'aH + bO -> 5H2O', 'aFe[2+] + bMnO4[-] + cH3O[+] -> dMn[2+] + eH2O + fFe[3+]', 'aCH3(CH2)3COOH + bO2 -> cH2O + dCO2']
const isEl = (s: string) => elementBySymbol.has(s)
const masses = new Map(elements.map(e => [e.symbol, e.mass ?? 0]))

export function SolverScreen() {
  const [mode, setMode] = useState<'Balance' | 'Stoichiometry'>('Balance')
  const [eq, setEq] = useState('aCH3CH2OH + bO2 -> cH2O + dCO2')
  const [answer, setAnswer] = useState<string | null>(null), [error, setError] = useState<string | null>(null)
  const run = (text = eq) => {
    const r = solve(text, isEl)
    if (r.ok) { setAnswer(r.value); setError(null) }
    else { setAnswer(null); setError(r.error.kind === 'notFound' ? t('Not found: no whole-number solution exists for this equation.') : t('Parse error: {why}.', { why: r.error.message })) }
  }
  return <Page title={t("Equation Solver")} toolbar={<Segmented value={mode} options={['Balance', 'Stoichiometry'] as const} onChange={setMode} label={t("Mode")} />}>
    <div class="scroll pad col" style={{ maxWidth: 760 }}>
      <input type="text" class="mono" style={{ fontSize: 18 }} aria-label={t("Equation")} placeholder={t("e.g. aH2 + bO2 -> cH2O")} value={eq} onInput={e => setEq((e.target as HTMLInputElement).value)} onKeyDown={e => { if (e.key === 'Enter' && mode === 'Balance') run() }} />
      {mode === 'Balance' ? <>
        <div class="row gap8"><button class="btn primary" onClick={() => run()}>{t("Solve")}</button>
          <select aria-label={t("Examples")} value="" onChange={e => { const v = (e.target as HTMLSelectElement).value; if (v) { setEq(v); run(v) } }}><option value="">{t("Examples")}</option>{examples.map(x => <option key={x} value={x}>{x}</option>)}</select></div>
        <Card title={t("Result")}>{answer ? <div class="row" style={{ justifyContent: 'space-between' }}><span class="mono" style={{ fontSize: 18, userSelect: 'text' }}>{formulaText(answer)}</span><button class="btn small" onClick={() => navigator.clipboard?.writeText(formulaText(answer))}>{t("Copy")}</button></div>
          : error ? <div class="warn" role="alert">⚠ {error}</div> : <div class="dim">{t("Enter an equation and press Solve.")}</div>}</Card>
        <Card title={t("How to write equations")}><div class="col gap8 dim">
          <div>{t("Put a single lowercase letter in front of a molecule to leave its coefficient open, or a number to fix it. The solver finds the smallest whole numbers that balance every element and the electric charge.")}</div>
          <div class="mono">{t("aH + bO -> 5H2O gives 10 H + 5 O -> 5 H2O")}</div>
          <div>{t("Use square brackets for charges, for example Fe[2+] or OH[-]. Parentheses are allowed: CH3(CH2)3COOH.")}</div><div>{t("The same letter used twice stands for the same quantity.")}</div>
          <div>{t("Equations that need fractional coefficients, or cannot be balanced, report “Not found”.")}</div></div></Card>
      </> : <Stoich equation={eq} />}
    </div></Page>
}

function Stoich({ equation }: { equation: string }) {
  const [amounts, setAmounts] = useState<Record<number, string>>({}), [units, setUnits] = useState<Record<number, QUnit>>({})
  const [prod, setProd] = useState(0), [actual, setActual] = useState('')
  const b = solveStructured(equation, isEl)
  if (!b.ok) return <div class="warn" role="alert">⚠ {b.error.kind === 'notFound' ? t("This equation can't be balanced with whole numbers.") : t('Fix the equation on the Balance tab first.')}</div>
  const species = speciesFrom(b.value, s => masses.get(s)), reactants = species.filter(s => s.isReactant), products = species.filter(s => !s.isReactant)
  const num = (s?: string) => { const v = Number((s ?? '').replace(',', '.')); return (s ?? '').trim() !== '' && Number.isFinite(v) ? v : null }
  const given = new Map<number, [number, QUnit]>(); for (const r of reactants) { const v = num(amounts[r.id]); if (v != null) given.set(r.id, [v, units[r.id] ?? 'g']) }
  const o = solveStoich(species, given), label = (s: { coefficient: number; formula: string }) => (s.coefficient === 1 ? '' : `${s.coefficient} `) + s.formula
  const act = num(actual)
  return <div class="col">
    <Card title={t("Balanced equation")}><span class="mono" style={{ fontSize: 18, userSelect: 'text' }}>{formulaText(reactants.map(label).join(' + ') + '  →  ' + products.map(label).join(' + '))}</span></Card>
    <Card title={t("Amounts you have (leave blank for “plenty”)")}>{reactants.map(r => <div key={r.id} class="row" style={{ justifyContent: 'space-between', padding: '4px 0' }}>
      <div><div class="mono">{formulaText(r.formula)}</div><div class="small dim">{t('{value} g/mol', { value: formatNumber(r.molarMass) })}</div></div>
      <span class="row gap8"><input type="text" inputMode="decimal" placeholder={t("amount")} aria-label={t('Amount of {formula}', { formula: r.formula })} style={{ width: 110, textAlign: 'right' }} value={amounts[r.id] ?? ''} onInput={e => setAmounts({ ...amounts, [r.id]: (e.target as HTMLInputElement).value })} />
        <select aria-label={t('Unit for {formula}', { formula: r.formula })} value={units[r.id] ?? 'g'} onChange={e => setUnits({ ...units, [r.id]: (e.target as HTMLSelectElement).value as QUnit })}>{qunits.map(u => <option key={u} value={u}>{tc('unit', u)}</option>)}</select></span></div>)}</Card>
    {o ? <>
      <Card title={t("Result")}><div class="col gap8">
        <div class="row" style={{ justifyContent: 'space-between' }}><span>{t("Limiting reagent")}</span><b class="mono warn" style={{ fontSize: 17 }}>{formulaText(o.limiting?.formula ?? '—')}</b></div>
        {o.excess.map(l => <div key={l.species.id} class="row" style={{ justifyContent: 'space-between' }}><span>{t('Left over: {formula}', { formula: formulaText(l.species.formula) })}</span><span class="mono">{t('{g} g ({mol} mol)', { g: formatNumber(l.grams), mol: formatNumber(l.moles) })}</span></div>)}
        {o.products.map(l => <div key={l.species.id} class="row" style={{ justifyContent: 'space-between' }}><span>{t('Theoretical yield: {formula}', { formula: formulaText(l.species.formula) })}</span><b class="mono">{t('{g} g ({mol} mol)', { g: formatNumber(l.grams), mol: formatNumber(l.moles) })}</b></div>)}</div></Card>
      <Card title={t("Percent yield")}><div class="col gap8">
        <select aria-label={t("Product")} value={prod} onChange={e => setProd(Number((e.target as HTMLSelectElement).value))}>{products.map((p, i) => <option key={i} value={i}>{formulaText(p.formula)}</option>)}</select>
        <div class="row" style={{ justifyContent: 'space-between' }}><span>{t("Actual yield (g)")}</span><input type="text" inputMode="decimal" placeholder={t("grams collected")} aria-label={t("Actual yield")} style={{ width: 140, textAlign: 'right' }} value={actual} onInput={e => setActual((e.target as HTMLInputElement).value)} /></div>
        {act != null && prod < o.products.length && o.products[prod].grams > 0 && <><div class="row" style={{ justifyContent: 'space-between' }}><span>{t("Percent yield")}</span><b class="mono" style={{ fontSize: 17 }}>{formatNumber(act / o.products[prod].grams * 100)} %</b></div>
          <div class="small dim">{t('{actual} g ÷ {theory} g × 100', { actual: formatNumber(act), theory: formatNumber(o.products[prod].grams) })}</div></>}</div></Card>
      <details open><summary class="bold" style={{ cursor: 'pointer' }}>{t("Show the steps")}</summary><ol class="mono small" style={{ userSelect: 'text' }}>{o.steps.map((s, i) => <li key={i}>{formulaText(s)}</li>)}</ol></details>
    </> : <div class="dim">{t("Enter the amount of at least one reactant to see the limiting reagent and yields.")}</div>}
  </div>
}
