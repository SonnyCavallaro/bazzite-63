#!/usr/bin/bash
# MX block 68: add GUI apps to Bazzite's Flatpak default-install list.
# Present at first boot, auto-updating from Flathub, user-removable. Keeping
# these as Flatpaks (not RPM) means they update without an image rebuild/reboot.
#
# The list is only consumed by Bazzite's ISO installer, never at runtime
# (bazzite-flatpak-manager maintains remotes/overrides but installs nothing):
# on this image the set is installed ON DEMAND by the user via
# `ujust install-default-flatpaks` / `ujust bazzite-63-setup`, which run
# /usr/libexec/bazzite63-flatpak-manager.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

# shellcheck disable=SC1091
source /ctx/build_files/shared/writeback-helpers.sh

INSTALL_LIST=/usr/share/ublue-os/bazzite/flatpak/install
[ -f "$INSTALL_LIST" ] || { echo "FAIL: $INSTALL_LIST not found (Bazzite layout changed?)"; exit 1; }

# Guard: if the upstream list ever lost its trailing newline, a plain append
# would glue our first app-id to the last upstream entry.
[ -z "$(tail -c1 "$INSTALL_LIST")" ] || echo >> "$INSTALL_LIST"

# Idempotent: append each app-id only if not already present, so we extend the
# upstream list instead of replacing it.
for app in \
    org.mozilla.thunderbird \
    me.proton.Pass \
    io.dbeaver.DBeaverCommunity \
    org.remmina.Remmina \
    com.parsecgaming.parsec \
    com.discordapp.Discord; do
    grep -qxF "$app" "$INSTALL_LIST" || echo "$app" >> "$INSTALL_LIST"
done

# The appends land in place on a base-image file (gotcha #40): rewrite the list
# onto a fresh inode so the appended tail survives the layer commit.
rewrite_fresh_inode "$INSTALL_LIST"

echo "::endgroup::"
