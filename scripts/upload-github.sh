#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'EOF'
Usage: scripts/upload-github.sh <tag> [asset ...]

Create or update a GitHub Release and upload release assets.

When no assets are supplied, the command verifies the SHA-256 files in
dist/release/, then uploads only the Apple Silicon and Intel DMGs. The gh CLI
must be authenticated, or GH_TOKEN must be set.

Environment:
  GITHUB_REPOSITORY  Override the target owner/repository.
  RELEASE_TARGET     Commit or branch for a new tag; defaults to current branch.
  RELEASE_NOTES_FILE Use a Markdown file instead of generated release notes.
  PRERELEASE=1       Create a prerelease.
  DRAFT=1            Create a draft release.
  REPLACE_RELEASE=1  Delete and recreate an existing Release without deleting its tag.
  FAIL_IF_RELEASE_EXISTS=1
                      Reject an existing Release instead of updating its assets.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
[[ $# -ge 1 ]] || { usage >&2; exit 2; }
command -v gh >/dev/null 2>&1 || fail "gh CLI is required"

tag="$1"
shift
[[ "$tag" == "Prerelease" || "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || fail "invalid release tag: $tag"
replace_release="${REPLACE_RELEASE:-0}"
[[ "$replace_release" == "0" || "$replace_release" == "1" ]] \
  || fail "REPLACE_RELEASE must be 0 or 1"
fail_if_release_exists="${FAIL_IF_RELEASE_EXISTS:-0}"
[[ "$fail_if_release_exists" == "0" || "$fail_if_release_exists" == "1" ]] \
  || fail "FAIL_IF_RELEASE_EXISTS must be 0 or 1"
[[ "$replace_release" == "0" || "$fail_if_release_exists" == "0" ]] \
  || fail "REPLACE_RELEASE and FAIL_IF_RELEASE_EXISTS cannot both be 1"

repository="${GITHUB_REPOSITORY:-}"
if [[ -z "$repository" ]]; then
  repository="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi
[[ -n "$repository" ]] || fail "could not determine the GitHub repository"

assets=()
if [[ $# -gt 0 ]]; then
  for asset in "$@"; do
    [[ -f "$asset" ]] || fail "asset not found: $asset"
    assets+=("$asset")
  done
else
  version="${tag#v}"
  release_root="$repo_root/dist/release"
  for package_name in \
    "DouMeow-${version}-Apple-Silicon.dmg" \
    "DouMeow-${version}-Intel.dmg"; do
    dmg="$release_root/$package_name"
    checksum="$dmg.sha256"
    [[ -f "$dmg" ]] || fail "release package not found: $dmg"
    [[ -f "$checksum" ]] || fail "release checksum not found: $checksum"
    (cd "$release_root" && shasum -a 256 -c "$(basename "$checksum")")
    assets+=("$dmg")
  done
fi

release_exists=0
if gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
  release_exists=1
fi

if [[ "$release_exists" == "1" && "$fail_if_release_exists" == "1" ]]; then
  fail "release $tag already exists; refusing to overwrite it"
fi
if [[ "$release_exists" == "1" && "$replace_release" == "1" ]]; then
  echo "Release $tag exists; deleting it before replacement"
  gh release delete "$tag" --yes --repo "$repository"
  release_exists=0
fi

if [[ "$release_exists" == "1" ]]; then
  echo "Release $tag exists; replacing matching assets"
  gh release upload "$tag" "${assets[@]}" --clobber --repo "$repository"
else
  release_target="${RELEASE_TARGET:-$(git branch --show-current)}"
  if [[ -z "$release_target" ]]; then
    release_target="$(git rev-parse HEAD)"
  fi
  create_args=(
    release create "$tag" "${assets[@]}"
    --repo "$repository"
    --title "DouMeow ${tag#v}"
  )
  if ! gh api "repos/${repository}/git/ref/tags/${tag}" >/dev/null 2>&1; then
    create_args+=(--target "$release_target")
  fi

  if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
    [[ -f "$RELEASE_NOTES_FILE" ]] || fail "release notes file not found: $RELEASE_NOTES_FILE"
    create_args+=(--notes-file "$RELEASE_NOTES_FILE")
  else
    create_args+=(--generate-notes)
  fi
  if [[ "${PRERELEASE:-0}" == "1" ]]; then
    create_args+=(--prerelease)
  fi
  if [[ "${DRAFT:-0}" == "1" ]]; then
    create_args+=(--draft)
  fi

  echo "Creating GitHub Release $tag in $repository at $release_target"
  gh "${create_args[@]}"
fi

echo "Uploaded ${#assets[@]} asset(s) to ${repository} release ${tag}"
