#!/usr/bin/env bash
# This image's GUI apps join Bazzite's default Flatpak list, after its own
# entries: Flatpaks update in place, without a rebuild or a reboot. Nothing in
# Bazzite reads the list any more (its ISO installs its own list);
# `ujust install-default-flatpaks` (bazzite-63-flatpak-manager) installs it on
# a host, on demand.
#
# Usage: run by build.sh; no arguments.
# Writes: the app ids appended to /usr/share/ublue-os/bazzite/flatpak/install,
#   each once, on a fresh inode, its VulkanLayer runtimes and Firefox dropped;
#   the app ids alone in /usr/share/bazzite-63/flatpak-apps.
# Exit status: 0 done; the build stops on a `FAIL: …` line.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

INSTALL_LIST=/usr/share/ublue-os/bazzite/flatpak/install
IMAGE_APPS=/usr/share/bazzite-63/flatpak-apps
APPS=(
    org.mozilla.thunderbird
    me.proton.Pass
    io.dbeaver.DBeaverCommunity
    org.remmina.Remmina
    com.parsecgaming.parsec
    com.discordapp.Discord
)

if [ "$(grep -cx org.mozilla.firefox "$INSTALL_LIST" || true)" != 1 ]; then
    fail_build "$INSTALL_LIST: org.mozilla.firefox not listed once"
fi

# Bazzite stopped updating the list, whose runtimes are pinned to 23.08, and
# Chrome is this image's browser; awk also ends the base's last line, so the
# first app never joins it.
{
    awk '!/^org\.freedesktop\.Platform\.VulkanLayer\./ && $0 != "org.mozilla.firefox"' \
        "$INSTALL_LIST"

    for app in "${APPS[@]}"; do
        if ! grep -qxF "$app" "$INSTALL_LIST"; then
            echo "$app"
        fi
    done
} > "$INSTALL_LIST.new"
mv -f "$INSTALL_LIST.new" "$INSTALL_LIST"
mkdir -p "$(dirname "$IMAGE_APPS")"
printf '%s\n' "${APPS[@]}" > "$IMAGE_APPS"

log "flatpak-apps: ${#APPS[@]} apps in the default list, $(wc -l < "$INSTALL_LIST") entries"
