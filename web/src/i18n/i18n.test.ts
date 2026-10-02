import { describe, expect, it } from 'vitest'
import { t, detectLanguage, setLanguage, language } from './index'

describe('i18n core', () => {
  it('returns the English text when nothing is translated', () => { expect(t('Periodic Table')).toBe('Periodic Table'); expect(t('No such string')).toBe('No such string') })
  it('fills placeholders and leaves unknown ones alone', () => { expect(t('Question {n} of {total}', { n: 2, total: 10 })).toBe('Question 2 of 10'); expect(t('Hello {who}', { n: 1 })).toBe('Hello {who}') })
  it('detects the language', () => {
    expect(detectLanguage('ru', ['en-US'])).toBe('ru'); expect(detectLanguage(null, ['uk-UA', 'en'])).toBe('uk'); expect(detectLanguage(null, ['zh-CN'])).toBe('zh')
    expect(detectLanguage(null, ['es-MX'])).toBe('es'); expect(detectLanguage(null, ['fr-CA'])).toBe('fr'); expect(detectLanguage(null, ['de-DE', 'ja'])).toBe('en'); expect(detectLanguage('xx', [])).toBe('en')
  })
  it('switching to English keeps keys as they are', async () => { await setLanguage('en', false); expect(language.get()).toBe('en'); expect(t('Settings')).toBe('Settings') })
})
