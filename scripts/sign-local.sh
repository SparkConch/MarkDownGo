#!/bin/bash
# Optional: re-sign the built app with the local Apple Development certificate (free Apple ID team).
# WARNING: an Apple Development certificate carries your email address in its common name, and
# codesign embeds the certificate into the app — anyone can read it with `codesign -dvvv`.
# NEVER run this for a build you publish. Release builds are ad-hoc signed and leak nothing.
# Local apps without quarantine run either way; this only matters for personal convenience.
set -euo pipefail
APP="build/Build/Products/Release/MarkDownGo.app"
IDENT=$(security find-identity -v -p codesigning | grep "Apple Development" | sed -E 's/.*"(.*)"/\1/' | head -1 || true)
if [ -z "${IDENT:-}" ]; then
  echo "No Apple Development identity found; keeping ad-hoc signature."
  exit 1
fi
codesign --force --deep --sign "$IDENT" "$APP"
echo "Signed with: $IDENT"
