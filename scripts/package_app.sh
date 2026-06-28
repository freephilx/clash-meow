#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

swift build -c release

binary_path="$(swift build -c release --show-bin-path)"
app_dir="$repo_root/dist/Clash Meow.app"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

cp "$binary_path/ClashMeow" "$app_dir/Contents/MacOS/ClashMeow"
cp -R "$binary_path/ClashMeow_ClashMeow.bundle" "$app_dir/ClashMeow_ClashMeow.bundle"

if [[ -f "$repo_root/Sources/ClashMeow/Resources/mihomo" ]]; then
  cp "$repo_root/Sources/ClashMeow/Resources/mihomo" "$app_dir/Contents/Resources/mihomo"
  chmod +x "$app_dir/Contents/Resources/mihomo"
fi

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>ClashMeow</string>
  <key>CFBundleIdentifier</key>
  <string>com.clash.meow</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Clash Meow</string>
  <key>CFBundleDisplayName</key>
  <string>Clash Meow</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Created $app_dir"
