import { useEffect, useMemo, useRef, useState } from 'preact/hooks'
import { elements, elementByZ, gridPosition, familyInfo } from '../lib/element'
import { QuizEngine, QuizKind, quizKinds, QuizQuestion, QuizStats, RNG } from '../lib/quiz'
import { Card, Check, Page, Segmented } from '../ui/kit'

const stats = new QuizStats()
type Phase = 'setup' | 'question' | 'results'
const ranges: [number, string][] = [[20, 'First 20 (H–Ca)'], [36, 'First 36 (H–Kr)'], [54, 'First 54 (H–Xe)'], [118, 'All 118']]

export function QuizScreen() {
  const [phase, setPhase] = useState<Phase>('setup')
  const [kinds, setKinds] = useState<Set<QuizKind>>(new Set(quizKinds)), [range, setRange] = useState(36), [length, setLength] = useState(10), [weak, setWeak] = useState(false)
  const rng = useRef(new RNG()), engine = useRef(new QuizEngine(36, [...quizKinds], stats))
  const [q, setQ] = useState<QuizQuestion | null>(null), [asked, setAsked] = useState(0), [score, setScore] = useState(0), [streak, setStreak] = useState(0), [best, setBest] = useState(0)
  const [answered, setAnswered] = useState<number | null>(null), [clickedZ, setClickedZ] = useState<number | null>(null), [missed, setMissed] = useState<{ q: QuizQuestion; given: string }[]>([]), [, tick] = useState(0)

  const next = (n = asked) => { if (n >= length) { setPhase('results'); return } setAnswered(null); setClickedZ(null); setQ(engine.current.next(rng.current)); setAsked(n + 1) }
  const start = () => {
    engine.current = new QuizEngine(range, quizKinds.filter(k => kinds.has(k)), stats, weak)
    setScore(0); setStreak(0); setBest(0); setMissed([]); setAnswered(null); setClickedZ(null); setPhase('question'); setAsked(0)
    setAnswered(null); setQ(engine.current.next(rng.current)); setAsked(1)
  }
  const answer = (index: number, text: string, right: boolean) => {
    if (!q || answered != null) return
    setAnswered(index); stats.record(q.z, right)
    if (right) { setScore(s => s + 1); setStreak(s => { setBest(b => Math.max(b, s + 1)); return s + 1 }) } else { setStreak(0); setMissed(m => [...m, { q, given: text }]) }
  }
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (phase !== 'question' || !q) return
      if (answered == null && q.kind !== 'Find it on the table' && /^[1-4]$/.test(e.key)) { const i = Number(e.key) - 1; if (i < q.options.length) answer(i, q.options[i], i === q.correct) }
      else if (answered != null && e.key === 'Enter') next()
    }
    addEventListener('keydown', onKey); return () => removeEventListener('keydown', onKey)
  })

  if (phase === 'setup') return <Page title="Quiz"><div class="scroll pad col" style={{ maxWidth: 560, margin: '0 auto', width: '100%' }}>
    <h1>Quiz</h1>
    <Card title="Question types"><div class="col gap4">{quizKinds.map(k => <Check key={k} checked={kinds.has(k)} onChange={on => { const n = new Set(kinds); if (on) n.add(k); else if (n.size > 1) n.delete(k); setKinds(n) }}>{k}</Check>)}</div></Card>
    <Card title="Which elements?"><Segmented value={String(range)} options={ranges.map(r => String(r[0]))} onChange={v => setRange(Number(v))} label="Elements" /><div class="small dim" style={{ marginTop: 6 }}>{ranges.find(r => r[0] === range)![1]}</div></Card>
    <div class="row wrap gap16"><label class="row gap8">Questions <select aria-label="Number of questions" value={length} onChange={e => setLength(Number((e.target as HTMLSelectElement).value))}>{[5, 10, 20].map(n => <option key={n}>{n}</option>)}</select></label>
      <span title="Elements you miss come up more often"><Check checked={weak} onChange={setWeak}>Practise my weak spots</Check></span></div>
    <div><button class="btn primary" style={{ padding: '8px 24px', fontSize: 16 }} onClick={start}>Start quiz</button></div>
    <Card title="Your weak spots">{stats.weakSpots.length === 0 ? <div class="dim">Nothing yet. Elements you get wrong will show up here.</div> : <div class="col gap4">
      {stats.weakSpots.slice(0, 6).map(w => <div key={w.z} class="row"><b style={{ width: 36 }}>{elementByZ.get(w.z)!.symbol}</b><span>{elementByZ.get(w.z)!.name}</span><span class="grow" /><span class="dim small">missed {w.missed} of {w.seen}</span></div>)}
      <div><button class="link danger" onClick={() => { stats.reset(); tick(n => n + 1) }}>Clear history</button></div></div>}</Card>
  </div></Page>

  if (phase === 'results') return <Page title="Quiz results"><div class="scroll pad col" style={{ maxWidth: 620, margin: '0 auto', width: '100%' }}>
    <h1>Results</h1>
    <div class="row" style={{ alignItems: 'baseline', gap: 10 }}><span style={{ fontSize: 64, fontWeight: 700 }} class={score * 10 >= (score + missed.length) * 8 && score + missed.length > 0 ? 'ok' : ''}>{score}</span><span class="dim" style={{ fontSize: 20 }}>out of {score + missed.length}</span></div>
    <div class="dim">Best streak: {best}</div>
    {missed.length ? <Card title="Review what you missed"><div class="col">{missed.map((m, i) => <div key={i} class="col gap4"><b>{m.q.prompt}</b><span class="err">You answered: {m.given}</span><span class="dim">{m.q.explanation}</span></div>)}</div></Card> : <div style={{ color: '#d9a400', fontSize: 17 }}>★ Perfect round</div>}
    <div class="row gap8"><button class="btn primary" onClick={start}>Play again</button><button class="btn" onClick={() => setPhase('setup')}>Change settings</button></div>
  </div></Page>

  return <Page title="Quiz question">
    <div class="toolbar"><span class="bar" style={{ width: 220 }}><i style={{ width: `${(asked - (answered == null ? 1 : 0)) / length * 100}%` }} /></span><span class="dim">Question {asked} of {length}</span><span class="grow" />
      <span class="ok" title="Score">✓ {score}</span><span class="warn" title="Current streak">🔥 {streak}</span><button class="link" onClick={() => setPhase('results')}>Quit</button></div>
    {q && <div class="scroll pad col" style={{ maxWidth: 820, margin: '0 auto', width: '100%', gap: 22 }}>
      <div style={{ fontSize: 26, fontWeight: 600 }}>{q.prompt}</div>
      {q.kind === 'Find it on the table' ? <TableChooser q={q} range={range} answered={answered != null} clickedZ={clickedZ} onPick={z => { setClickedZ(z); answer(z === q.answerZ ? 0 : 1, elementByZ.get(z)!.name, z === q.answerZ) }} />
        : <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>{q.options.map((t, i) => {
          const done = answered != null, isRight = i === q.correct, isPicked = i === answered
          return <button key={i} class="btn" disabled={done} style={{ padding: 14, display: 'flex', gap: 10, alignItems: 'center', textAlign: 'left', fontSize: 18, opacity: 1,
            background: !done ? 'var(--bg2)' : isRight ? 'rgba(48,164,108,.25)' : isPicked ? 'rgba(229,72,77,.25)' : 'var(--bg2)' }} onClick={() => answer(i, t, isRight)}>
            <span class="mono dim small">{i + 1}</span><span style={{ flex: 1 }}>{t}</span>{done && (isRight ? <span class="ok">✔</span> : isPicked ? <span class="err">✖</span> : null)}</button> })}</div>}
      {answered != null && (() => { const right = q.kind === 'Find it on the table' ? clickedZ === q.answerZ : answered === q.correct
        return <div class="card col" style={{ background: right ? 'rgba(48,164,108,.12)' : 'rgba(229,72,77,.12)' }} role="status"><b class={right ? 'ok' : 'err'} style={{ fontSize: 20 }}>{right ? '✔ Correct' : '✖ Not quite'}</b>
          <div class="dim" style={{ fontSize: 17 }}>{q.explanation}</div><div><button class="btn primary" autoFocus onClick={() => next()}>{asked >= length ? 'See results' : 'Next'}</button></div></div> })()}
    </div>}
  </Page>
}

