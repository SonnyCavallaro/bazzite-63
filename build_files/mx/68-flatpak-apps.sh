#!/usr/bin/bash
# MX block 68: add GUI apps to Bazzite's Flatpak default-install list.
# Present at first boot, auto-updating from Flathub, user-removable. Keeping
# these as Flatpaks (not RPM) means they update without an image rebuild/reboot.
#
# The list is only consumed by Bazzite's ISO installer, never at runtime
# (bazzite-flatpak-manager maintains remotes/overrides but installs nothing),
# so bazzite63-flatpak-manager.service (enabled below) installs it at boot —
# otherwise a stock-ISO + `bootc switch` system would never get these apps.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

INSTALL_LIST=/usr/share/ublue-os/bazzite/flatpak/install
[ -f "$INSTALL_LIST" ] || { echo "FAIL: $INSTALL_LIST not found (Bazzite layout changed?)"; exit 1; }

# Idempotent: append each app-id only if not already present, so we extend the
# upstream list instead of replacing it.
for app in \
    com.google.Chrome \
    org.mozilla.Thunderbird \
    me.proton.Pass \
    io.dbeaver.DBeaverCommunity \
    org.remmina.Remmina \
    com.parsecgaming.parsec \
    com.discordapp.Discord; do
    grep -qxF "$app" "$INSTALL_LIST" || echo "$app" >> "$INSTALL_LIST"
done

# Boot-time installer for the list above (see header).
systemctl enable bazzite63-flatpak-manager.service

echo "::endgroup::"
