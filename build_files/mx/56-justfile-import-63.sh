#!/usr/bin/bash
# MX block 56: register the bazzite-63 justfile in Bazzite's master ujust file.
#
# Companion to 55-justfile-reconcile.sh (kept verbatim from bazzite-mx): the
# bazzite-63 additions live in their own 96-bazzite-63.just so upstream's
# 95-bazzite-mx.just and its import script can be synced untouched. Idempotent
# append at the end of the master, preserving all upstream imports.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

# shellcheck disable=SC1091
source /ctx/build_files/shared/writeback-helpers.sh

MASTER=/usr/share/ublue-os/justfile
IMPORT_LINE='import "/usr/share/ublue-os/just/96-bazzite-63.just"'

if [ ! -f "$MASTER" ]; then
    echo "FAIL: $MASTER not found (did Bazzite change layout?)"
    exit 1
fi

if grep -qxF "$IMPORT_LINE" "$MASTER"; then
    echo "Import line already present in $MASTER, nothing to do."
else
    {
        echo ""
        echo "# bazzite-63 custom recipes"
        echo "$IMPORT_LINE"
    } >> "$MASTER"
    echo "Import line appended to $MASTER."
fi

# This script is the LAST writer of $MASTER: 55-justfile-reconcile.sh closes
# with a fresh-inode rewrite, and the append above lands in place on that file
# again, so the torn-writeback exposure returns (gotcha #40 — release
# 44.20260826.1 shipped $MASTER with its import tail replaced by NUL bytes and
# `ujust` died on deploy with "unknown start of token '' (U+0000)"). Rewrite
# once more; check-image-integrity.sh re-proves the cold bytes after rechunk.
rewrite_fresh_inode "$MASTER"

echo "::endgroup::"
