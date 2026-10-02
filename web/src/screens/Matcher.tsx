import { useState } from 'preact/hooks'
import { rankSpectrum, assignments, parseWavelengths, Candidate } from '../lib/matcher'
import { spectra, nanometers, wavelengthColor } from '../lib/element'
import { formatNumber } from '../lib/format'
import { Canvas } from '../ui/canvas'
import { Page, Segmented, Slider } from '../ui/kit'
import { t } from '../i18n'

const examples: [string, string][] = [['Hydrogen (Balmer lines)', '486.13, 656.28'], ['Helium', '587.56, 667.82, 706.52, 501.57'], ['Sodium lamp (D doublet)', '589.0, 589.6'], ['Mystery gas: hydrogen + helium', '486.13, 656.28, 587.56, 667.82']]

export function MatcherScreen() {
  const [text, setText] = useState('486.13, 656.28, 587.56, 667.82'), [ang, setAng] = useState(false), [tol, setTol] = useState(1), [sel, setSel] = useState<number | null>(null)
  const observed = parseWavelengths(text, ang), ranked = rankSpectrum(observed, tol).slice(0, 10)
  const cur: Candidate | undefined = ranked.find(c => c.element.z === sel) ?? ranked[0]
  return <Page title={t("Spectrum Matcher")}><div class="split" style={{ gridTemplateColumns: 'minmax(400px, 460px) 1fr' }}>
    <div class="scroll pad col">
      <h3>{t("Observed lines")}</h3>
      <textarea class="mono" rows={4} aria-label={t("Observed wavelengths")} value={text} onInput={e => setText((e.target as HTMLTextAreaElement).value)} />
      <div class="row wrap gap8"><Segmented small value={ang ? 'Å' : 'nm'} options={['nm', 'Å'] as const} onChange={v => setAng(v === 'Å')} label={t("Unit")} />
        <select aria-label={t("Examples")} value="" onChange={e => { const v = (e.target as HTMLSelectElement).value; if (v) { setText(v); setAng(false); setSel(null) } }}><option value="">{t("Examples")}</option>{examples.map(([n, text]) => <option key={n} value={text}>{t(n)}</option>)}</select>
        <span class="grow" /><span class="dim">{t('{n} lines observed', { n: observed.length })}</span></div>
      <div class="row gap8">{t("Tolerance")} <Slider label={t("Tolerance")} min={0.1} max={5} step={0.1} value={tol} onChange={setTol} width={160} /><span class="mono">± {tol.toFixed(1)} nm</span></div>
      <hr style={{ width: '100%', border: 0, borderTop: '1px solid var(--line)' }} />
      <h3>{t("Best matches")}</h3>
      {!ranked.length ? <div class="dim">{observed.length ? t('No element in the database has lines near these wavelengths. Try a wider tolerance.') : t('Enter one or more wavelengths separated by commas or spaces.')}</div>
        : <div class="col gap4" role="listbox" aria-label={t("Matches")}>{ranked.map(c => <button key={c.element.z} role="option" aria-selected={c === cur} class="btn" style={{ display: 'flex', alignItems: 'center', gap: 10, textAlign: 'left', background: c === cur ? 'var(--bg3)' : undefined }} onClick={() => setSel(c.element.z)}>
          <b style={{ width: 36, fontSize: 17 }}>{c.element.symbol}</b><span style={{ flex: 1 }}>{t(c.element.name)}<div class="small dim">{t('explains {n} of {total} lines', { n: c.matches.length, total: observed.length })}</div></span>
          <span class="bar" style={{ width: 90 }}><i style={{ width: `${Math.max(4, c.score * 100)}%` }} /></span><span class="mono" style={{ width: 44, textAlign: 'right' }}>{Math.round(c.score * 100)}%</span></button>)}</div>}
    </div>
    <div class="scroll pad col">{cur ? <>
      <h2>{t('{name} vs. your lines', { name: t(cur.element.name) })}</h2>
      <Comparison observed={observed} z={cur.element.z} />
      <div class="row gap16 small"><span>{t("⚪ your lines")}</span><span style={{ color: '#d9a400' }}>● {t('{name} lines', { name: t(cur.element.name) })}</span></div>
      <h3>{t("Line by line")}</h3>
      <table class="t"><thead><tr><th>{t("Observed")}</th><th>{t("Could be")}</th><th>{t("Offset")}</th></tr></thead><tbody>{observed.map((o, i) => { const who = assignments(o, tol); return <tr key={i}>
        <td class="mono">{formatNumber(o)} nm</td><td class={who.length ? '' : 'dim'}>{who.length ? who.slice(0, 4).map(w => w[0].symbol).join(', ') : t('no match')}</td><td class="mono dim">{who[0] ? '±' + formatNumber(who[0][1]) + ' nm' : '—'}</td></tr> })}</tbody></table>
      <div class="small dim">{t("Scores combine how many of your lines the element explains with how many of its strong visible lines you actually saw, so a gas that only shares one line scores low.")}</div>
    </> : <div class="dim center pad">{t("Matches will appear here")}</div>}</div>
  </div></Page>
}

function Comparison({ observed, z }: { observed: number[]; z: number }) {
  const lines = spectra.get(z) ?? []
  return <Canvas class="canvasbox" style={{ height: 110 }} label={t("Observed lines compared with the element's lines")} deps={[observed, z]} draw={(ctx, w, h) => {
    const lo = Math.min(380, ...observed), hi = Math.max(780, ...observed), x = (nm: number) => (nm - lo) / (hi - lo) * w
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h)
    for (let i = 0; i < 100; i++) { ctx.globalAlpha = 0.5; ctx.fillStyle = wavelengthColor(lo + (hi - lo) * (i + 0.5) / 100, true); ctx.fillRect(w * i / 100, h / 2 - 1, w / 100 + 1, 2) }
    ctx.globalAlpha = 1
    const maxI = Math.max(1, ...lines.map(l => l.intensity))
    for (const l of lines) { const nm = nanometers(l); if (nm < lo || nm > hi) continue; ctx.globalAlpha = 0.4 + 0.6 * l.intensity / maxI; ctx.fillStyle = '#ffd60a'; ctx.fillRect(x(nm) - 1, h / 2 + 4, 2, h / 2 - 8) }
    ctx.globalAlpha = 1; ctx.fillStyle = '#fff'; for (const o of observed) if (o >= lo && o <= hi) ctx.fillRect(x(o) - 1.5, 4, 3, h / 2 - 8)
    ctx.fillStyle = '#999'; ctx.font = '9px system-ui'; ctx.textAlign = 'left'; ctx.fillText(`${Math.round(lo)} nm`, 6, h - 4); ctx.textAlign = 'right'; ctx.fillText(`${Math.round(hi)} nm`, w - 6, h - 4)
  }} />
}
