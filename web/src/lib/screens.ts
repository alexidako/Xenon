export type ScreenId = 'table' | 'glossary' | 'rs' | 'tables' | 'equipment' | 'editor' | 'molecules' | 'orbitals' | 'filling' | 'quiz' | 'vbt'
  | 'isotopes' | 'plot' | 'calculators' | 'solver' | 'matcher' | 'export' | 'settings'

export interface Screen { id: ScreenId; title: string; icon: string; aliases: string[] }
const S = (id: ScreenId, title: string, icon: string, aliases: string[] = []): Screen => ({ id, title, icon, aliases })

export const screens: Record<ScreenId, Screen> = {
  table: S('table', 'Periodic Table', 'grid', ['periodic table', 'elements', 'table']),
  isotopes: S('isotopes', 'Isotope Chart', 'nuclide', ['isotope chart', 'nuclides', 'decay']),
  plot: S('plot', 'Plot Data', 'chart', ['plot data', 'graph', 'trends']),
  matcher: S('matcher', 'Spectrum Matcher', 'wave', ['spectrum matcher', 'spectra', 'emission lines']),
  quiz: S('quiz', 'Quiz', 'quiz', ['quiz', 'test', 'flashcards', 'practice']),
  filling: S('filling', 'Electron Filling', 'boxes', ['electron filling', 'aufbau', 'hund', 'pauli', 'configuration']),
  glossary: S('glossary', 'Glossary', 'book', ['glossary', 'terms', 'definitions']),
  editor: S('editor', 'Molecule Editor', 'pen', ['molecule editor', 'draw', 'sketch']),
  molecules: S('molecules', 'Molecules', 'atom', ['molecules', '3d', 'viewer']),
  orbitals: S('orbitals', 'Orbitals', 'orbital', ['orbitals', 'orbital', 's p d', 'hybrid']),
  vbt: S('vbt', 'Valence Bond Theory', 'link', ['valence bond theory', 'vbt', 'hybridization', 'resonance', 'formal charge']),
  calculators: S('calculators', 'Calculators', 'fx', ['calculators', 'gas law', 'molar mass', 'concentration', 'titration', 'nuclear decay', 'half-life']),
  solver: S('solver', 'Equation Solver', 'equals', ['equation solver', 'balance equation', 'stoichiometry', 'limiting reagent']),
  export: S('export', 'Export Data', 'share', ['export data', 'csv', 'html', 'xml']),
  rs: S('rs', 'Risk & Safety', 'warn', ['risk', 'safety', 'r/s phrases', 'hazard']),
  tables: S('tables', 'Reference Tables', 'tablecells', ['greek', 'roman numerals', 'prefixes', 'reference tables']),
  equipment: S('equipment', 'Lab Equipment', 'flask', ['lab equipment', 'tools', 'glassware']),
  settings: S('settings', 'Settings', 'gear', ['settings', 'units', 'preferences', 'celsius', 'kelvin', 'theme', 'dark mode']),
}

export const screenGroups: { title: string; items: ScreenId[] }[] = [
  { title: 'Explore', items: ['table', 'isotopes', 'plot', 'matcher'] },
  { title: 'Learn', items: ['quiz', 'filling', 'glossary'] },
  { title: 'Molecules & Bonding', items: ['editor', 'molecules', 'orbitals', 'vbt'] },
  { title: 'Tools', items: ['calculators', 'solver', 'export'] },
  { title: 'Reference', items: ['rs', 'tables', 'equipment'] },
]
export const shortcutOrder: ScreenId[] = screenGroups.flatMap(g => g.items).slice(0, 10)
