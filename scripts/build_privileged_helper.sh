#!/bin/bash
set -euo pipefail

ROOT="${SRCROOT}"
APP_BUNDLE="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"
HELPER_ID="com.clash.meow.helper"
APP_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.clash.meow}"
LAUNCH_SERVICES_DIR="${APP_BUNDLE}/Contents/Library/LaunchServices"
DAEMON_DIR="${APP_BUNDLE}/Contents/Library/LaunchDaemons"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"
BUILD_DIR="${DERIVED_FILE_DIR}/helper-build"
HELPER_BIN="${LAUNCH_SERVICES_DIR}/${HELPER_ID}"
MIHOMO_BIN="${RESOURCES_DIR}/mihomo"
HELPER_INFO="${BUILD_DIR}/${HELPER_ID}-Info.plist"
APP_INFO="${APP_BUNDLE}/Contents/Info.plist"
SIGN_ID="${EXPANDED_CODE_SIGN_IDENTITY:--}"
CODE_SIGN_TIMESTAMP_MODE="${CLASH_MEOW_CODE_SIGN_TIMESTAMP:-timestamp}"

mkdir -p "${LAUNCH_SERVICES_DIR}" "${DAEMON_DIR}" "${BUILD_DIR}"
cp "${ROOT}/ClashMeowHelper/Info.plist" "${HELPER_INFO}"
cp "${ROOT}/ClashMeowHelper/${HELPER_ID}.plist" "${DAEMON_DIR}/${HELPER_ID}.plist"

SWIFT_SOURCES=(
  "${ROOT}/Sources/ClashMeow/PrivilegedHelperConstants.swift"
  "${ROOT}/Sources/ClashMeow/HelperXPCProtocol.swift"
  "${ROOT}/ClashMeowHelper/HelperService.swift"
  "${ROOT}/ClashMeowHelper/main.swift"
)

build_helper_binary() {
  for arch in arm64 x86_64; do
    xcrun swiftc \
      -target "${arch}-apple-macos14.0" \
      -O \
      "${SWIFT_SOURCES[@]}" \
      -framework Foundation \
      -Xlinker -sectcreate \
      -Xlinker __TEXT \
      -Xlinker __info_plist \
      -Xlinker "${HELPER_INFO}" \
      -Xlinker -sectcreate \
      -Xlinker __TEXT \
      -Xlinker __launchd_plist \
      -Xlinker "${DAEMON_DIR}/${HELPER_ID}.plist" \
      -o "${BUILD_DIR}/helper-${arch}"
  done

  xcrun lipo -create \
    "${BUILD_DIR}/helper-arm64" \
    "${BUILD_DIR}/helper-x86_64" \
    -output "${BUILD_DIR}/${HELPER_ID}"

  rm -rf "${HELPER_BIN}"
  cp "${BUILD_DIR}/${HELPER_ID}" "${HELPER_BIN}"
  chmod 755 "${HELPER_BIN}"
}

sign_path() {
  if [ "${SIGN_ID}" != "-" ] && [ -n "${SIGN_ID}" ]; then
    local timestamp_args=()
    if [ "${CODE_SIGN_TIMESTAMP_MODE}" = "none" ]; then
      timestamp_args=(--timestamp=none)
    else
      timestamp_args=(--timestamp)
    fi
    codesign --force --options runtime "${timestamp_args[@]}" --sign "${SIGN_ID}" "$1"
  else
    codesign --force --sign - "$1"
  fi
}

build_helper_binary
sign_path "${HELPER_BIN}"
if [ -f "${MIHOMO_BIN}" ]; then
  chmod 755 "${MIHOMO_BIN}"
  sign_path "${MIHOMO_BIN}"
fi

python3 - "${HELPER_BIN}" "${HELPER_INFO}" "${APP_INFO}" "${HELPER_ID}" "${APP_ID}" <<'PY'
import plistlib
import subprocess
import sys

helper_bin, helper_info, app_info, helper_id, app_id = sys.argv[1:6]

def designated_requirement(path: str) -> str:
    result = subprocess.run(
        ["codesign", "-d", "-r-", path],
        capture_output=True,
        text=True,
        check=False,
    )
    output = result.stderr + result.stdout
    marker = "designated => "
    if marker not in output:
        raise SystemExit(f"Cannot read designated requirement for {path}\n{output}")
    return output.split(marker, 1)[1].strip()

helper_requirement = designated_requirement(helper_bin)
app_requirement = helper_requirement.replace(f'identifier "{helper_id}"', f'identifier "{app_id}"', 1)

with open(app_info, "rb") as handle:
    app_plist = plistlib.load(handle)
app_plist.setdefault("SMPrivilegedExecutables", {})[helper_id] = helper_requirement
with open(app_info, "wb") as handle:
    plistlib.dump(app_plist, handle)

with open(helper_info, "rb") as handle:
    helper_plist = plistlib.load(handle)
helper_plist["SMAuthorizedClients"] = [app_requirement]
with open(helper_info, "wb") as handle:
    plistlib.dump(helper_plist, handle)

print(f"Updated SMPrivilegedExecutables: {helper_requirement}")
print(f"Updated SMAuthorizedClients: {helper_plist['SMAuthorizedClients'][0]}")
PY

build_helper_binary
sign_path "${HELPER_BIN}"
