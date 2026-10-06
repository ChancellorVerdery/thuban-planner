#!/bin/zsh
# Visual smoke test: builds (unless SKIP_BUILD=1), launches the Debug binary on a fresh temporary THUBAN_PLANNER_HOME
# with THUBAN_PLANNER_SMOKE=<output dir>. The app seeds SampleData, walks every section, the registered SmokeScenes,
# Planner and Route in dark mode and every Settings pane, writes PNGs and exits. Only the process it launched is
# ever stopped. Never ssh, never your real data.
# Usage: [DERIVED=.build/DerivedData-<name>] [SKIP_BUILD=1] scripts/smoke.sh [output-dir]   (default .build/smoke)
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${1:-$ROOT/.build/smoke}"
[[ "$OUT" = /* ]] || OUT="$ROOT/$OUT"
DERIVED="${DERIVED:-.build/DerivedData}"
APP="$ROOT/$DERIVED/Build/Products/Debug/Thuban Planner.app/Contents/MacOS/Thuban Planner"
LOG="$(mktemp "${TMPDIR:-/tmp}/thuban-planner-smoke-log.XXXXXX")"

if [[ "${SKIP_BUILD:-0}" != "1" || ! -x "$APP" ]]; then
  DERIVED="$DERIVED" scripts/build.sh || exit 1
fi

HOME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/thuban-planner-smoke-home.XXXXXX")"
rm -rf "$OUT"; mkdir -p "$OUT"
echo "Smoke home: $HOME_DIR"
echo "Output:     $OUT"
THUBAN_PLANNER_SMOKE="$OUT" THUBAN_PLANNER_HOME="$HOME_DIR" "$APP" > "$LOG" 2>&1 &
PID=$!
TIMEOUT="${SMOKE_TIMEOUT:-360}"
for (( i = 1; i <= TIMEOUT; i++ )); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
  echo "TIMEOUT: app still running after $TIMEOUT s; stopping it (pid $PID)"; kill "$PID" 2>/dev/null; STATUS=2
else
  wait "$PID"; STATUS=$?; echo "App exited with status $STATUS"
fi
echo "--- app output (last 40 lines of $LOG):"; tail -40 "$LOG"
echo "--- screenshots:"; ls "$OUT"/*.png 2>/dev/null || echo "(none)"
rm -rf "$HOME_DIR"
exit $STATUS
