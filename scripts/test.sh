#!/bin/zsh
# Unit tests for the core package (includes the 400 Atlas golden scheduler cases; regenerate them with
# scripts/golden.sh). Never touches ssh or the real data folder.
set -uo pipefail
cd "$(dirname "$0")/../Packages/ThubanPlannerCore"
swift test 2>&1 | tee "${TMPDIR:-/tmp}/thuban-planner-test.log" | grep -E "error|failed|Executed|Build complete" | tail -30
exit ${pipestatus[1]}
