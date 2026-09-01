#!/usr/bin/env bash
# Resolve the upstream Bazzite tag and the downstream release tag for a stream.
#
# Usage:
#   resolve-release-tag.sh <stream_name> [upstream_tag]
#
# stream_name: stable | testing. upstream_tag empty = latest for the stream.
# Env: GH_TOKEN (gh auth), REPO_FULL (owner/repo). Writes upstream_tag= and
# release_tag= to $GITHUB_OUTPUT (stdout when unset, for local testing).
#
# Single owner of the downstream tag schema: [testing-]MAJOR.<build date>[.N].
set -euo pipefail

STREAM="${1:?stream_name required}"
UP="${2:-}"
REPO_FULL="${REPO_FULL:?REPO_FULL (owner/repo) required}"

# Latest upstream release for the stream when no explicit tag is given.
if [ -z "$UP" ]; then
  if [ "$STREAM" = "stable" ]; then
    UP=$(gh release view --repo ublue-os/bazzite --json tagName -q .tagName)
  else
    UP=$(gh release list --repo ublue-os/bazzite --json tagName,publishedAt --limit 50 \
      | jq -r '[.[] | select(.tagName|startswith("testing-"))] | sort_by(.publishedAt) | last | .tagName')
  fi
fi

# A three-group tag is either a genuine upstream same-date rebuild (which we
# build on and track) or a stray downstream .N fed via dispatch (which 404s as
# an upstream link). Keep it when it exists upstream; otherwise strip the .N.
if [[ "$UP" =~ ^(testing-)?[0-9]+\.[0-9]+\.[0-9]+$ ]] \
   && ! gh release view --repo ublue-os/bazzite "$UP" >/dev/null 2>&1; then
  echo "::warning::upstream tag ${UP} not found on ublue-os/bazzite; using ${UP%.*}"
  UP="${UP%.*}"
fi

# Downstream release tags live on their own calendar: [testing-]MAJOR.<build
# date>, independent of the upstream tag's date, so upstream's own .N suffixes
# never leak into our nomenclature. First build of the day uses the bare tag;
# same-day rebuilds append .1 .2 .3 via collision detection.
FEDORA_MAJOR="${UP#testing-}"
FEDORA_MAJOR="${FEDORA_MAJOR%%.*}"
PREFIX="${FEDORA_MAJOR}.$(date -u +%Y%m%d)"
if [ "$STREAM" != "stable" ]; then
  PREFIX="testing-${PREFIX}"
fi

# gh exits 0 with empty output when the repo has no releases yet; a real API
# failure aborts via set -e — fail-closed, never pick a tag on partial data.
EXISTING=$(gh release list --repo "$REPO_FULL" --limit 200 --json tagName -q '.[].tagName')

OWNER_LC="${REPO_FULL%%/*}"
OWNER_LC="${OWNER_LC,,}"

# A tag is taken when a Release exists OR any flavour already carries the GHCR
# tag (a build whose release step failed): re-picking it would silently repoint
# an immutable, cosign-signed tag. Fail-closed: a GHCR probe error other than a
# plain missing image aborts instead of reading as "tag free". The probe
# authenticates with GH_TOKEN when available: an anonymous probe against a
# package that does not exist yet (fresh repo, post-wipe) dies at the bearer
# token request with a bare 403 — indistinguishable from a real failure —
# while the authenticated probe answers "manifest unknown". Missing includes
# denied/unauthorized, which GHCR still answers for absent packages.
PROBE_CREDS=()
if [ -n "${GH_TOKEN:-}" ]; then
  PROBE_CREDS=(--creds "${OWNER_LC}:${GH_TOKEN}")
fi
taken() {
  echo "$EXISTING" | grep -qx "$1" && return 0
  local img out
  for img in bazzite-mx bazzite-mx-nvidia bazzite-mx-nvidia-open; do
    if out=$(skopeo inspect "${PROBE_CREDS[@]}" --no-tags "docker://ghcr.io/${OWNER_LC}/${img}:$1" 2>&1); then
      return 0
    fi
    if ! grep -qiE 'manifest unknown|name unknown|not found|denied|unauthorized' <<<"$out"; then
      echo "::error::GHCR probe failed for ${img}:$1 — refusing to assume the tag is free"
      echo "$out"
      exit 1
    fi
  done
  return 1
}

RT="$PREFIX"
N=0
while taken "$RT"; do
  N=$((N+1))
  RT="${PREFIX}.${N}"
done

{
  echo "upstream_tag=$UP"
  echo "release_tag=$RT"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "Upstream: $UP"
echo "Release tag: $RT"
