#!/usr/bin/bash
# MX block 56: register the bazzite-63 justfile in Bazzite's master ujust file.
#
# Companion to 55-justfile-reconcile.sh (kept verbatim from bazzite-mx): the
# bazzite-63 additions live in their own 96-bazzite-63.just so upstream's
# 95-bazzite-mx.just and its import script can be synced untouched. Idempotent
# append at the end of the master, preserving all upstream imports.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

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

echo "::endgroup::"
