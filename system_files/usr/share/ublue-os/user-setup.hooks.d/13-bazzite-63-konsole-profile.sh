#!/usr/bin/env bash
# Konsole opens PowerShell for an account that predates the image too
# (/etc/skel reaches new homes only): the profile is copied when the home has
# none, and DefaultProfile is written only when konsolerc names none, so a
# profile the user chose stays. Every graphical session, from
# ublue-user-setup.service, so a home created later is reached at its first
# login.
#
# Usage: 13-bazzite-63-konsole-profile.sh   (as the user; ublue-user-setup runs it)
#   The smoke test points HOME at a fixture home.
# Output: `bazzite-63-konsole-profile: …` lines, the last one naming what the
#   run left in place (tests/45-konsole-profile.sh reads it).
# Exit status: 0 done; 1 a write failed, the file named in a
#   `bazzite-63-konsole-profile: ERROR: …` line on stderr.
set -euo pipefail

SKEL_PROFILE=/etc/skel/.local/share/konsole/Powershell.profile
PROFILE=$HOME/.local/share/konsole/Powershell.profile
KONSOLERC=$HOME/.config/konsolerc

# --- the steps ----------------------------------------------------------------

fail() {
    echo "bazzite-63-konsole-profile: ERROR: $*; retried at the next login" >&2
    exit 1
}

# Written beside and renamed, so a copy cut short by a full home leaves no
# empty profile for the next login to count as present.
seed_profile() {
    if [ -e "$PROFILE" ]; then
        return 0
    fi

    if ! mkdir -p "$(dirname "$PROFILE")" 2> /dev/null \
        || ! cp "$SKEL_PROFILE" "$PROFILE.new" 2> /dev/null \
        || ! mv -f "$PROFILE.new" "$PROFILE" 2> /dev/null; then
        rm -f "$PROFILE.new"
        fail "could not seed $PROFILE"
    fi

    echo "bazzite-63-konsole-profile: seeded $PROFILE from /etc/skel"
}

set_default_profile() {
    if grep -qs '^DefaultProfile=' "$KONSOLERC"; then
        return 0
    fi

    if ! mkdir -p "$(dirname "$KONSOLERC")" 2> /dev/null \
        || ! kwriteconfig6 --file "$KONSOLERC" --group 'Desktop Entry' \
            --key DefaultProfile Powershell.profile 2> /dev/null; then
        fail "could not write DefaultProfile to $KONSOLERC"
    fi

    echo "bazzite-63-konsole-profile: DefaultProfile=Powershell.profile in $KONSOLERC"
}

# --- main ---------------------------------------------------------------------

seed_profile
set_default_profile

echo "bazzite-63-konsole-profile: Konsole defaults to" \
    "$(sed -n 's/^DefaultProfile=//p' "$KONSOLERC")"
