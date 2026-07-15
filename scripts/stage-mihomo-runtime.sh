#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/Mihomo}"
requested_archs="${ARCHS:-$(uname -m)}"
args=()

for arch in $requested_archs; do
  case "$arch" in
    arm64|x86_64)
      args+=(--arch "$arch")
      ;;
  esac
done

if [[ ${#args[@]} -eq 0 ]]; then
  echo "error: ARCHS does not contain a supported Mihomo architecture: $requested_archs" >&2
  exit 1
fi

exec /usr/bin/python3 "$ROOT/scripts/mihomo-runtime.py" stage \
  --destination "$DESTINATION" \
  "${args[@]}"

