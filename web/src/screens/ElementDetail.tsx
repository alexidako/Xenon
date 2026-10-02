import { useState } from 'preact/hooks'
import { Element, familyInfo, iupacGroup, isotopesByElement, spectra, decayLabel, halfLifeText, Isotope, nanometers, wavelengthColor } from '../lib/element'
import { shellCounts, subshellsOf } from '../lib/config'
import { prettyConfig } from '../lib/quiz'
import { energyText, lengthText, temperatureText, prefs } from '../lib/prefs'
import { useStore } from '../lib/store'
import { reference } from '../lib/reference'
import { sig, formatNumber } from '../lib/format'
import { Card, KV, Markup, Segmented, NumInput } from '../ui/kit'
import { Canvas, cssVar } from '../ui/canvas'
import { t } from '../i18n'

const tabs = ['Overview', 'Atom', 'Isotopes', 'Spectrum', 'Misc', 'Links'] as const
type Tab = typeof tabs[number]
const fmt = (v: number | null, unit = '') => v == null ? '—' : Number(v.toFixed(4)).toLocaleString('en-US', { maximumFractionDigits: 4 }) + (unit ? ' ' + unit : '')
const countries: Record<string, string> = { de: 'Germany', dk: 'Denmark', es: 'Spain', fi: 'Finland', fr: 'France', it: 'Italy', ru: 'Russia', se: 'Sweden', uk: 'United Kingdom', us: 'United States', ch: 'Switzerland', at: 'Austria', pl: 'Poland', nl: 'Netherlands', jp: 'Japan', ca: 'Canada', be: 'Belgium', no: 'Norway', ie: 'Ireland', hu: 'Hungary', ua: 'Ukraine', cz: 'Czech Republic', pt: 'Portugal', mx: 'Mexico', au: 'Australia', ar: 'Argentina', co: 'Colombia', sk: 'Slovakia', cn: 'China', in: 'India', ancient: 'Known since antiquity' }

export function ElementDetail({ element: e }: { element: Element }) {
  const [tab, setTab] = useState<Tab>('Overview'); useStore(prefs)
  const fam = familyInfo(e)
  return <div class="pad col" style={{ gap: 16 }}>
    <div class="elhead">
      <div class="bigtile" style={{ background: fam?.color ?? 'rgba(128,128,128,.4)' }}><span class="small">{e.z}</span><b>{e.symbol}</b><span class="small">{fmt(e.mass)}</span></div>
      <div class="col gap4"><h1>{t(e.name)}</h1><div class="dim">{fam ? t(fam.label) : ''}</div></div>
    </div>
    <Segmented small value={tab} options={tabs} onChange={setTab} label={t("Detail section")} />
    {tab === 'Overview' && <Overview e={e} />}
    {tab === 'Atom' && <AtomModel e={e} />}
    {tab === 'Isotopes' && <IsotopeList e={e} />}
    {tab === 'Spectrum' && <SpectrumPanel e={e} />}
    {tab === 'Misc' && <Misc e={e} />}
    {tab === 'Links' && <Links e={e} />}
  </div>
}

function Overview({ e }: { e: Element }) {
  const g = iupacGroup(e.z)
  return <div class="col">
    {e.nameOrigin && <em class="dim">{t(e.nameOrigin)}</em>}
    <Card title={t("Classification")}><KV rows={[
      ['Group / period', `${g ?? '—'} / ${e.period ?? '—'}`], ['Block', e.block ?? '—'],
      ['Electron configuration', e.configuration ? prettyConfig(e.configuration) : '—'],
      ['Oxidation states', e.oxidation.length ? e.oxidation.map(o => o > 0 ? `+${o}` : String(o)).join(', ') : '—']]} /></Card>
    <Card title={t("Mass & size")}><KV rows={[['Atomic mass', fmt(e.mass, 'u')], ['Exact mass', fmt(e.exactMass, 'u')], ['Covalent radius', lengthText(e.radiusCovalent)], ['Van der Waals radius', lengthText(e.radiusVDW)]]} /></Card>
    <Card title={t("Energies")}><KV rows={[['Electronegativity (Pauling)', fmt(e.electronegativity)], ['First ionization energy', energyText(e.ionization)], ['Electron affinity', energyText(e.electronAffinity)]]} /></Card>
    <Card title={t("Phase changes")}><KV rows={[['Melting point', temperatureText(e.meltingPoint)], ['Boiling point', temperatureText(e.boilingPoint)]]} /></Card>
  </div>
}

