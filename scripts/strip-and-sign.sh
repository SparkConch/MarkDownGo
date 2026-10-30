#!/bin/bash
# Remove build-time absolute paths (/Users/<you>/...) from the shipped binaries, then re-sign
# ad-hoc. Swift keeps source paths in local symbols; `strip -x` drops them, which invalidates the
# signature, so signing happens right after. Usage: scripts/strip-and-sign.sh [Debug|Release]
set -euo pipefail
CONFIG="${1:-Release}"
APP="build/Build/Products/${CONFIG}/MarkDownGo.app"
[ -d "$APP" ] || { echo "missing $APP — build first"; exit 1; }

BINARIES=("$APP/Contents/MacOS/MarkDownGo")
FRAMEWORK="$APP/Contents/Frameworks/MarkDownGoCore.framework/Versions/A/MarkDownGoCore"
[ -f "$FRAMEWORK" ] && BINARIES+=("$FRAMEWORK")

for binary in "${BINARIES[@]}"; do
  strip -x "$binary" 2>/dev/null || true
done

codesign --force --deep --sign - "$APP" >/dev/null 2>&1

leaks=0
for binary in "${BINARIES[@]}"; do
  n=$(strings -a "$binary" | grep -c '/Users/' || true)
  leaks=$((leaks + n))
done
echo "stripped and re-signed ($([ "$leaks" -eq 0 ] && echo "no build paths left" || echo "$leaks build paths remain"))"
