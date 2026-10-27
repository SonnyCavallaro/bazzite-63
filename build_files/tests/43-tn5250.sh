#!/usr/bin/env bash
# Smoke test of 43-tn5250.sh: the package, its two terminals and the desktop
# entry of xt5250.
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$(realpath "$0")")/lib.sh"

check_terminals() {
    if [ -x /usr/bin/tn5250 ] && [ -x /usr/bin/xt5250 ] \
        && [ -f /usr/share/applications/xt5250.desktop ]; then
        echo "OK: tn5250 and xt5250 in /usr/bin, xt5250.desktop installed"
    else
        echo "FAIL: tn5250, xt5250 or xt5250.desktop missing"
    fi
}

check_pkg tn5250
check_terminals
