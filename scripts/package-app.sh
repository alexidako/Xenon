#!/bin/bash
# Builds a release binary and wraps it in Xenon.app (ad-hoc signed, for local use).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Xenon.app"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Xenon" "$APP/Contents/MacOS/Xenon"
# SwiftPM resources (element data, icons, molecules, ...) live in this bundle; Bundle.module finds it in Resources.
cp -R "$BIN_DIR/Xenon_Xenon.bundle" "$APP/Contents/Resources/"
# Translations: SwiftUI finds <lang>.lproj in the app bundle. Regenerate with scripts/make-localizations.py.
python3 scripts/make-localizations.py >/dev/null
cp -R packaging/localization/*.lproj "$APP/Contents/Resources/"

# App icon: 3D N≡N render (regenerate with: swiftc tools/make_logo.swift -o /tmp/make_logo && /tmp/make_logo packaging/AppIcon.png)
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512 1024; do
  sips -z $s $s packaging/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
done
cp "$ICONSET/icon_32x32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
rm "$ICONSET/icon_1024x1024.png"
rm "$ICONSET/icon_64x64.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string><string>uk</string><string>zh-Hans</string><string>es</string><string>fr</string></array>
  <key>CFBundleName</key><string>Xenon</string>
  <key>CFBundleDisplayName</key><string>Xenon</string>
  <key>CFBundleIdentifier</key><string>local.xenon</string>
  <key>CFBundleExecutable</key><string>Xenon</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.2</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>NSHumanReadableCopyright</key><string>Built by pupper, 2026. Data and artwork from KDE Kalzium (GPL-2.0-or-later) and the Blue Obelisk project (MIT).</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"
