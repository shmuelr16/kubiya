#!/bin/bash
# Builds build/Kubiya-<version>-mac.dmg: Kubiya.app plus a shortcut to Applications.
# Needs Godot 4.7 and its macOS export template (macos.zip) installed.
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
OUT="build/mac"
STAGE="build/dmg"
DMG="build/Kubiya-${VERSION}-mac.dmg"

rm -rf "$OUT" "$STAGE" "$DMG"
mkdir -p "$OUT" "$STAGE"

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "macOS" "$OUT/Kubiya.app"
test -x "$OUT/Kubiya.app/Contents/MacOS/Kubiya"

cp -R "$OUT/Kubiya.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Kubiya" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
