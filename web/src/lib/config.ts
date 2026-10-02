export interface Subshell { n: number; l: string; electrons: number }
const cores: Record<string, string> = {
  He: '1s2', Ne: '[He] 2s2 2p6', Ar: '[Ne] 3s2 3p6', Kr: '[Ar] 4s2 3d10 4p6', Xe: '[Kr] 5s2 4d10 5p6', Rn: '[Xe] 6s2 4f14 5d10 6p6',
}
export function subshellsOf(text: string): Subshell[] {
  const out: Subshell[] = []
  for (const token of text.split(' ').filter(Boolean)) {
    if (token.startsWith('[')) {
      const name = token.slice(1, -1)
      if (Object.hasOwn(cores, name)) out.push(...subshellsOf(cores[name]))
    } else {
      const l = [...token.slice(1)].find(c => 'spdf'.includes(c))
      const n = parseInt(token[0]), e = parseInt(token.slice(2))
      if (l && Number.isFinite(n) && Number.isFinite(e)) out.push({ n, l, electrons: e })
    }
  }
  return out
}
/** Electrons per principal shell n = 1, 2, 3 … */
export function shellCounts(text: string): number[] {
  const counts = new Map<number, number>()
  for (const s of subshellsOf(text)) counts.set(s.n, (counts.get(s.n) ?? 0) + s.electrons)
  const max = Math.max(1, ...counts.keys())
  return Array.from({ length: max }, (_, i) => counts.get(i + 1) ?? 0)
}
const supers = '⁰¹²³⁴⁵⁶⁷⁸⁹'
export const superscript = (n: number) => [...String(n)].map(c => supers[Number(c)]).join('')
