#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resources_dir="$repo_root/Sources/ClashMeow/Resources"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

tag="${1:-${MIHOMO_TAG:-}}"
if [[ -z "$tag" ]]; then
  if command -v gh >/dev/null 2>&1; then
    tag="$(gh release list -R MetaCubeX/mihomo --exclude-pre-releases --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || true)"
  fi
  if [[ -z "$tag" ]]; then
    tag="$(curl -fsSL https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
  fi
fi

arch="$(uname -m)"
case "$arch" in
  arm64) asset="mihomo-darwin-arm64-${tag}.gz" ;;
  x86_64) asset="mihomo-darwin-amd64-${tag}.gz" ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

mkdir -p "$resources_dir"
echo "Downloading MetaCubeX/mihomo $tag ($asset)"

if command -v gh >/dev/null 2>&1 && gh release download "$tag" -R MetaCubeX/mihomo -p "$asset" -D "$tmp_dir" 2>/dev/null; then
  :
else
  curl -fL "https://github.com/MetaCubeX/mihomo/releases/download/${tag}/${asset}" -o "$tmp_dir/$asset"
fi

gzip -dc "$tmp_dir/$asset" > "$resources_dir/mihomo"
chmod +x "$resources_dir/mihomo"

echo "Installed $resources_dir/mihomo"
"$resources_dir/mihomo" -v || true