function AtomModel({ e }: { e: Element }) {
  const shells = shellCounts(e.configuration ?? ''), subs = subshellsOf(e.configuration ?? '')
  return <div class="col">
    <Canvas class="canvasbox" style={{ height: 280 }} label={t('Bohr-style model of {name}: {shells} electrons per shell', { name: t(e.name), shells: shells.join(', ') })} deps={[e.z]} draw={(ctx, w, h) => {
      const cx = w / 2, cy = h / 2, maxR = Math.min(w, h) / 2 - 6, nR = maxR * 0.12, step = (maxR - nR - 4) / Math.max(shells.length, 1)
      ctx.fillStyle = 'rgba(0,0,0,.25)'; ctx.fillRect(0, 0, w, h)
      shells.forEach((count, i) => {
        const r = nR + 4 + step * (i + 1)
        ctx.strokeStyle = 'rgba(160,160,170,.6)'; ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(cx, cy, r, 0, 7); ctx.stroke()
        for (let k = 0; k < count; k++) {
          const a = 2 * Math.PI * (k / Math.max(count, 1)) - Math.PI / 2 + i * 0.3, x = cx + r * Math.cos(a), y = cy + r * Math.sin(a)
          ctx.fillStyle = '#ffd60a'; ctx.strokeStyle = '#ff9f0a'; ctx.beginPath(); ctx.arc(x, y, 4.5, 0, 7); ctx.fill(); ctx.stroke()
        }
      })
      ctx.fillStyle = '#ff3b30'; ctx.beginPath(); ctx.arc(cx, cy, nR, 0, 7); ctx.fill()
    }} />
    <div class="small dim">{t("Each ring is an electron shell; each yellow dot an electron.")}</div>
    <table class="t"><thead><tr><th>{t("Shell")}</th><th>{t("Electrons")}</th><th>{t("Subshells")}</th></tr></thead><tbody>
      {shells.map((c, i) => <tr key={i}><td>{i + 1} ({'KLMNOPQ'[Math.min(i, 6)]})</td><td class="mono">{c}</td><td class="mono">{subs.filter(s => s.n === i + 1).map(s => `${s.n}${s.l}${s.electrons}`).join('  ')}</td></tr>)}
    </tbody></table>
    <KV rows={[['Protons / electrons', String(e.z)], ['Configuration', e.configuration ? prettyConfig(e.configuration) : '—']]} />
  </div>
}

function IsotopeList({ e }: { e: Element }) {
  const list = isotopesByElement.get(e.z) ?? []
  const summary = (i: Isotope) => i.decays.slice(0, 2).map(d => d.percent != null ? `${decayLabel(d.mode)} ${sig(d.percent, 3)}%` : decayLabel(d.mode)).join(', ')
  return <div class="col">
    <div class="dim">{t('{n} known isotopes', { n: list.length })}</div>
    {!list.length ? <div class="dim">{t("No isotope data.")}</div> : <div style={{ overflowX: 'auto' }}><table class="t"><thead><tr><th>{t("Isotope")}</th><th>{t("Abundance")}</th><th>{t("Half-life")}</th><th>{t("Spin")}</th><th>{t("Decay")}</th></tr></thead><tbody>
      {list.map(i => <tr key={i.a}>
        <td class={i.abundance != null ? 'bold' : ''}><sup>{i.a}</sup>{e.symbol}</td>
        <td class="nowrap">{i.abundance != null ? <span class="row gap8"><span class="bar" style={{ width: 40 }}><i style={{ width: `${Math.max(2, i.abundance)}%` }} /></span><span class="mono">{sig(i.abundance, 4)}%</span></span> : <span class="dim">—</span>}</td>
        <td class="mono nowrap">{halfLifeText(i)}</td><td>{i.spin ?? '—'}</td><td class="nowrap">{summary(i)}</td></tr>)}
    </tbody></table></div>}
  </div>
}

const wunits = ['nm', 'Å', 'µm', 'eV'] as const
type WUnit = typeof wunits[number]
const fromNM = (u: WUnit, nm: number) => u === 'nm' ? nm : u === 'Å' ? nm * 10 : u === 'µm' ? nm / 1000 : 1239.841984 / nm
const toNM = (u: WUnit, v: number) => u === 'nm' ? v : u === 'Å' ? v / 10 : u === 'µm' ? v * 1000 : 1239.841984 / v
const region = (nm: number) => nm < 380 ? 'UV' : nm > 780 ? 'IR' : t('visible')