function TableChooser({ q, range, answered, clickedZ, onPick }: { q: QuizQuestion; range: number; answered: boolean; clickedZ: number | null; onPick: (z: number) => void }) {
  const cell = 36, gap = 3, shown = elements.filter(e => e.z <= range), rows = Math.max(...shown.map(e => gridPosition(e.z).row)) + 1, extra = rows > 8 ? 12 : 0
  return <div style={{ position: 'relative', width: 18 * (cell + gap), height: rows * (cell + gap) + extra, marginTop: 24 }} role="grid" aria-label="Periodic table">
    {!answered && <div class="dim" style={{ position: 'absolute', top: -24 }}>Click the element</div>}
    {shown.map(e => { const p = gridPosition(e.z)
      const bg = !answered ? 'var(--bg3)' : e.z === q.answerZ ? 'rgba(48,164,108,.7)' : e.z === clickedZ ? 'rgba(229,72,77,.7)' : 'var(--bg2)'
      return <button key={e.z} role="gridcell" aria-label={answered ? e.name : `Element ${p.row + 1}-${p.col + 1}`} disabled={answered} onClick={() => onPick(e.z)}
        style={{ position: 'absolute', left: p.col * (cell + gap), top: p.row * (cell + gap) + (p.row >= 8 ? 12 : 0), width: cell, height: cell, border: 0, borderRadius: 4, background: bg, fontWeight: 600, fontSize: 12, cursor: answered ? 'default' : 'pointer', color: 'var(--text)' }}>{answered ? e.symbol : ''}</button> })}
  </div>
}
export { useMemo, familyInfo }
