#!/usr/bin/env bash
# Smoke test of 40-firefox-flatpak.sh: no Firefox RPM nor its directory, and
# the Flatpak no longer denied.
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

FLATPAK_BLOCKLIST=/usr/share/ublue-os/flatpak-blocklist

check_rpm_gone() {
    local installed

    installed=$(rpm -q firefox firefox-langpacks 2>&1 | grep -v 'is not installed' || true)

    if [ -z "$installed" ] && [ ! -e /usr/lib64/firefox ]; then
        echo "OK: no Firefox RPM and no /usr/lib64/firefox"
    else
        echo "FAIL: Firefox RPM left: ${installed:-/usr/lib64/firefox}"
    fi
}

check_flatpak_allowed() {
    if [ -f "$FLATPAK_BLOCKLIST" ] \
        && ! grep -q 'org\.mozilla\.firefox' "$FLATPAK_BLOCKLIST"; then
        echo "OK: $FLATPAK_BLOCKLIST no longer denies org.mozilla.firefox"
    else
        echo "FAIL: $FLATPAK_BLOCKLIST missing or still naming org.mozilla.firefox"
    fi
}

check_rpm_gone
check_flatpak_allowed
