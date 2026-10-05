#!/bin/zsh
# Regenerates the bundled UNC Charlotte BSME dataset
# (Packages/ThubanPlannerCore/Sources/ThubanPlannerCore/Resources/uncc-bsme-2025-26.json) from the public catalog,
# catalog.charlotte.edu, read-only, with the headless Chromium in Playwright's cache (the catalog's AWS WAF challenge
# needs JavaScript; no Node needed). Pages are cached in /tmp/thuban-catalog-pages (pass --no-cache to refetch); about
# 160 pages on a cold cache, paced 1 s apart. Then run scripts/test.sh: CatalogDatasetTests checks the Swift parser
# agrees with the dataset on every requirement line.
# Offerings snapshot (Resources/uncc-offerings-snapshot.json, Banner's public class search, one search per subject
# per term): THUBAN_PLANNER_LIVE_OFFERINGS=1 scripts/refresh_catalog.sh --offerings
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--offerings" ]]; then
  out="$PWD/Packages/ThubanPlannerCore/Sources/ThubanPlannerCore/Resources/uncc-offerings-snapshot.json"
  cd Packages/ThubanPlannerCore
  THUBAN_PLANNER_LIVE_OFFERINGS="$out" swift test --filter OfferingsLiveTests 2>&1 | grep -E "live:|error|Executed" | tail -100
  exit 0
fi
python3 tools/catalog/refresh_catalog.py "$@"
