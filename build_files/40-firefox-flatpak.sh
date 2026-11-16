#!/usr/bin/env bash
# Firefox leaves the image: bazzite-mx's Fedora RPM is removed with the Bazzite
# defaults copied into it, and the Flatpak's entry leaves the base's Bazaar
# blocklist, so a user who wants Firefox installs Bazzite's Flatpak.
#
# Usage: run by build.sh; no arguments.
# Writes: firefox and firefox-langpacks removed, /usr/lib64/firefox gone; the
#   org.mozilla.firefox entry out of the Bazaar blocklist, on a fresh inode.
# Exit status: 0 done; the build stops on a `FAIL: …` line when the entry is
#   not where the base put it.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

FIREFOX_DIR=/usr/lib64/firefox
FIREFOX_ID=org.mozilla.firefox

# --- the steps ----------------------------------------------------------------

# The Bazzite defaults bazzite-mx installed beside the RPM belong to no
# package, so the directory goes with them.
remove_firefox_rpm() {
    dnf5 -y remove firefox firefox-langpacks
    rm -rf "$FIREFOX_DIR"
}

# The list bazzite-mx's block_in_bazaar appended for Firefox goes whole, and
# no unconditional list blocks the id afterwards.
allow_firefox_flatpak() {
    if [ "$(bazaar_block_count "$FIREFOX_ID" "$BAZAAR_BLOCKLIST")" != 1 ]; then
        fail_build "$BAZAAR_BLOCKLIST: $FIREFOX_ID not blocked once by the base"
    fi

    if ! python3 - "$FIREFOX_ID" "$BAZAAR_BLOCKLIST" > "$BAZAAR_BLOCKLIST.new" << 'EOF'; then
import sys
app, path = sys.argv[1:]
entry = f"\n  - priority: 0\n    block:\n    - {app}\n"
text = open(path).read()
if text.count(entry) != 1:
    sys.exit(1)
sys.stdout.write(text.replace(entry, ""))
EOF
        fail_build "$BAZAAR_BLOCKLIST: the base's $FIREFOX_ID list not found once"
    fi
    mv -f "$BAZAAR_BLOCKLIST.new" "$BAZAAR_BLOCKLIST"

    if [ "$(bazaar_block_count "$FIREFOX_ID" "$BAZAAR_BLOCKLIST")" != 0 ]; then
        fail_build "$BAZAAR_BLOCKLIST: $FIREFOX_ID still blocked"
    fi
}

# --- main ---------------------------------------------------------------------

remove_firefox_rpm
allow_firefox_flatpak

log "firefox-flatpak: the RPM removed, the Flatpak allowed"
