import { Store } from '../lib/store'

/** Translation: `t("English text")` looks the English text up in the current language's dictionary and falls back to the
 *  English itself. `{name}` placeholders are filled from the second argument. The English text is the key, so the source
 *  stays readable and a missing translation never shows a raw key. */
export const languages = [
  { code: 'en', name: 'English', html: 'en' },
  { code: 'ru', name: 'Русский', html: 'ru' },
  { code: 'uk', name: 'Українська', html: 'uk' },
  { code: 'zh', name: '简体中文', html: 'zh-Hans' },
  { code: 'es', name: 'Español', html: 'es' },
  { code: 'fr', name: 'Français', html: 'fr' },
] as const
export type Lang = typeof languages[number]['code']
export const langCodes = languages.map(l => l.code) as Lang[]
const storageKey = 'xenon.lang'

/** The saved choice, else the best match for the browser/OS language, else English. */
export function detectLanguage(saved: string | null = readSaved(), preferred: readonly string[] = typeof navigator !== 'undefined' ? navigator.languages ?? [navigator.language] : []): Lang {
  if (saved && (langCodes as string[]).includes(saved)) return saved as Lang
  for (const p of preferred) { const base = p.toLowerCase().split('-')[0]; if ((langCodes as string[]).includes(base)) return base as Lang }
  return 'en'
}
function readSaved(): string | null { try { return localStorage.getItem(storageKey) } catch { return null } }

export const language = new Store<Lang>('en')
let dict: Record<string, string> = {}
const loaders = import.meta.glob('./locales/*.json', { import: 'default' }) as Record<string, () => Promise<Record<string, string>>>

/** Switches the language (loading its dictionary the first time) and remembers the choice. */
export async function setLanguage(code: Lang, remember = true): Promise<void> {
  const load = loaders[`./locales/${code}.json`]
  dict = code === 'en' || !load ? {} : await load()
  if (typeof document !== 'undefined') document.documentElement.lang = languages.find(l => l.code === code)?.html ?? 'en'
  if (remember) { try { localStorage.setItem(storageKey, code) } catch { /* ignore */ } }
  language.set(code)
}

/** English strings that were looked up in a non-English language without finding a translation (inspect `__xenonMissing` in dev tools). */
export const missing = new Set<string>()
if (typeof window !== 'undefined') (window as unknown as { __xenonMissing: Set<string> }).__xenonMissing = missing

export function t(key: string, params?: Record<string, string | number>): string {
  const found = Object.hasOwn(dict, key) && dict[key] !== ''
  if (!found && /[A-Za-z]{3}/.test(key) && Object.keys(dict).length) missing.add(key)
  const s = found ? dict[key] : key
  return params ? s.replace(/\{(\w+)\}/g, (m, k) => (k in params ? String(params[k]) : m)) : s
}
/** Like t(), for short or ambiguous strings: looks up "context|text" first, then the plain text (units, one-letter labels). */
export function tc(context: string, key: string): string {
  const k = `${context}|${key}`
  return Object.hasOwn(dict, k) && dict[k] !== '' ? dict[k] : t(key)
}
/** True when the current language has its own text for this English string. */
export const hasTranslation = (key: string) => Object.hasOwn(dict, key) && dict[key] !== ''
