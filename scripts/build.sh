#!/bin/zsh
# Debug build of the app (ad-hoc signed). Prints only errors/warnings from our sources and the result.
# DERIVED=<dir> overrides the DerivedData path (ALWAYS use a private one when others may be building);
# CONFIG=Release builds Release. The Xcode project is regenerated from project.yml every time (it is not committed).
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED:-.build/DerivedData}"
LOG="${DERIVED}/xcodebuild.log"
mkdir -p "$DERIVED"
xcodegen generate --quiet || exit 1
xcodebuild -project ThubanPlanner.xcodeproj -scheme ThubanPlanner -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build "$@" > "$LOG" 2>&1
STATUS=$?
grep -E "(error|warning): " "$LOG" | grep -E "ThubanPlanner/|ThubanPlannerCore/|Shared/|xcodebuild: error" | grep -v "DerivedData" | sort -u | head -60
grep -E "\*\* BUILD (SUCCEEDED|FAILED) \*\*" "$LOG" || echo "** BUILD RESULT UNKNOWN (see $LOG) **"
echo "App: $DERIVED/Build/Products/$CONFIG/Thuban Planner.app"
exit $STATUS
