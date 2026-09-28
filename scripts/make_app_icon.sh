#!/bin/zsh
# Regenerates ThubanPlanner/Resources/Assets.xcassets/AppIcon.appiconset from the app mark (Shared/Art/AppArtSource.swift, Brass on a dark plate).
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
cp scripts/make_app_icon.swift "$TMP/main.swift"
swiftc -D APPICON_TOOL -o "$TMP/make_app_icon" "$TMP/main.swift" \
  Shared/Art/AppArt.swift Shared/Art/AppArtSource.swift
find ThubanPlanner/Resources/Assets.xcassets/AppIcon.appiconset -name "*.png" -delete
"$TMP/make_app_icon" ThubanPlanner/Resources/Assets.xcassets/AppIcon.appiconset
rm -rf "$TMP"
