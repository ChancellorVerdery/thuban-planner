#!/bin/zsh
# Unit tests for the core package (includes the 400 Atlas golden scheduler cases; regenerate them with
# scripts/golden.sh). Never touches ssh or the real data folder.
# THUBAN_PLANNER_LIVE_BANNER=1 scripts/test.sh runs ONLY the live, public, read-only Banner check (the term list and
# one class search for MEGR 2144 on selfservice.uncc.edu; never signs in). Keep those runs rare.
set -uo pipefail
cd "$(dirname "$0")/../Packages/ThubanPlannerCore"
if [[ "${THUBAN_PLANNER_LIVE_BANNER:-0}" == "1" ]]; then
  THUBAN_PLANNER_LIVE_BANNER=1 swift test --filter BannerLiveTests 2>&1 | tee "${TMPDIR:-/tmp}/thuban-planner-live.log" | grep -E "live:|error|failed|skipped|Executed" | tail -20
  exit ${pipestatus[1]}
fi
swift test 2>&1 | tee "${TMPDIR:-/tmp}/thuban-planner-test.log" | grep -E "error|failed|Executed|Build complete" | tail -30
exit ${pipestatus[1]}
