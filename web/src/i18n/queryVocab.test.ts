import { afterEach, describe, expect, test } from 'vitest'
import { setLanguage, Lang } from './index'
import { runQuery } from '../lib/query'

const cases: [Lang, string, string][] = [
  ['ru', 'галогены, открытые до 1850', 'halogens discovered before 1850'],
  ['ru', 'жидкие при комнатной температуре', 'liquid at room temperature'],
  ['ru', 'температура плавления выше 3000 K', 'melting point above 3000 K'],
  ['ru', 'самый тяжёлый благородный газ', 'heaviest noble gas'],
  ['ru', 'металлы 3 периода', 'metals period 3'],
  ['uk', 'галогени, відкриті до 1850', 'halogens discovered before 1850'],
  ['uk', 'рідкі за кімнатної температури', 'liquid at room temperature'],
  ['uk', 'електронегативність більше 3', 'electronegativity above 3'],
  ['zh', '1850年之前发现的卤素', 'halogens discovered before 1850'],
  ['zh', '室温下的液体', 'liquid at room temperature'],
  ['zh', '熔点高于3000K', 'melting point above 3000 K'],
  ['zh', '最重的稀有气体', 'heaviest noble gas'],
  ['es', 'halógenos descubiertos antes de 1850', 'halogens discovered before 1850'],
  ['es', 'líquidos a temperatura ambiente', 'liquid at room temperature'],
  ['es', 'punto de fusión mayor que 3000 K', 'melting point above 3000 K'],
  ['es', 'el gas noble más pesado', 'heaviest noble gas'],
  ['fr', 'halogènes découverts avant 1850', 'halogens discovered before 1850'],
  ['fr', 'liquides à température ambiante', 'liquid at room temperature'],
  ['fr', 'point de fusion supérieur à 3000 K', 'melting point above 3000 K'],
  ['fr', 'le gaz noble le plus lourd', 'heaviest noble gas'],
  ['ru', 'радиоактивные металлы', 'radioactive metals'],
  ['ru', 'открыты в Германии', 'discovered in germany'],
  ['uk', '3 період, метали', 'metals period 3'],
  ['zh', '第3周期的金属', 'metals period 3'],
  ['zh', '放射性金属', 'radioactive metals'],
  ['es', 'gases a 300 K', 'gas at 300 K'],
  ['fr', 'métaux du groupe 3', 'metals group 3'],
  ['fr', 'rayon covalent entre 1 et 1,5 Å', 'covalent radius between 1 and 1.5 Å'],
]

afterEach(() => setLanguage('en', false))

describe('questions in other languages', () => {
  for (const [lang, q, en] of cases) {
    test(`${lang}: ${q}`, async () => {
      await setLanguage('en', false)
      const expected = runQuery(en)
      expect(expected && expected.matches.length).toBeGreaterThan(0)
      await setLanguage(lang, false)
      const got = runQuery(q)
      expect(got?.matches.map(e => e.z)).toEqual(expected!.matches.map(e => e.z))
    })
  }
})
