#!/bin/zsh
# Release build → /Applications/Thuban Planner.app (replaces any existing copy, relaunches if it was running).
set -uo pipefail
cd "$(dirname "$0")/.."
CONFIG=Release DERIVED=.build/DerivedData-Release scripts/build.sh || exit 1
SRC=".build/DerivedData-Release/Build/Products/Release/Thuban Planner.app"
DEST="/Applications/Thuban Planner.app"
WAS_RUNNING=0
if pgrep -f "/Applications/Thuban Planner.app/Contents/MacOS/Thuban Planner" >/dev/null; then
  WAS_RUNNING=1
  pkill -f "/Applications/Thuban Planner.app/Contents/MacOS/Thuban Planner"
  sleep 1
fi
rm -rf "$DEST"
cp -R "$SRC" "$DEST" || exit 1
echo "Installed $DEST"
if [[ "$WAS_RUNNING" == "1" ]]; then open "$DEST"; fi
