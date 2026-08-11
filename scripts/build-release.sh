#!/bin/bash
# Build architecture-specific DouClash packages with the locked Mihomo runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="$ROOT/DouClash.xcodeproj"
SCHEME="DouClash"
CONFIGURATION="Release"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist/release}"
BUILD_ROOT="$ROOT/build/release"
SOURCE_PACKAGES="$BUILD_ROOT/SourcePackages"
RUNTIME_TOOL="$ROOT/scripts/mihomo-runtime.py"
REQUESTED_ARCHS="${PACKAGE_ARCHS:-arm64 x86_64}"
VERSION="${1:-${VERSION:-}}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
ARCHITECTURES=()

usage() {
  cat <<'EOF'
Usage: scripts/build-release.sh [version]

Build ad-hoc signed Apple Silicon and Intel DMGs from the prepared runtime
cache. Run make setup first. This command does not use Developer ID signing or
Apple notarization.

Environment:
  BUILD_NUMBER       CFBundleVersion; defaults to the Xcode setting.
  PACKAGE_ARCHS      Architectures to package; defaults to "arm64 x86_64".
  OUTPUT_DIR         Package output directory; defaults to dist/release.
  SKIP_TESTS=1       Skip the Swift test suite.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

xcode_setting() {
  local key="$1"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null \
    | awk -F'= ' -v key="$key" '{ lhs=$1; gsub(/^[ \t]+|[ \t]+$/, "", lhs); if (lhs == key) { print $2; exit } }'
}

display_architecture() {
  case "$1" in
    arm64) echo "Apple-Silicon" ;;
    x86_64) echo "Intel" ;;
    *) echo "$1" ;;
  esac
}

verify_single_architecture() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(xcrun lipo -archs "$path")"
  [[ "$actual" == "$expected" ]] \
    || fail "architecture mismatch for $path: expected $expected, got $actual"
}

verify_dmg() {
  local dmg_path="$1"
  local architecture="$2"
  local mount_root
  local mounted_app
  local app_binary
  local helper
  local mihomo

  mount_root="$(mktemp -d "$BUILD_ROOT/verify-dmg-$architecture.XXXXXX")"
  mounted_app="$mount_root/DouClash.app"
  if ! hdiutil attach -nobrowse -readonly -mountpoint "$mount_root" "$dmg_path" >/dev/null; then
    rmdir "$mount_root" 2>/dev/null || true
    fail "could not mount generated DMG: $dmg_path"
  fi

  app_binary="$mounted_app/Contents/MacOS/DouClash"
  helper="$mounted_app/Contents/Library/LaunchServices/com.dou.clash.helper"
  mihomo="$mounted_app/Contents/Resources/Mihomo/$architecture/bin/mihomo"

  [[ -x "$app_binary" ]] || fail "main executable missing from $dmg_path"
  [[ -x "$helper" ]] || fail "privileged helper missing from $dmg_path"
  [[ -x "$mihomo" ]] || fail "Mihomo $architecture missing from $dmg_path"
  verify_single_architecture "$app_binary" "$architecture"
  verify_single_architecture "$helper" "$architecture"
  verify_single_architecture "$mihomo" "$architecture"
  codesign --verify --deep --strict "$mounted_app"

  hdiutil detach "$mount_root" >/dev/null
  rmdir "$mount_root"
}

