import { render } from 'preact'
import './styles.css'
import { App } from './App'
import { prefs, applyTheme } from './lib/prefs'
import { installExternalLinks } from './lib/export'
import { detectLanguage, setLanguage } from './i18n'

applyTheme(prefs.get().theme)
installExternalLinks()
// load the dictionary before the first paint so the interface never flashes in English
setLanguage(detectLanguage(), false).finally(() => render(<App />, document.getElementById('app')!))
