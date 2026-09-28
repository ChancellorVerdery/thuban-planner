#!/bin/zsh
# Checks the V8 sort port against REAL V8 — the one thing the JavaScriptCore-based tests cannot prove (JSC's sort is a
# merge sort, so where comparator call order matters — requirement cycles with lazily memoized depths — Swift's
# V8Sort is otherwise only compared with tools/golden/v8sort.js, which mirrors it).
#
#   1. tools/golden/v8trace.mjs: the port and the engine's own sort must make the SAME comparator calls in the same
#      order on 2,700 seeded arrays (consistent, random and lazily memoizing comparators, up to 3,000 elements).
#   2. tools/golden/gen.mjs with GOLDEN_NATIVE_SORT=1 (Atlas's scheduler on V8's own sort) must reproduce the committed
#      golden-schedule.json (made under JavaScriptCore with the port) byte for byte.
#
# Needs a V8 runtime: `node` or `deno` on PATH, or V8_NODE=<binary> (e.g. an Electron app's binary; it is run with
# ELECTRON_RUN_AS_NODE=1). Exits 2 when there is none. Not part of scripts/test.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
GOLDEN=Packages/ThubanPlannerCore/Tests/ThubanPlannerCoreTests/Fixtures/golden-schedule.json
run=()
if [[ -n "${V8_NODE:-}" ]]; then run=(env ELECTRON_RUN_AS_NODE=1 "$V8_NODE")
elif command -v node >/dev/null; then run=(node)
elif command -v deno >/dev/null; then run=(deno run --allow-env)
else
  echo "v8check: no V8 runtime (install Node, or set V8_NODE=<node-compatible binary>); nothing checked." >&2
  exit 2
fi
engine=$("${run[@]}" -e 'console.log(typeof process !== "undefined" && process.versions && process.versions.v8 ? "v8 " + process.versions.v8 : "unknown")' 2>/dev/null || echo unknown)
echo "v8check: engine $engine"
cmp_=$(mktemp)
trap 'rm -f "$cmp_"' EXIT
(cd tools/golden && TZ=UTC "${run[@]}" v8trace.mjs) | tee /dev/stderr | grep -q ' 0 differ ' || { echo "v8check: FAIL — port differs from V8's sort" >&2; exit 1; }
(cd tools/golden && TZ=UTC GOLDEN_NATIVE_SORT=1 "${run[@]}" gen.mjs) > "$cmp_"
if cmp -s "$cmp_" "$GOLDEN"; then
  echo "v8check: golden cases identical under V8's own sort ($(wc -c < "$GOLDEN" | tr -d ' ') bytes)"
else
  echo "v8check: FAIL — Atlas's scheduler under V8's own sort differs from $GOLDEN" >&2
  exit 1
fi
