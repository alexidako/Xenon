#!/bin/bash
# Visual regression tests.
#   scripts/vrt.sh            capture every screen and compare with vrt/baseline
#   scripts/vrt.sh --update   capture and accept the result as the new baseline
#   scripts/vrt.sh --only gas capture/compare only scenarios whose name contains "gas"
set -euo pipefail
cd "$(dirname "$0")/.."

UPDATE=0; ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    --update) UPDATE=1 ;;
    --only) ONLY=(--only "$2"); shift ;;
  esac
  shift
done

swift build 2>&1 | tail -1
BIN="$(swift build --show-bin-path)/Xenon"

pkill -f "debug/Xenon" 2>/dev/null || true   # a leftover copy would steal the window
pkill -f "Xenon.app/Contents/MacOS" 2>/dev/null || true
rm -rf vrt/current; mkdir -p vrt/current vrt/baseline
"$BIN" --vrt vrt/current ${ONLY[@]+"${ONLY[@]}"}

if [ "$UPDATE" = 1 ]; then
  cp vrt/current/*.png vrt/baseline/
  echo "Baseline updated: $(ls vrt/baseline | wc -l | tr -d ' ') screens in vrt/baseline"
else
  "$BIN" --vrt-compare vrt/baseline vrt/current vrt/diff
fi
