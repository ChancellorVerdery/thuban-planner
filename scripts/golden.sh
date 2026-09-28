#!/bin/zsh
# Regenerates the scheduler golden cases by running Atlas's own scheduler (tools/golden/atlas-course.js) under macOS's
# built-in JavaScriptCore with V8's sort order (tools/golden/v8sort.js). No Node needed. Then run scripts/test.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
JSC=/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc
OUT=Packages/ThubanPlannerCore/Tests/ThubanPlannerCoreTests/Fixtures/golden-schedule.json
(cd tools/golden && TZ=UTC "$JSC" -m sortcheck.mjs)
(cd tools/golden && TZ=UTC "$JSC" -m gen.mjs) > "$OUT"
echo "wrote $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
