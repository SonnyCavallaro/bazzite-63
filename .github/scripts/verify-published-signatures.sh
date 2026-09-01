#!/usr/bin/env bash
# Verify one stream's published images against cosign.pub, negative control first.
#
# Usage:
#   verify-published-signatures.sh <stream_name>
#
# Env: REPO_OWNER, MATRIX_INCLUDE (the JSON build matrix — the image set is
# DERIVED from it, never a literal list). Run from the repo root: cosign.pub
# is read from the working directory.
#
# Pattern from akmods verify-publication, trimmed of the policy pull: a
# signature check that cannot fail proves nothing, so an image signed by a
# FOREIGN key (upstream's) must be rejected before any acceptance counts.
set -euo pipefail

STREAM="${1:?stream_name required}"
MATRIX_INCLUDE="${MATRIX_INCLUDE:?MATRIX_INCLUDE (JSON build matrix) required}"
REPO_OWNER="${REPO_OWNER:?REPO_OWNER required}"

registry="ghcr.io/${REPO_OWNER,,}"
retry() { local n; for n in 1 2 3 4 5; do "$@" && return 0; [ "$n" -eq 5 ] && return 1; sleep $((n * 5)); done; }

mapfile -t images < <(jq -r --arg s "$STREAM" '[.[] | select(.stream_name == $s).image_name] | unique[]' <<< "$MATRIX_INCLUDE")
if [ "${#images[@]}" -eq 0 ]; then
  echo "::error::no ${STREAM} images in the build matrix — this stream should never have reached verification"
  exit 1
fi

# Negative control first: cosign.pub must REJECT an image signed by another
# key, or every acceptance below is vacuous.
if cosign verify --key cosign.pub "ghcr.io/ublue-os/bazzite:stable" > /dev/null 2>&1; then
  echo "::error::negative control failed: cosign.pub accepted a foreign signature"
  exit 1
fi
echo "OK: negative control rejected the foreign-signed image"
for img in "${images[@]}"; do
  digest=$(retry skopeo inspect --no-tags "docker://${registry}/${img}:${STREAM}" | jq -r .Digest)
  retry cosign verify --key cosign.pub "${registry}/${img}@${digest}" > /dev/null
  echo "OK: ${img}@${digest} verified"
done
