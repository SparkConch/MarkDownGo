#!/bin/bash
# Produce dist/MarkDownGo-<version>-arm64.dmg from the Release build (ad-hoc signed, unnotarized).
# The volume holds the app plus an Applications folder shortcut, the usual macOS drag-to-install shape.
set -euo pipefail
VERSION="${1:-0.1.0}"
APP="build/Build/Products/Release/MarkDownGo.app"
OUT="dist/MarkDownGo-${VERSION}-arm64.dmg"
[ -d "$APP" ] || { echo "missing $APP — run make build first"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/MarkDownGo.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$OUT"
hdiutil create -volname MarkDownGo -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
echo "$OUT"
