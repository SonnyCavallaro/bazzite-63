#!/usr/bin/env bash
# Emit the Markdown body for a bazzite-63 GitHub Release on stdout:
# intro + Upstream section (Bazzite compare diff) + image digest table
# + commits table + How-to-rebase + cosign verify hint.
#
# Usage:
#   changelog.sh <upstream_tag> <release_tag> <prev_tag> \
#                <digest_main> [stream_name] [prev_upstream]
#
# stream_name (default "stable") drives the bootc switch tag in "How to rebase"
# (:stable vs :testing) so users land on the right mutable channel.
# prev_upstream is the upstream tag the previous release was built off
# (recovered by the caller from that release's title); empty when unknown.
#
# Env vars (auto-populated by GitHub Actions, override for local testing):
#   GITHUB_REPOSITORY_OWNER  e.g. SonnyCavallaro
#   GITHUB_REPOSITORY        e.g. SonnyCavallaro/bazzite-63
set -euo pipefail

UPSTREAM_TAG="${1:?upstream_tag required}"
RELEASE_TAG="${2:?release_tag required}"
PREV_TAG="${3:-}"
DIGEST_MAIN="${4:?digest for bazzite-63 required}"
STREAM_NAME="${5:-stable}"
PREV_UPSTREAM="${6:-}"

OWNER="${GITHUB_REPOSITORY_OWNER:-SonnyCavallaro}"
OWNER_LC="${OWNER,,}"
REPO="${GITHUB_REPOSITORY:-${OWNER}/bazzite-63}"

UPSTREAM_REPO="ublue-os/bazzite"
COSIGN_PUB_URL="https://raw.githubusercontent.com/${REPO}/main/cosign.pub"

# The upstream tag arrives authoritative from the caller (the resolve jobs
# 404-gate it against real ublue-os/bazzite releases), so it is used verbatim —
# including upstream's own same-day rebuild suffix (e.g. testing-44.20260705.1).
UPSTREAM_URL="https://github.com/${UPSTREAM_REPO}/releases/tag/${UPSTREAM_TAG}"

# Downstream release tags live on their own calendar: [testing-]MAJOR.<build
# date>, plus a third numeric group .N for same-day rebuilds. That .N is always
# ours, so a rebuild is recognisable from the release tag alone.
IS_REBUILD="no"
if [[ "${RELEASE_TAG}" =~ ^(testing-)?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  IS_REBUILD="yes"
fi

# --- Intro paragraph -------------------------------------------------------
if [[ -z "${PREV_TAG}" ]]; then
  COUNT="$(git rev-list --count HEAD 2>/dev/null || echo "?")"
  cat <<EOF
This is an automatically generated changelog for \`bazzite-63\` release \`${RELEASE_TAG}\`, built off [\`ublue-os/bazzite@${UPSTREAM_TAG}\`](${UPSTREAM_URL}).

This is the initial release. ${COUNT} commits in the repository at the time of build.
EOF
else
  PREV_URL="https://github.com/${REPO}/releases/tag/${PREV_TAG}"
  cat <<EOF
This is an automatically generated changelog for \`bazzite-63\` release \`${RELEASE_TAG}\`, built off [\`ublue-os/bazzite@${UPSTREAM_TAG}\`](${UPSTREAM_URL}).

Previous release: [\`${PREV_TAG}\`](${PREV_URL}).
EOF
fi

# --- Upstream section ------------------------------------------------------
# The real delta between two bazzite-63 releases is almost always the upstream
# Bazzite bump. Show the compare diff when the upstream tag moved; otherwise say
# plainly that this is a same-upstream rebuild with no upstream changes.
cat <<EOF

### Upstream
EOF
if [[ -n "${PREV_UPSTREAM}" && "${PREV_UPSTREAM}" != "${UPSTREAM_TAG}" ]]; then
  COMPARE_URL="https://github.com/${UPSTREAM_REPO}/compare/${PREV_UPSTREAM}...${UPSTREAM_TAG}"
  echo ""
  echo "Bazzite \`${PREV_UPSTREAM}\` → \`${UPSTREAM_TAG}\` — [compare upstream changes ↗](${COMPARE_URL})."
elif [[ -n "${PREV_UPSTREAM}" && "${IS_REBUILD}" == "yes" ]]; then
  echo ""
  echo "Downstream rebuild on the same upstream tag \`${UPSTREAM_TAG}\` — no upstream changes."
elif [[ -n "${PREV_UPSTREAM}" ]]; then
  echo ""
  echo "Tracks Bazzite \`${UPSTREAM_TAG}\` — unchanged since the previous release."
else
  echo ""
  echo "Tracks Bazzite \`${UPSTREAM_TAG}\`."
fi

# --- Images table (our value-add) ------------------------------------------
cat <<EOF

### Images

| Variant | Pull reference (immutable digest) |
| --- | --- |
| \`bazzite-63\` | \`ghcr.io/${OWNER_LC}/bazzite-63@${DIGEST_MAIN}\` |
EOF

# --- Commits table (downstream repo changes, when there are any) ------------
if [[ -n "${PREV_TAG}" ]]; then
  COMMITS="$(git log "${PREV_TAG}..HEAD" \
    --pretty=format:"| **[\`%h\`](https://github.com/${REPO}/commit/%H)** | %s | %an |" \
    2>/dev/null || true)"
  cat <<EOF

### Commits (bazzite-63)
EOF
  if [[ -n "${COMMITS}" ]]; then
    cat <<EOF

| Hash | Subject | Author |
| --- | --- | --- |
${COMMITS}
EOF
  else
    echo ""
    echo "_No downstream changes — this release only refreshes against upstream._"
  fi
fi

# --- How to rebase ---------------------------------------------------------
cat <<EOF

### How to rebase

For current users, run:

\`\`\`bash
# For the latest ${STREAM_NAME} (mobile tag, follows future releases automatically):
sudo bootc switch ghcr.io/${OWNER_LC}/bazzite-63:${STREAM_NAME}

# For this specific release (immutable, pinned):
sudo bootc switch ghcr.io/${OWNER_LC}/bazzite-63:${RELEASE_TAG}
\`\`\`

### Verify

Each image is signed at build time. Before rebasing in security-sensitive contexts:

\`\`\`bash
cosign verify --key ${COSIGN_PUB_URL} <ref>
\`\`\`
EOF
