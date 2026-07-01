#!/usr/bin/bash
# Top-level build orchestrator: copy system_files, run the numbered MX
# build steps, clean the stage, validate repos are all disabled.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

CTX="${CTX:-/ctx}"

# Network resilience for every dnf5 call in this stage: raise the
# per-connection timeout from the 30s default — COPR/mirror flakes are the
# most common CI build failure (pattern from Aurora upstream).
# clean-stage.sh restores the original dnf.conf.
cp /etc/dnf/dnf.conf /tmp/dnf.conf.orig
dnf5 config-manager setopt timeout=60

# 1. Copy system_files
if [ -d "$CTX/system_files" ]; then
    rsync -rvKl "$CTX/system_files/" /
fi

# 2. Run the numbered MX build scripts
"$CTX/build_files/shared/build-mx.sh"

# 3. Cleanup + repo isolation validation (build fails if any repo enabled=1)
"$CTX/build_files/shared/clean-stage.sh"
"$CTX/build_files/shared/validate-repos.sh"

echo "::endgroup::"