export function SpectrumPanel({ e }: { e: Element }) {
  const lines = [...(spectra.get(e.z) ?? [])].sort((a, b) => a.wavelength - b.wavelength)
  const [type, setType] = useState<'Emission' | 'Absorption'>('Emission'), [unit, setUnit] = useState<WUnit>('nm'), [lo, setLo] = useState(380), [hi, setHi] = useState(780)
  if (!lines.length) return <div class="dim">{t('No spectrum is available for {name}.', { name: t(e.name) })}</div>
  const a = Math.min(lo, hi), b = Math.max(lo, hi), shown = lines.filter(l => nanometers(l) >= a && nanometers(l) <= b)
  const lab = (nm: number) => formatNumber(fromNM(unit, nm)) + ' ' + unit
  return <div class="col">
    <div class="row wrap">
      <Segmented small value={type} options={['Emission', 'Absorption'] as const} onChange={setType} />
      <select aria-label={t("Unit")} value={unit} onChange={ev => setUnit((ev.target as HTMLSelectElement).value as WUnit)}>{wunits.map(u => <option key={u}>{u}</option>)}</select>
    </div>
    <div class="row wrap gap8">{t("Range")} <NumInput width={80} label={t("From")} value={Number(fromNM(unit, lo).toPrecision(6))} onChange={v => v > 0 && setLo(toNM(unit, v))} /> {t("to")}
      <NumInput width={80} label={t("To")} value={Number(fromNM(unit, hi).toPrecision(6))} onChange={v => v > 0 && setHi(toNM(unit, v))} /> {unit}<span class="grow" />
      <button class="btn small" onClick={() => { setLo(380); setHi(780) }}>{t("Visible")}</button>
      <button class="btn small" onClick={() => { setLo(Math.max(1, nanometers(lines[0]) - 5)); setHi(nanometers(lines[lines.length - 1]) + 5) }}>{t("All")}</button></div>
    <SpectrumStrip lines={lines.map(l => ({ nm: nanometers(l), intensity: l.intensity }))} lo={a} hi={b} absorption={type === 'Absorption'} />
    <div class="row small dim"><span>{lab(a)}</span><span class="grow" /><span>{lab(b)}</span></div>
    <div class="small dim">{t('{n} of {total} lines in range', { n: shown.length, total: lines.length })}</div>
    <table class="t"><thead><tr><th /><th>{t("Wavelength")}</th><th>{t("Intensity")}</th><th>{t("Region")}</th></tr></thead><tbody>
      {lines.map((l, i) => { const nm = nanometers(l); return <tr key={i} style={{ opacity: nm >= a && nm <= b ? 1 : 0.4 }}>
        <td><span class="swatch" style={{ background: wavelengthColor(nm), borderRadius: 7 }} /></td><td class="mono">{lab(nm)}</td><td class="mono">{l.intensity}</td><td class="dim">{region(nm)}</td></tr> })}
    </tbody></table>
  </div>
}

export function SpectrumStrip({ lines, lo, hi, absorption, height = 70 }: { lines: { nm: number; intensity: number }[]; lo: number; hi: number; absorption: boolean; height?: number }) {
  return <Canvas class="canvasbox" style={{ height }} label={t("Spectrum")} deps={[lines, lo, hi, absorption]} draw={(ctx, w, h) => {
    if (hi <= lo) return
    if (absorption) { const steps = 120; for (let i = 0; i < steps; i++) { ctx.fillStyle = wavelengthColor(lo + (hi - lo) * (i + 0.5) / steps, true); ctx.fillRect(w * i / steps, 0, w / steps + 1, h) } }
    else { ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h) }
    const maxI = Math.max(1, ...lines.map(l => l.intensity))
    for (const l of lines) {
      if (l.nm < lo || l.nm > hi) continue
      const x = (l.nm - lo) / (hi - lo) * w, alpha = 0.35 + 0.65 * l.intensity / maxI
      ctx.globalAlpha = alpha; ctx.fillStyle = absorption ? '#000' : wavelengthColor(l.nm, true); ctx.fillRect(x - 1, 0, 2, h); ctx.globalAlpha = 1
    }
  }} />
}

function Misc({ e }: { e: Element }) {
  const year = e.discoveryDate == null ? null : Number(e.discoveryDate)
  const use = reference.uses[String(e.z)]
  return <div class="col">
    <Card title={t("Discovery")}><KV rows={[
      ['Year', year == null || Number.isNaN(year) || year === 0 ? t('known since antiquity') : String(year)],
      ['Discovered by', e.discoverers.length ? e.discoverers.join(', ') : '—'],
      ['Country', e.discoveryCountry.length ? e.discoveryCountry.map(c => countries[c.toLowerCase()] ? t(countries[c.toLowerCase()]) : c.toUpperCase()).join(', ') : '—']]} /></Card>
    <Card title={t("Name")}><span style={{ userSelect: 'text' }}>{e.nameOrigin ? t(e.nameOrigin) : '—'}</span></Card>
    {use && <Card title={t("Use")}><Markup text={t(use)} /></Card>}
  </div>
}

function Links({ e }: { e: Element }) {
  const jlab = `https://education.jlab.org/itselemental/ele${String(e.z).padStart(3, '0')}.html`
  return <div class="col"><div class="dim">{t('Look up {name} online', { name: t(e.name) })}</div>
    <a href={`https://en.wikipedia.org/wiki/${e.name}`} target="_blank" rel="noreferrer">{t("Wikipedia")}</a>
    <a href={jlab} target="_blank" rel="noreferrer">{t("Jefferson Lab – It's Elemental")}</a>
    <a href={`https://www.webelements.com/${e.name.toLowerCase()}/`} target="_blank" rel="noreferrer">{t("WebElements")}</a></div>
}
export { cssVar }