package_architecture() {
  local architecture="$1"
  local display_arch
  local archive_path
  local app_path
  local app_binary
  local helper
  local mihomo
  local package_root
  local dmg_name
  local dmg_path

  display_arch="$(display_architecture "$architecture")"
  archive_path="$BUILD_ROOT/$architecture/DouClash.xcarchive"
  app_path="$archive_path/Products/Applications/DouClash.app"
  app_binary="$app_path/Contents/MacOS/DouClash"
  helper="$app_path/Contents/Library/LaunchServices/com.dou.clash.helper"
  mihomo="$app_path/Contents/Resources/Mihomo/$architecture/bin/mihomo"
  package_root="$BUILD_ROOT/$architecture/dmg-root"
  dmg_name="DouClash-$VERSION-$display_arch.dmg"
  dmg_path="$OUTPUT_DIR/$dmg_name"

  rm -rf "$BUILD_ROOT/$architecture"
  mkdir -p "$(dirname "$archive_path")"
  echo "==> Archiving DouClash $VERSION ($BUILD_NUMBER) for $display_arch"
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
    "ARCHS=$architecture" \
    ONLY_ACTIVE_ARCH=YES \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    ENABLE_HARDENED_RUNTIME=NO \
    DOUCLASH_CODE_SIGN_TIMESTAMP=none

  [[ -d "$app_path" ]] || fail "archived app not found: $app_path"
  [[ -x "$helper" ]] || fail "privileged helper not found: $helper"
  [[ -x "$mihomo" ]] || fail "bundled Mihomo not found: $mihomo"
  [[ ! -d "$app_path/Contents/Resources/Mihomo/$( [[ "$architecture" == arm64 ]] && echo x86_64 || echo arm64 )" ]] \
    || fail "archive unexpectedly contains the other Mihomo architecture"

  verify_single_architecture "$app_binary" "$architecture"
  verify_single_architecture "$helper" "$architecture"
  verify_single_architecture "$mihomo" "$architecture"
  codesign --verify --deep --strict --verbose=2 "$app_path"

  local actual_version
  actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
  [[ "$actual_version" == "$VERSION" ]] \
    || fail "archived app version is $actual_version, expected $VERSION"

  mkdir -p "$package_root"
  ditto "$app_path" "$package_root/DouClash.app"
  ln -s /Applications "$package_root/Applications"
  rm -f "$dmg_path" "$dmg_path.sha256"

  echo "==> Creating $dmg_name"
  hdiutil create \
    -volname "DouClash $VERSION" \
    -srcfolder "$package_root" \
    -format UDZO \
    -ov \
    "$dmg_path"

  (
    cd "$OUTPUT_DIR"
    shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
    shasum -a 256 -c "$dmg_name.sha256"
  )
  verify_dmg "$dmg_path" "$architecture"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
[[ $# -le 1 ]] || { usage >&2; exit 2; }

for command_name in xcodebuild swift xcrun hdiutil codesign shasum ditto; do
  require_command "$command_name"
done

for architecture in $REQUESTED_ARCHS; do
  case "$architecture" in
    arm64|x86_64) ARCHITECTURES+=("$architecture") ;;
    *) fail "unsupported package architecture: $architecture" ;;
  esac
done
[[ ${#ARCHITECTURES[@]} -gt 0 ]] || fail "PACKAGE_ARCHS is empty"

if [[ -z "$VERSION" ]]; then
  VERSION="$(xcode_setting MARKETING_VERSION)"
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || fail "invalid version: $VERSION"

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(xcode_setting CURRENT_PROJECT_VERSION)"
fi
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "BUILD_NUMBER must be numeric: $BUILD_NUMBER"

mkdir -p "$OUTPUT_DIR" "$BUILD_ROOT"

runtime_arguments=()
for architecture in "${ARCHITECTURES[@]}"; do
  runtime_arguments+=(--arch "$architecture")
done

echo "==> Verifying prepared checksum-locked Mihomo dependencies"
/usr/bin/python3 "$RUNTIME_TOOL" verify "${runtime_arguments[@]}"

echo "==> Resolving Swift package dependencies"
xcodebuild \
  -resolvePackageDependencies \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES"

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  echo "==> Running Swift tests"
  swift test --no-parallel
fi

for architecture in "${ARCHITECTURES[@]}"; do
  package_architecture "$architecture"
done

echo
echo "Release packages created in $OUTPUT_DIR:"
for architecture in "${ARCHITECTURES[@]}"; do
  display_arch="$(display_architecture "$architecture")"
  echo "  DouClash-$VERSION-$display_arch.dmg"
  echo "  DouClash-$VERSION-$display_arch.dmg.sha256"
done
echo
echo "Packages use ad-hoc signing and are not notarized. Gatekeeper may block them on other Macs."
