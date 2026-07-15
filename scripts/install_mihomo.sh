#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "scripts/install_mihomo.sh is deprecated; preparing the locked runtime cache." >&2
exec "$ROOT/scripts/prepare-mihomo-runtime.sh" "$@"
