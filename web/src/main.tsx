import { render } from 'preact'
import './styles.css'
import { App } from './App'
import { prefs, applyTheme } from './lib/prefs'
import { installExternalLinks } from './lib/export'

applyTheme(prefs.get().theme)
installExternalLinks()
render(<App />, document.getElementById('app')!)
