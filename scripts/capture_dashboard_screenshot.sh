#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

output_path="$repo_root/docs/images/app-screenshot.png"
derived_data="$repo_root/.build/DerivedData"
app_path="$derived_data/Build/Products/Debug/DouClash.app"

xcodebuild \
  -scheme DouClash \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  build >/dev/null

rm -f "$output_path"
pkill -x "DouClash" >/dev/null 2>&1 || true

"$app_path/Contents/MacOS/DouClash" \
  -dashboardDemo \
  -exportDashboardScreenshot "$output_path"

if [[ ! -s "$output_path" ]]; then
  echo "Screenshot export failed: $output_path" >&2
  exit 1
fi

echo "Saved screenshot to $output_path"
