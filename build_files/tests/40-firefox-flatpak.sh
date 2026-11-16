#!/usr/bin/env bash
# Smoke test of 40-firefox-flatpak.sh: no Firefox RPM nor its directory, and
# the Flatpak no longer blocked in Bazaar.
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$(realpath "$0")")/lib.sh"

check_rpm_gone() {
    local installed

    installed=$(rpm -q firefox firefox-langpacks 2>&1 | grep -v 'is not installed' || true)

    if [ -z "$installed" ] && [ ! -e /usr/lib64/firefox ]; then
        echo "OK: no Firefox RPM and no /usr/lib64/firefox"
    else
        echo "FAIL: Firefox RPM left: ${installed:-/usr/lib64/firefox}"
    fi
}

# No list of the parsed blocklist, conditional or not, names Firefox; the
# base's Steam entry stays.
check_flatpak_allowed() {
    local count

    count=$(
        python3 - "$BAZAAR_BLOCKLIST" 2>&1 << 'EOF' || true
import sys, yaml
with open(sys.argv[1]) as f:
    lists = yaml.safe_load(f)["blocklists"]
print(sum((b.get("block") or []).count("org.mozilla.firefox") for b in lists))
EOF
    )

    if [ "$count" = 0 ]; then
        echo "OK: $BAZAAR_BLOCKLIST no longer blocks org.mozilla.firefox"
    else
        echo "FAIL: $BAZAAR_BLOCKLIST: Firefox counted $(on_one_line 'nothing' <<< "$count")"
    fi

    check_bazaar_block com.valvesoftware.Steam
}

check_rpm_gone
check_flatpak_allowed
