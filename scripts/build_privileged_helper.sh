#!/bin/bash
set -euo pipefail

ROOT="${SRCROOT}"
APP_BUNDLE="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"
HELPER_ID="com.dou.clash.helper"
APP_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.dou.clash}"
LAUNCH_SERVICES_DIR="${APP_BUNDLE}/Contents/Library/LaunchServices"
DAEMON_DIR="${APP_BUNDLE}/Contents/Library/LaunchDaemons"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"
BUILD_DIR="${DERIVED_FILE_DIR}/helper-build"
HELPER_BIN="${LAUNCH_SERVICES_DIR}/${HELPER_ID}"
HELPER_INFO="${BUILD_DIR}/${HELPER_ID}-Info.plist"
APP_INFO="${APP_BUNDLE}/Contents/Info.plist"
SIGN_ID="${EXPANDED_CODE_SIGN_IDENTITY:--}"
CODE_SIGN_TIMESTAMP_MODE="${DOUCLASH_CODE_SIGN_TIMESTAMP:-timestamp}"
REQUESTED_ARCHS="${ARCHS:-arm64 x86_64}"
HELPER_ARCHS=()

for arch in ${REQUESTED_ARCHS}; do
  case "${arch}" in
    arm64|x86_64)
      HELPER_ARCHS+=("${arch}")
      ;;
  esac
done

if [[ ${#HELPER_ARCHS[@]} -eq 0 ]]; then
  echo "error: ARCHS does not contain a supported helper architecture: ${REQUESTED_ARCHS}" >&2
  exit 1
fi

mkdir -p "${LAUNCH_SERVICES_DIR}" "${DAEMON_DIR}" "${BUILD_DIR}"
cp "${ROOT}/DouClashHelper/Info.plist" "${HELPER_INFO}"
cp "${ROOT}/DouClashHelper/${HELPER_ID}.plist" "${DAEMON_DIR}/${HELPER_ID}.plist"

SWIFT_SOURCES=(
  "${ROOT}/Sources/DouClash/PrivilegedHelperConstants.swift"
  "${ROOT}/Sources/DouClash/HelperXPCProtocol.swift"
  "${ROOT}/DouClashHelper/HelperService.swift"
  "${ROOT}/DouClashHelper/main.swift"
)

build_helper_binary() {
  local arch
  local helper_inputs=()
  for arch in "${HELPER_ARCHS[@]}"; do
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
    helper_inputs+=("${BUILD_DIR}/helper-${arch}")
  done

  if [[ ${#helper_inputs[@]} -eq 1 ]]; then
    cp "${helper_inputs[0]}" "${BUILD_DIR}/${HELPER_ID}"
  else
    xcrun lipo -create "${helper_inputs[@]}" -output "${BUILD_DIR}/${HELPER_ID}"
  fi

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
while IFS= read -r mihomo_bin; do
  chmod 755 "${mihomo_bin}"
  sign_path "${mihomo_bin}"
done < <(find "${RESOURCES_DIR}/Mihomo" -type f -path "*/bin/mihomo" -print)

python3 - "${HELPER_BIN}" "${HELPER_INFO}" "${APP_INFO}" "${HELPER_ID}" "${APP_ID}" "${SIGN_ID}" <<'PY'
import plistlib
import subprocess
import sys

helper_bin, helper_info, app_info, helper_id, app_id, sign_id = sys.argv[1:7]

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

if sign_id == "-" or not sign_id:
    helper_requirement = f'identifier "{helper_id}"'
    app_requirement = f'identifier "{app_id}"'
else:
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
