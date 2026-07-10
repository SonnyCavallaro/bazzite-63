#!/usr/bin/env bash
# Smoke test of 45-konsole-profile.sh and the files it guards: the skel
# konsolerc names the PowerShell profile, profile.ps1 wires Homebrew, mise and
# the Ctrl+C/V handlers, and the hook seeds an older home whose konsolerc names
# no profile, keeps a profile and a default the user chose and fails loudly
# when it cannot write.
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$(realpath "$0")")/lib.sh"

HOOK=/usr/share/ublue-os/user-setup.hooks.d/13-bazzite-63-konsole-profile.sh
SKEL_PROFILE=/etc/skel/.local/share/konsole/Powershell.profile
POWERSHELL_PROFILE=/etc/skel/.config/powershell/profile.ps1

# Konsole reads DefaultProfile in [Desktop Entry] alone.
default_profile() {
    kreadconfig6 --file "$1" --group 'Desktop Entry' --key DefaultProfile || true
}

check_skel_files() {
    if [ "$(default_profile /etc/skel/.config/konsolerc)" = Powershell.profile ] \
        && grep -q 'exec bash -l' "$SKEL_PROFILE" \
        && grep -q '^Command=.*p=/home/linuxbrew/.linuxbrew/bin/pwsh;' "$SKEL_PROFILE" \
        && grep -qF "\$env:PATH + ':/home/linuxbrew/.linuxbrew/bin:" "$POWERSHELL_PROFILE" \
        && grep -q 'mise activate pwsh' "$POWERSHELL_PROFILE" \
        && grep -qF 'Remove-Item Env:DOTNET_ROOT' "$POWERSHELL_PROFILE" \
        && grep -q 'CopyOrCancelLine' "$POWERSHELL_PROFILE"; then
        echo "OK: skel konsolerc names Powershell.profile, profile.ps1 wires brew and mise"
    else
        echo "FAIL: skel konsolerc, Powershell.profile or profile.ps1 incomplete"
    fi
}

run_hook() {
    HOME=$1 bash "$HOOK" 2>&1
}

check_hook_seeds_an_older_home() {
    local home=$1
    local output

    mkdir -p "$home/.config"
    printf '[MainWindow]\nHeight=1\n' > "$home/.config/konsolerc"

    if output=$(run_hook "$home") \
        && cmp -s "$SKEL_PROFILE" "$home/.local/share/konsole/Powershell.profile" \
        && [ "$(default_profile "$home/.config/konsolerc")" = Powershell.profile ] \
        && grep -qx 'Height=1' "$home/.config/konsolerc" \
        && grep -q 'Konsole defaults to Powershell.profile$' <<< "$output"; then
        echo "OK: hook seeds the profile and makes it the default on an older home"
    else
        echo "FAIL: hook on an older home: $(on_one_line 'no output' <<< "$output")"
    fi
}

check_hook_keeps_the_user_choice() {
    local home=$1
    local output

    mkdir -p "$home/.config" "$home/.local/share/konsole"
    printf '[Desktop Entry]\nDefaultProfile=Mine.profile\n' > "$home/.config/konsolerc"
    echo '[General]' > "$home/.local/share/konsole/Powershell.profile"

    if output=$(run_hook "$home") \
        && grep -qx 'DefaultProfile=Mine.profile' "$home/.config/konsolerc" \
        && [ "$(cat "$home/.local/share/konsole/Powershell.profile")" = '[General]' ] \
        && grep -q 'Konsole defaults to Mine.profile$' <<< "$output"; then
        echo "OK: hook leaves the user's own Powershell.profile and default profile"
    else
        echo "FAIL: hook over a chosen profile: $(on_one_line 'no output' <<< "$output")"
    fi
}

# Known-bad: a regular file where the directories go refuses mkdir for root as
# well, and the build runs the tests as root.
check_hook_fails_when_it_cannot_write() {
    local home=$1
    local output

    mkdir -p "$home"
    touch "$home/.local"

    if output=$(run_hook "$home"); then
        echo "FAIL: hook exited 0 with its target directory blocked"
    elif grep -q 'ERROR: could not seed' <<< "$output"; then
        echo "OK: hook reports and fails when the copy fails"
    else
        echo "FAIL: hook failed without naming the file: $(on_one_line 'no output' <<< "$output")"
    fi
}

check_konsole_hook() {
    local fixture

    fixture=$(mktemp -d)
    check_hook_seeds_an_older_home "$fixture/older"
    check_hook_keeps_the_user_choice "$fixture/chosen"
    check_hook_fails_when_it_cannot_write "$fixture/locked"
    rm -rf "$fixture"
}

check_skel_files
check_konsole_hook
