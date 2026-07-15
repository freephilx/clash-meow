#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$#" -eq 0 ]]; then
  requested_archs="${MIHOMO_VENDOR_ARCHS:-current}"
  args=()
  for arch in $requested_archs; do
    args+=(--arch "$arch")
  done
  exec /usr/bin/python3 "$ROOT/scripts/mihomo-runtime.py" prepare "${args[@]}"
fi

exec /usr/bin/python3 "$ROOT/scripts/mihomo-runtime.py" prepare "$@"

