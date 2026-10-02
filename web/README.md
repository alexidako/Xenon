# Xenon for Windows, Linux and the web

The cross-platform version of Xenon: the same screens and logic as the Mac app, written in TypeScript with Preact and
three.js, and packaged as a desktop app with [Tauri](https://tauri.app). It also runs as a plain web page.

## Run it

```bash
cd web
npm install
npm run dev          # opens http://localhost:5173
npm test             # 100+ logic checks (parsers, solver, quiz, VBT, resonance, optimizer, ...)
npm run build        # static site in web/dist (host it anywhere)
```

## Build the desktop installers

Installers have to be built on their own operating system, so the easiest route is the included GitHub Actions workflow
(`.github/workflows/desktop.yml`): push the repo to GitHub, open **Actions → Build Xenon desktop apps → Run workflow**,
and download the Windows (`.msi`, `.exe`), Linux (`.deb`, `.rpm`, `.AppImage`) and macOS (`.dmg`) files from the run.
Push a tag like `v1.0.1` to get them attached to a draft release instead (for the maintainer: review it on the Releases page, then press *Publish release* so everyone else can download it).

To build on your own machine you need Node 20+ and a Rust toolchain ([rustup.rs](https://rustup.rs)):

```bash
cd web
npm install
npm run tauri build          # installer for the OS you are on, in src-tauri/target/release/bundle
```

Linux also needs `libwebkit2gtk-4.1-dev libappindicator3-dev librsvg2-dev patchelf`.

### First launch (the apps are not code-signed)

* **Windows:** SmartScreen may say "Windows protected your PC". Choose *More info → Run anyway*.
* **macOS:** right-click the app and choose *Open* the first time.
* **Linux:** make the AppImage executable (`chmod +x Xenon*.AppImage`) or install the `.deb`/`.rpm`.

Removing these warnings needs a paid Windows code-signing certificate and an Apple Developer ID.

## What is where

| Folder | Contents |
| --- | --- |
| `src/lib` | all logic (no UI): formulas, solver, quiz, VBT, resonance, orbitals, force-field optimizer, ... with `*.test.ts` |
| `src/screens`, `src/ui` | the 18 screens and shared components |
| `src/data` | element, isotope, spectrum and reference data, molecules (converted from Kalzium) |
| `src-tauri` | the Tauri desktop wrapper and icons |

Licence: GPL-2.0-or-later, see `../LICENSE` and `../NOTICE.md`.
