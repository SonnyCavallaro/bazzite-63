#!/usr/bin/env bash
# Smoke test of 47-segoe-font.sh: the font keys in kdeglobals beside the
# base's own, no Segoe font file in the image, the autostart entry, and the
# per-user installer on a fixture home. Offline, the installer meets a package
# whose font fontconfig does not know and a package it cannot fetch: both
# leave no stamp, so the next login retries. Installing the real font needs
# Microsoft's package and a session; that is proven on a host.
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$(realpath "$0")")/lib.sh"

KDEGLOBALS=/etc/xdg/kdeglobals
INSTALLER=/usr/libexec/bazzite-63-segoe-ui-variable
FONT_10='Segoe UI Variable,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1'
FONT_8='Segoe UI Variable,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1'
# Any font fontconfig knows under another family stands in for the package's.
STAND_IN_FONT=/usr/share/fonts/fira-code/FiraCode-Light.ttf

# Each key read in its group: activeFont under [General] would leave the window
# titles unchanged.
check_kdeglobals() {
    local entry group key value missing=""

    for entry in "General/font=$FONT_10" "General/menuFont=$FONT_10" \
        "General/toolBarFont=$FONT_10" "General/smallestReadableFont=$FONT_8" \
        "WM/activeFont=$FONT_10"; do
        group=${entry%%/*}
        key=${entry#*/}
        key=${key%%=*}
        value=$(kreadconfig6 --file "$KDEGLOBALS" --group "$group" --key "$key" || true)

        if [ "$value" != "${entry#*=}" ]; then
            missing+=" $group/$key"
        fi
    done

    if [ -z "$missing" ] && grep -q '^LookAndFeelPackage=' "$KDEGLOBALS"; then
        echo "OK: $KDEGLOBALS sets Segoe UI Variable and keeps the base's keys"
    else
        echo "FAIL: $KDEGLOBALS:${missing:- lost the look-and-feel key of the base}"
    fi
}

# The licence forbids redistribution: no copy of the font in /usr or /etc.
check_no_font_baked() {
    local baked

    baked=$(find /usr /etc -iname 'SegoeUI*.ttf' 2> /dev/null || true)

    if [ -z "$baked" ]; then
        echo "OK: no Segoe UI font file in the image"
    else
        echo "FAIL: Segoe UI baked: $(on_one_line none <<< "$baked")"
    fi
}

# run_installer <home> <url>: the installer as a login would run it.
run_installer() {
    env -u XDG_CONFIG_HOME -u XDG_DATA_HOME HOME=$1 SEGOE_URL=$2 "$INSTALLER" 2>&1
}

check_installer_retries() {
    local fixture fonts output home stamp_left=""

    fixture=$(mktemp -d)
    fonts=$fixture/home/.local/share/fonts/segoe-ui-variable
    mkdir -p "$fixture/package/fonts"
    cp "$STAND_IN_FONT" "$fixture/package/fonts/SegoeUI-VF.ttf"
    echo licence > "$fixture/package/EULA.txt"
    (cd "$fixture/package" && python3 -m zipfile -c ../segoe.zip fonts EULA.txt)

    output=$(run_installer "$fixture/home" "file://$fixture/segoe.zip")
    output+=$'\n'$(run_installer "$fixture/away" "file://$fixture/missing.zip")

    for home in home away; do
        if [ -e "$fixture/$home/.config/bazzite-63-segoe-ui-variable.done" ]; then
            stamp_left+=" $home"
        fi
    done

    if [ -z "$stamp_left" ] \
        && cmp -s "$STAND_IN_FONT" "$fonts/SegoeUI-VF.ttf" \
        && [ -f "$fonts/EULA.txt" ] \
        && grep -q 'fontconfig does not see the installed font' <<< "$output" \
        && grep -q 'cannot download' <<< "$output"; then
        echo "OK: installer unpacks the package, and leaves no stamp when the font is not usable"
    else
        echo "FAIL: installer retry paths: stamp in${stamp_left:- none};" \
            "$(on_one_line 'no output' <<< "$output")"
    fi

    rm -rf "$fixture"
}

check_kdeglobals
check_no_font_baked
check_desktop_file /etc/xdg/autostart/bazzite-63-segoe-ui-variable.desktop
check_installer_retries
