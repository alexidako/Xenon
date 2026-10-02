import { useEffect, useRef, useState } from 'preact/hooks'
import { searchPalette } from '../lib/palette'
import { goTo, jump } from '../lib/nav'
import { Icon } from './icons'
import { t } from '../i18n'

export function Palette() {
  const [q, setQ] = useState(''), [idx, setIdx] = useState(0)
  const input = useRef<HTMLInputElement>(null)
  const results = searchPalette(q)
  useEffect(() => { input.current?.focus() }, [])
  const close = () => jump.set(j => ({ ...j, paletteOpen: false }))
  const choose = (i: number) => { const r = results[i]; if (r) goTo(r) }
  return <div class="overlay" onMouseDown={e => { if (e.target === e.currentTarget) close() }}>
    <div class="palette" role="dialog" aria-label={t("Quick lookup")} onKeyDown={e => {
      if (e.key === 'ArrowDown') { e.preventDefault(); setIdx(i => Math.min(i + 1, Math.max(0, results.length - 1))) }
      else if (e.key === 'ArrowUp') { e.preventDefault(); setIdx(i => Math.max(i - 1, 0)) }
      else if (e.key === 'Enter') choose(idx)
      else if (e.key === 'Escape') close()
    }}>
      <input ref={input} type="text" placeholder={t("Jump to a screen, element, term or molecule")} value={q} aria-label={t("Quick lookup")} onInput={e => { setQ((e.target as HTMLInputElement).value); setIdx(0) }} />
      <div class="results">
        {results.map((r, i) => <div key={r.id} class={'item' + (i === idx ? ' on' : '')} onMouseEnter={() => setIdx(i)} onClick={() => choose(i)}>
          <Icon name={r.icon} /><span>{r.title}</span><span class="grow" /><span class="small dim">{r.subtitle}</span>
        </div>)}
        {!results.length && <div class="pad dim">{t('Nothing found for “{q}”', { q })}</div>}
      </div>
    </div>
  </div>
}
