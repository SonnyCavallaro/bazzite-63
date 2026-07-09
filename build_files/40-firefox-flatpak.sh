#!/usr/bin/env bash
# Firefox leaves the image: bazzite-mx's Fedora RPM is removed with the Bazzite
# defaults copied into it, and the Flatpak's deny line leaves the base's
# filter, so a user who wants Firefox installs Bazzite's Flatpak.
#
# Usage: run by build.sh; no arguments.
# Writes: firefox and firefox-langpacks removed, /usr/lib64/firefox gone; the
#   `deny org.mozilla.firefox/*` line out of the Flatpak filter, on a fresh
#   inode.
# Exit status: 0 done; the build stops on a `FAIL: …` line when the deny line
#   is not where the base put it.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

FIREFOX_DIR=/usr/lib64/firefox
# The base's Flatpak filter, which bazzite-flatpak-manager sets on Flathub.
FLATPAK_BLOCKLIST=/usr/share/ublue-os/flatpak-blocklist
DENY_LINE='deny org.mozilla.firefox/*'

# --- the steps ----------------------------------------------------------------

# The Bazzite defaults bazzite-mx installed beside the RPM belong to no
# package, so the directory goes with them.
remove_firefox_rpm() {
    dnf5 -y remove firefox firefox-langpacks
    rm -rf "$FIREFOX_DIR"
}

allow_firefox_flatpak() {
    local count

    count=$(grep -cxF -- "$DENY_LINE" "$FLATPAK_BLOCKLIST" || true)

    if [ "$count" != 1 ]; then
        fail_build "$FLATPAK_BLOCKLIST: '$DENY_LINE' found ${count:-0} times, expected once"
    fi

    grep -vxF -- "$DENY_LINE" "$FLATPAK_BLOCKLIST" > "$FLATPAK_BLOCKLIST.new" || true
    mv -f "$FLATPAK_BLOCKLIST.new" "$FLATPAK_BLOCKLIST"
}

# --- main ---------------------------------------------------------------------

remove_firefox_rpm
allow_firefox_flatpak

log "firefox-flatpak: the RPM removed, the Flatpak allowed"
