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

# Guard: if the upstream list ever lost its trailing newline, a plain append
# would glue our first app-id to the last upstream entry.
[ -z "$(tail -c1 "$INSTALL_LIST")" ] || echo >> "$INSTALL_LIST"

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

# Chrome as system-wide default browser. Merged into Bazzite's own
# /etc/xdg/mimeapps.list (which ships e.g. the Bazaar .flatpakref handler)
# instead of shipping a static file that would clobber upstream entries.
# A static default has no timing races (a first-login hook stamps itself
# before Chrome's Flatpak exists and never retries); users can still
# override per-user via ~/.config/mimeapps.list.
XDG_DEFAULTS=/etc/xdg/mimeapps.list
[ -f "$XDG_DEFAULTS" ] || printf '[Default Applications]\n' > "$XDG_DEFAULTS"
grep -q '^\[Default Applications\]' "$XDG_DEFAULTS" || printf '\n[Default Applications]\n' >> "$XDG_DEFAULTS"
for entry in \
    'x-scheme-handler/http=com.google.Chrome.desktop' \
    'x-scheme-handler/https=com.google.Chrome.desktop' \
    'text/html=com.google.Chrome.desktop' \
    'application/xhtml+xml=com.google.Chrome.desktop'; do
    grep -qxF "$entry" "$XDG_DEFAULTS" || sed -i "/^\[Default Applications\]$/a $entry" "$XDG_DEFAULTS"
done

echo "::endgroup::"
