#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> Building Debug (Xcode)..."
xcodebuild -project ClashMeow.xcodeproj -scheme ClashMeow -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet

app_path="$(find ~/Library/Developer/Xcode/DerivedData/ClashMeow-*/Build/Products/Debug -name 'Clash Meow.app' -type d 2>/dev/null | /usr/bin/sort | /usr/bin/tail -n 1)"
if [[ -z "$app_path" ]]; then
  echo "Could not locate built .app in DerivedData" >&2
  exit 1
fi

binary="$app_path/Contents/MacOS/Clash Meow"
if [[ ! -x "$binary" ]]; then
  echo "Could not find executable at $binary" >&2
  exit 1
fi

echo "==> Running mode switch self test..."
echo "    App: $app_path"
set +e
output="$("$binary" -modeSwitchSelfTest 2>&1)"
code=$?
set -e
printf '%s\n' "$output"
echo "==> Exit code: $code"
exit "$code"
