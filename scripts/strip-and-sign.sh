#!/bin/bash
# Remove build-time absolute paths (/Users/<you>/...) from the shipped binaries, then re-sign.
#
# Signing order matters: `strip` invalidates signatures, and the QuickLook extension must be signed
# with ITS entitlements (app-sandbox — PlugInKit refuses plugins without it) while the host app must
# NOT inherit them. So the nested bundle is signed first, explicitly, then the outer app.
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

APEX="$APP/Contents/PlugIns/MarkDownGoQuickLook.appex"
if [ -d "$APEX" ]; then
  ENT="MarkDownGo/QuickLook/MarkDownGoQuickLook.entitlements"
  # The extension carries its own binary — it needs the same path scrub, then its entitlements.
  APEX_BIN="$APEX/Contents/MacOS/MarkDownGoQuickLook"
  [ -f "$APEX_BIN" ] && { strip -x "$APEX_BIN" 2>/dev/null || true; BINARIES+=("$APEX_BIN"); }
  codesign --force --sign - --entitlements "$ENT" "$APEX" >/dev/null 2>&1
fi

codesign --force --sign - "$APP" >/dev/null 2>&1

leaks=0
for binary in "${BINARIES[@]}"; do
  n=$(strings -a "$binary" | grep -c '/Users/' || true)
  leaks=$((leaks + n))
done
sandboxed="no"
if [ -d "$APEX" ]; then
  codesign -d --entitlements - "$APEX" 2>/dev/null | grep -q "app-sandbox" && sandboxed="yes"
fi
echo "stripped and re-signed ($([ "$leaks" -eq 0 ] && echo "no build paths left" || echo "$leaks build paths remain"); quicklook sandbox=$sandboxed)"
