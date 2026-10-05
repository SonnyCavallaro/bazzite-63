#!/usr/bin/env bash
# Delete the GitHub releases (and their git tags) older than the newest
# KEEP_STABLE stable and KEEP_TESTING testing ones.
#
# Usage:
#   prune-releases.sh
#
# Env: GH_TOKEN (gh auth, contents: write), REPO (default GITHUB_REPOSITORY),
# KEEP_STABLE (default 3), KEEP_TESTING (default 2), DRY_RUN=true lists the
# verdicts and deletes nothing.
#
# Streams are told apart by tag shape: [testing-]MAJOR.DATE[.N]. A tag of any
# other shape and a draft are never touched. Order is publishedAt, never
# createdAt, which is the target commit's date (gotcha #22). The Latest
# release is kept whatever its rank. The GHCR image of a deleted release stays
# pullable by tag until clean.yml's package pruning rotates it.
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:?REPO or GITHUB_REPOSITORY required}}"
KEEP_STABLE="${KEEP_STABLE:-3}"
KEEP_TESTING="${KEEP_TESTING:-2}"
DRY_RUN="${DRY_RUN:-false}"
LIMIT=200

# Newest first, one "<tag>\t<isLatest>" line per published release.
rows=$(gh release list --repo "$REPO" --limit "$LIMIT" \
  --json tagName,publishedAt,isLatest,isDraft \
  --jq '[.[] | select(.isDraft | not)] | sort_by(.publishedAt) | reverse | .[] | [.tagName, (.isLatest | tostring)] | @tsv')

total=$(printf '%s' "$rows" | grep -c . || true)
if [ "$total" -eq 0 ]; then
  echo "::error::no published release on ${REPO}: refusing to judge an empty list" >&2
  exit 1
fi
if [ "$total" -ge "$LIMIT" ]; then
  echo "::error::${total} releases reach the listing limit ${LIMIT}: the ranking would be partial" >&2
  exit 1
fi

stable=0
testing=0
deleted=0
while IFS=$'\t' read -r tag latest; do
  if [[ "$tag" =~ ^testing-[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    testing=$((testing + 1))
    rank=$testing keep=$KEEP_TESTING
  elif [[ "$tag" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    stable=$((stable + 1))
    rank=$stable keep=$KEEP_STABLE
  else
    echo "ignore ${tag} (not a release tag shape)"
    continue
  fi
  if [ "$rank" -le "$keep" ]; then
    echo "keep   ${tag}"
  elif [ "$latest" = "true" ]; then
    echo "keep   ${tag} (Latest)"
  elif [ "$DRY_RUN" = "true" ]; then
    echo "delete ${tag} (dry run)"
    deleted=$((deleted + 1))
  else
    gh release delete "$tag" --repo "$REPO" --cleanup-tag --yes
    echo "delete ${tag}"
    deleted=$((deleted + 1))
  fi
done <<<"$rows"

echo "${total} releases, ${deleted} deleted$([ "$DRY_RUN" = "true" ] && echo " in a dry run") (keep ${KEEP_STABLE} stable + ${KEEP_TESTING} testing)"
