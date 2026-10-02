import { describe, expect, it } from 'vitest'
import { exportCsv, exportHtml, exportXml, exportProps } from './export'
import { elements } from './element'

describe('export', () => {
  const fe = elements.filter(e => e.symbol === 'Fe'), ps = exportProps.slice(0, 3)
  it('csv quotes and escapes', () => { const c = exportCsv(fe, ps); expect(c.split('\n')[0]).toBe('"Name","Atomic Number","Symbol","Mass"'); expect(c).toContain('"Iron","26","Fe","55.845 u"') })
  it('xml and html are well-formed', () => { expect(exportXml(fe, ps)).toContain('<property name="Symbol">Fe</property>'); expect(exportHtml(fe, ps)).toContain('<th colspan="2">Iron</th>') })
  it('escapes markup', () => { const x = exportXml([{ ...fe[0], name: 'A<&"B' }], ps); expect(x).toContain('A&lt;&amp;&quot;B') })
})
