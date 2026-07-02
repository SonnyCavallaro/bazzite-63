#!/usr/bin/env bash
# Smoke test of 12-host-helpers.sh: the helpers name this image's scope and
# registries.d file, not bazzite-mx's, and migrate's self-test, which drives
# host.sh through its plan and apply on fixture hosts, still passes on the
# renamed code.
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$(realpath "$0")")/lib.sh"

HOST_LIBRARY=/usr/lib/bazzite-mx/host.sh
VERIFY_HOST=/usr/libexec/bazzite-mx-verify-host
MIGRATE=/usr/libexec/bazzite-mx-migrate

check_no_base_scope() {
    local hits

    hits=$(grep -l matrixdj96 "$HOST_LIBRARY" "$VERIFY_HOST" "$MIGRATE" 2>&1 || true)

    if [ -z "$hits" ]; then
        echo "OK: no helper names matrixdj96"
    else
        echo "FAIL: still naming matrixdj96: $(on_one_line none <<< "$hits")"
    fi
}

check_scope_lines() {
    if grep -qxF 'VENDOR_SCOPE=ghcr.io/sonnycavallaro' "$HOST_LIBRARY" 2> /dev/null \
        && grep -qxF 'REGISTRIES=/etc/containers/registries.d/sonnycavallaro.yaml' \
            "$VERIFY_HOST" 2> /dev/null; then
        echo "OK: host.sh and verify-host read ghcr.io/sonnycavallaro and its registries.d file"
    else
        echo "FAIL: host.sh or verify-host does not read ghcr.io/sonnycavallaro"
    fi
}

check_no_base_scope
check_scope_lines
check_self_test migrate "$MIGRATE"
