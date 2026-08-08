#!/bin/bash
# Build current code and upload versioned DMG packages to a GitHub Release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/ClashMeow.xcodeproj"
SCHEME="${SCHEME:-ClashMeow}"
CONFIGURATION="${CONFIGURATION:-Release}"

usage() {
  cat <<'EOF'
Usage: scripts/release.sh

Build the Apple Silicon and Intel DMGs, then create or update the matching
GitHub Release. GitHub creates a missing release tag at the selected target.

Environment:
  PACKAGE_VERSION    Package version; defaults to Xcode MARKETING_VERSION.
  RELEASE_TAG        GitHub release tag; defaults to v<package version>.
  RELEASE_TARGET     Commit or branch for a new tag; defaults to current branch.
  RELEASE_REMOTE     Git remote used to push a missing tag; defaults to origin.
  ALLOW_DIRTY=1      Allow packaging an uncommitted working tree.
  BUILD_NUMBER       CFBundleVersion passed to build-release.sh.
  GITHUB_REPOSITORY  Override the target owner/repository.
  RELEASE_NOTES_FILE Use a Markdown file instead of generated release notes.
  PRERELEASE=1       Create a prerelease.
  DRAFT=1            Create a draft release.
  SKIP_TESTS=1       Skip the Swift test suite during packaging.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

build_setting() {
  local key="$1"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null \
    | awk -F'= ' -v key="$key" '{ lhs=$1; gsub(/^[ \t]+|[ \t]+$/, "", lhs); if (lhs == key) { print $2; exit } }'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
[[ $# -eq 0 ]] || { usage >&2; exit 2; }

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is required"
command -v gh >/dev/null 2>&1 || fail "gh CLI is required"
command -v git >/dev/null 2>&1 || fail "git is required"

version="${PACKAGE_VERSION:-$(build_setting MARKETING_VERSION)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || fail "invalid package version: $version"
release_tag="${RELEASE_TAG:-v$version}"
release_remote="${RELEASE_REMOTE:-origin}"
release_target="${RELEASE_TARGET:-$(git branch --show-current)}"
if [[ -z "$release_target" ]]; then
  release_target="$(git rev-parse HEAD)"
fi

if [[ -n "$(git status --porcelain)" && "${ALLOW_DIRTY:-0}" != "1" ]]; then
  echo "error: 工作区存在未提交修改。请先提交，或设置 ALLOW_DIRTY=1 强制发布。" >&2
  git status --short >&2
  exit 1
fi

ensure_release_tag() {
  local target_commit
  local remote_commit
  local local_commit

  target_commit="$(git rev-parse "${release_target}^{commit}")" \
    || fail "cannot resolve release target: $release_target"
  remote_commit="$(git ls-remote "$release_remote" "refs/tags/$release_tag^{}" | awk 'NR == 1 { print $1 }')"
  if [[ -z "$remote_commit" ]]; then
    remote_commit="$(git ls-remote "$release_remote" "refs/tags/$release_tag" | awk 'NR == 1 { print $1 }')"
  fi

  if [[ -n "$remote_commit" ]]; then
    [[ "$remote_commit" == "$target_commit" ]] \
      || fail "remote tag $release_tag points to $remote_commit, expected $target_commit"
    echo "==> Remote tag already exists: $release_tag"
    return
  fi

  local_commit="$(git rev-list -n 1 "$release_tag" 2>/dev/null || true)"
  if [[ -n "$local_commit" ]]; then
    [[ "$local_commit" == "$target_commit" ]] \
      || fail "local tag $release_tag points to $local_commit, expected $target_commit"
  else
    echo "==> Creating local tag: $release_tag -> $target_commit"
    git tag "$release_tag" "$target_commit"
  fi

  echo "==> Pushing tag to $release_remote: $release_tag"
  git push "$release_remote" "refs/tags/$release_tag"
}

echo "==> Release: $release_tag"
echo "==> Version: $version"
echo "==> Target: $release_target"
"$ROOT/scripts/build-release.sh" "$version"
ensure_release_tag

assets=(
  "$ROOT/dist/release/Clash-Meow-$version-Apple-Silicon.dmg"
  "$ROOT/dist/release/Clash-Meow-$version-Apple-Silicon.dmg.sha256"
  "$ROOT/dist/release/Clash-Meow-$version-Intel.dmg"
  "$ROOT/dist/release/Clash-Meow-$version-Intel.dmg.sha256"
)
for asset in "${assets[@]}"; do
  [[ -f "$asset" ]] || fail "release asset not found: $asset"
done
"$ROOT/scripts/upload-github.sh" "$release_tag" "${assets[@]}"
