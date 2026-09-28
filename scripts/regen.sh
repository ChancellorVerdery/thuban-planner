#!/bin/zsh
# Regenerates ThubanPlanner.xcodeproj from project.yml (build.sh does this too). Run it before opening Xcode.
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
xcodegen generate --quiet
