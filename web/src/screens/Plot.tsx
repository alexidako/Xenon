import { useMemo, useState } from 'preact/hooks'
import { Element, elements } from '../lib/element'
import { Check, NumInput, Page, Segmented, Select } from '../ui/kit'
import { ScatterChart } from '../ui/chart'
import { t } from '../i18n'

const props: [string, (e: Element) => number | null][] = [
  ['Atomic number', e => e.z], ['Atomic mass', e => e.mass], ['Electronegativity', e => e.electronegativity], ['Melting point (K)', e => e.meltingPoint],
  ['Boiling point (K)', e => e.boilingPoint], ['Van der Waals radius (Å)', e => e.radiusVDW], ['Covalent radius (Å)', e => e.radiusCovalent],
  ['Ionization energy (eV)', e => e.ionization], ['Electron affinity (eV)', e => e.electronAffinity],
]
const names = props.map(p => p[0])
const styles = ['Points', 'Line', 'Line & points'] as const

export function PlotScreen() {
  const [x, setX] = useState(names[0]), [y, setY] = useState('Ionization energy (eV)')
  const [from, setFrom] = useState(1), [to, setTo] = useState(118)
  const [style, setStyle] = useState<typeof styles[number]>('Line & points'), [labels, setLabels] = useState(true)
  const points = useMemo(() => {
    const fx = props.find(p => p[0] === x)![1], fy = props.find(p => p[0] === y)![1]
    return elements.filter(e => e.z >= from && e.z <= to).flatMap(e => { const a = fx(e), b = fy(e); return a != null && b != null ? [{ x: a, y: b, label: e.symbol }] : [] }).sort((p, q) => p.x - q.x)
  }, [x, y, from, to])
  return <Page title={t("Plot Data")} toolbar={<>
    <label class="row gap8">{t("Y axis")} <Select value={y} options={names} onChange={setY} label={t("Y axis")} /></label>
    <label class="row gap8">{t("X axis")} <Select value={x} options={names} onChange={setX} label={t("X axis")} /></label>
    <span class="row gap8">{t("Elements")} <NumInput width={60} label={t("First element")} value={from} onChange={setFrom} /> {t("to")} <NumInput width={60} label={t("Last element")} value={to} onChange={setTo} /></span>
    <Segmented small value={style} options={styles} onChange={setStyle} label={t("Style")} /><Check checked={labels} onChange={setLabels}>{t("Labels")}</Check>
    <span class="grow" /><span class="small dim">{t('{n} elements plotted', { n: points.length })}</span></>}>
    <div class="pad" style={{ flex: 1, minHeight: 0 }}>{points.length ? <ScatterChart points={points} xLabel={t(x)} yLabel={t(y)} line={style !== 'Points'} dots={style !== 'Line'} labels={labels && style !== 'Line'} height={Math.max(300, window.innerHeight - 150)} /> : <div class="dim center">{t("Nothing to plot for this range.")}</div>}</div>
  </Page>
}
