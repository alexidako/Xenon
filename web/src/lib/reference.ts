import json from '../data/reference.json'

export interface GlossaryEntry { name: string; desc: string; refs: string[] }
export interface LabTool { picture: string; name: string; desc: string }
export interface Reference {
  uses: Record<string, string>; rphrases: Record<string, string>; sphrases: Record<string, string>
  greek: { upper: string; lower: string; name: string }[]
  numbers: { number: string; prefix: string; roman: string }[]
  glossary: GlossaryEntry[]; tools: LabTool[]
}
export const reference = json as unknown as Reference
export const dataUrl = (path: string) => `data/${path}`
export const elementIconUrl = (z: number) => dataUrl(`icons/${z}.svg`)
