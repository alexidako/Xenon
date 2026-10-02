import { elements, elementBySymbol } from './element'

export interface MolAtom { symbol: string; x: number; y: number; z: number }
export interface MolBond { a: number; b: number; order: number }
export interface Molecule { name: string; atoms: MolAtom[]; bonds: MolBond[] }

export function formulaOf(m: Molecule): string {
  const counts = new Map<string, number>()
  for (const a of m.atoms) counts.set(a.symbol, (counts.get(a.symbol) ?? 0) + 1)
  const part = (s: string) => { const c = counts.get(s); return c == null ? '' : c === 1 ? s : `${s}${c}` }
  let out = ''
  const hasC = counts.has('C')
  if (hasC) out += part('C') + part('H')
  for (const s of [...counts.keys()].sort()) if (!(hasC && (s === 'C' || s === 'H'))) out += part(s)
  return out
}
export const massOf = (m: Molecule) => m.atoms.reduce((s, a) => s + (elementBySymbol.get(a.symbol)?.mass ?? 0), 0)

export type Format = 'cml' | 'mol' | 'xyz'

/** "2_2_2-trifluoroethanol" -> "2,2,2-Trifluoroethanol"; "carbon_dioxide" -> "Carbon dioxide" */
export function nameFromFile(file: string): string {
  const base = file.replace(/^.*\//, '').replace(/\.[^.]+$/, '').replace(/(?<=\d)_(?=\d)/g, ',').replaceAll('_', ' ')
  return base.charAt(0).toUpperCase() + base.slice(1)
}

export function loadMolecule(text: string, file: string): Molecule | null {
  const fallback = nameFromFile(file)
  switch (file.split('.').pop()?.toLowerCase()) {
    case 'cml': return parseCML(text, fallback)
    case 'mol': case 'sdf': return parseMOL(text, fallback)
    case 'xyz': return parseXYZ(text, fallback)
    default: return null
  }
}

const attrs = (tag: string): Record<string, string> => {
  const out: Record<string, string> = {}
  for (const m of tag.matchAll(/([\w:.-]+)\s*=\s*"([^"]*)"/g)) out[m[1]] = m[2]
  return out
}

// CML: <atom id elementType x3 y3 z3/>, <bond atomRefs2 order/>
export function parseCML(text: string, fallback: string): Molecule | null {
  const atoms: MolAtom[] = [], bonds: MolBond[] = []; const ids = new Map<string, number>()
  for (const m of text.matchAll(/<atom\b([^>]*)>/g)) {
    const a = attrs(m[1]); const x = Number(a.x3), y = Number(a.y3), z = Number(a.z3)
    if (a.elementType && a.x3 != null && a.y3 != null && a.z3 != null && Number.isFinite(x + y + z)) {
      ids.set(a.id ?? String(atoms.length), atoms.length); atoms.push({ symbol: a.elementType, x, y, z })
    }
  }
  for (const m of text.matchAll(/<bond\b([^>]*)>/g)) {
    const a = attrs(m[1]); const refs = (a.atomRefs2 ?? '').split(' ').filter(Boolean)
    if (refs.length === 2 && ids.has(refs[0]) && ids.has(refs[1])) {
      const o = a.order ?? '1'
      const order = Number.isFinite(parseInt(o)) ? parseInt(o) : o === 'S' ? 1 : o === 'D' ? 2 : o === 'T' ? 3 : 1
      bonds.push({ a: ids.get(refs[0])!, b: ids.get(refs[1])!, order: Math.max(1, order) })
    }
  }
  if (!atoms.length) return null
  const name = /<name\b[^>]*>([\s\S]*?)<\/name>/.exec(text)?.[1].trim()
  return { name: name || fallback, atoms, bonds }
}

// MDL MOL V2000
export function parseMOL(text: string, fallback: string): Molecule | null {
  const lines = text.split(/\r?\n/)
  if (lines.length <= 4) return null
  const na = parseInt(lines[3].slice(0, 3)), nb = parseInt(lines[3].slice(3, 6))
  if (!(na > 0) || !(nb >= 0) || na > 100_000 || nb > 1_000_000 || lines.length < 4 + na + nb) return null
  const atoms: MolAtom[] = []
  for (const l of lines.slice(4, 4 + na)) {
    const f = l.trim().split(/\s+/)
    if (f.length < 4) return null
    const x = Number(f[0]), y = Number(f[1]), z = Number(f[2])
    if (![x, y, z].every(Number.isFinite)) return null
    atoms.push({ symbol: f[3], x, y, z })
  }
  const bonds: MolBond[] = []
  for (const l of lines.slice(4 + na, 4 + na + nb)) {
    const f = l.trim().split(/\s+/).map(s => parseInt(s)).filter(Number.isFinite)
    if (f.length >= 3) bonds.push({ a: f[0] - 1, b: f[1] - 1, order: Math.max(1, Math.min(3, f[2])) })
  }
  const title = lines[0].trim()
  return { name: title || fallback, atoms, bonds }
}

// XYZ has no bonds; infer them from distances.
export function parseXYZ(text: string, fallback: string): Molecule | null {
  const lines = text.split(/\r?\n/)
  const n = parseInt(lines[0]?.trim() ?? '')
  if (lines.length <= 2 || !(n > 0) || n > 100_000 || lines.length < 2 + n) return null
  const atoms: MolAtom[] = []
  for (const l of lines.slice(2, 2 + n)) {
    const f = l.trim().split(/\s+/)
    if (f.length < 4) return null
    const x = Number(f[1]), y = Number(f[2]), z = Number(f[3])
    if (![x, y, z].every(Number.isFinite)) return null
    atoms.push({ symbol: f[0], x, y, z })
  }
  return { name: lines[1] || fallback, atoms, bonds: inferBonds(atoms) }
}

export function inferBonds(atoms: MolAtom[]): MolBond[] {
  const cov = new Map(elements.map(e => [e.symbol, e.radiusCovalent ?? 0.8]))
  const bonds: MolBond[] = []
  for (let i = 0; i < atoms.length; i++) for (let j = i + 1; j < atoms.length; j++) {
    const d = Math.hypot(atoms[i].x - atoms[j].x, atoms[i].y - atoms[j].y, atoms[i].z - atoms[j].z)
    if (d > 0.4 && d < (cov.get(atoms[i].symbol) ?? 0.8) + (cov.get(atoms[j].symbol) ?? 0.8) + 0.4) bonds.push({ a: i, b: j, order: 1 })
  }
  return bonds
}

const f6 = (v: number) => v.toFixed(6)
const pad = (s: string, n: number) => s.padStart(n)
export function exportMolecule(m: Molecule, format: Format): string {
  switch (format) {
    case 'xyz': return `${m.atoms.length}\n${m.name}\n` + m.atoms.map(a => `${a.symbol} ${f6(a.x)} ${f6(a.y)} ${f6(a.z)}`).join('\n') + '\n'
    case 'mol': {
      let s = `${m.name}\n Xenon\n\n${pad(String(m.atoms.length), 3)}${pad(String(m.bonds.length), 3)}  0  0  0  0  0  0  0  0999 V2000\n`
      for (const a of m.atoms) s += pad(a.x.toFixed(4), 10) + pad(a.y.toFixed(4), 10) + pad(a.z.toFixed(4), 10) + ' ' + a.symbol.padEnd(3) + ' 0  0  0  0  0\n'
      for (const b of m.bonds) s += pad(String(b.a + 1), 3) + pad(String(b.b + 1), 3) + pad(String(b.order), 3) + '  0  0  0\n'
      return s + 'M  END\n'
    }
    case 'cml': {
      const esc = (t: string) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;')
      let s = `<molecule>\n <name>${esc(m.name)}</name>\n <atomArray>\n`
      m.atoms.forEach((a, i) => { s += `  <atom id="a${i + 1}" elementType="${a.symbol}" x3="${f6(a.x)}" y3="${f6(a.y)}" z3="${f6(a.z)}"/>\n` })
      s += ' </atomArray>\n <bondArray>\n'
      for (const b of m.bonds) s += `  <bond atomRefs2="a${b.a + 1} a${b.b + 1}" order="${b.order}"/>\n`
      return s + ' </bondArray>\n</molecule>\n'
    }
  }
}

// Bundled library (Kalzium's molecule set)
const files = import.meta.glob('../data/molecules/*', { query: '?raw', import: 'default', eager: true }) as Record<string, string>
export const moleculeLibrary: Molecule[] = Object.entries(files)
  .map(([path, text]) => loadMolecule(text, path))
  .filter((m): m is Molecule => m != null)
  .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }))
