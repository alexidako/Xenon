// Writes the question-box vocabulary (used by the web app) as JSON for the Mac app: Sources/Xenon/Resources/queryvocab.json.
// Run from web/:  node tools/export-query-vocab.mjs   (needs a Node that runs TypeScript files, 22.6+)
import { writeFileSync } from 'node:fs'
const { queryRules } = await import('../src/i18n/queryVocab.ts')
writeFileSync('../Sources/Xenon/Resources/queryvocab.json', JSON.stringify(queryRules))
console.log('languages:', Object.keys(queryRules).join(', '))
