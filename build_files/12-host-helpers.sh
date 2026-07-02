#!/usr/bin/env bash
# The host helpers the base ships (ujust migrate, verify-host and the library
# they share) name bazzite-mx's registry scope: on this image they would send
# a host to ghcr.io/matrixdj96 and check that scope's policy. The scope and its
# registries.d file are renamed to this image's, ghcr.io/sonnycavallaro and
# sonnycavallaro.yaml (11-image-signing.sh writes their policy); everything
# else in the helpers stays bazzite-mx's.
#
# Usage: run by build.sh after 11-image-signing.sh; no arguments.
# Writes: /usr/lib/bazzite-mx/host.sh, /usr/libexec/bazzite-mx-verify-host and
#   /usr/libexec/bazzite-mx-migrate, each on a fresh inode.
# Exit status: 0 done; the build stops on a `FAIL: …` line when an anchor the
#   rename relies on is not found exactly once.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

BASE_VENDOR=matrixdj96
VENDOR=sonnycavallaro

HOST_LIBRARY=/usr/lib/bazzite-mx/host.sh
VERIFY_HOST=/usr/libexec/bazzite-mx-verify-host
MIGRATE=/usr/libexec/bazzite-mx-migrate
SHADOWING="^M[[:space:]]+containers/(policy\\.json|registries\\.d/$BASE_VENDOR\\.yaml)\$"

# <file>|<line the file must hold once>: where each helper reads the scope, so
# a base that moved it elsewhere stops the build.
ANCHORS=(
    "$HOST_LIBRARY|VENDOR_SCOPE=ghcr.io/$BASE_VENDOR"
    "$VERIFY_HOST|REGISTRIES=/etc/containers/registries.d/$BASE_VENDOR.yaml"
    "$MIGRATE|    local shadowing='$SHADOWING'"
)

# --- the steps ----------------------------------------------------------------

require_anchors() {
    local entry file anchor count

    for entry in "${ANCHORS[@]}"; do
        file=${entry%%|*}
        anchor=${entry#*|}
        count=$(grep -cxF -- "$anchor" "$file" || true)

        if [ "$count" != 1 ]; then
            fail_build "$file: '$anchor' found ${count:-0} times, expected once"
        fi
    done
}

# The rename covers the helper's self-test fixtures too, so its self-test keeps
# describing the code it tests.
rename_scope() {
    local entry file

    for entry in "${ANCHORS[@]}"; do
        file=${entry%%|*}

        sed "s/$BASE_VENDOR/$VENDOR/g" "$file" > "$file.new"
        chmod --reference="$file" "$file.new"
        mv -f "$file.new" "$file"
    done
}

# --- main ---------------------------------------------------------------------

require_anchors
rename_scope

log "host-helpers: migrate and verify-host follow ghcr.io/$VENDOR"
