# Notices

**Xenon** is Copyright © 2026 pupper and is released under the **GNU General Public License, version 2 or (at your
option) any later version** (see `LICENSE`). It is a port of, and derives from, **KDE Kalzium**, which is also
GPL-2.0-or-later: <https://invent.kde.org/education/kalzium>. The GPL requires that anyone who receives Xenon can also get
its complete source code; this repository is that source.

## Third-party material

| Material | Where | Licence / credit |
| --- | --- | --- |
| Kalzium application logic, algorithms and text (equation solver, glossary, lab equipment, R/S phrases, tables) | ported to Swift and TypeScript | GPL-2.0-or-later, © the KDE Kalzium authors |
| Element, isotope and spectrum data | `elements.json`, `isotopes.json`, `spectra.json` (converted from Kalzium's `libscience/data`) | Blue Obelisk Data Repository, MIT licence |
| Molecule files (`*.cml`) | `Sources/Xenon/Resources/molecules`, `web/src/data/molecules` | © 2006 Jerome Pansanel, BSD-3-Clause (`LICENSES/BSD-3-Clause.txt`) |
| Element icons, hazard symbols, lab-equipment pictures | `Sources/Xenon/Resources`, `web/public/data` | Taken from Kalzium; individual artists are credited in Kalzium's `data/iconsets/school/COPYRIGHT`. Licences vary by file upstream, so check them before redistributing these assets on their own. |

## Tools used to build the web version

three.js (MIT), Preact (MIT), Vite (MIT), Tauri (Apache-2.0 / MIT). See each package for its licence text.

The "Xenon" name and the N₂ logo are new and are not part of KDE Kalzium. The word "Kalzium" and the KDE logo are not used
as the name of this application.
