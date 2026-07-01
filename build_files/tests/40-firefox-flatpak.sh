#!/usr/bin/env bash
# Smoke test of 40-firefox-flatpak.sh: no Firefox RPM nor its directory, the
# Flatpak no longer denied, verify-host reporting the Flatpak as the browser
# and still parsing (it has no self-test), and migrate copying no profile into
# an RPM. migrate's self-test, run by tests/12-host-helpers.sh, proves the
# shortened step 8 still runs.
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

FLATPAK_BLOCKLIST=/usr/share/ublue-os/flatpak-blocklist
VERIFY_HOST=/usr/libexec/bazzite-mx-verify-host
MIGRATE=/usr/libexec/bazzite-mx-migrate

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

check_helpers() {
    if bash -n "$VERIFY_HOST" 2> /dev/null \
        && grep -qF "the Firefox Flatpak is installed (the image's browser)" "$VERIFY_HOST" \
        && ! grep -q 'the RPM is the image' "$VERIFY_HOST" \
        && ! grep -q mozilla "$MIGRATE"; then
        echo "OK: verify-host reports the Flatpak as the browser, migrate copies no profile"
    else
        echo "FAIL: verify-host does not parse, or a helper still treats the RPM as the browser"
    fi
}

check_rpm_gone
check_flatpak_allowed
check_helpers
