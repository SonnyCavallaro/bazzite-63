#!/usr/bin/env bash
# Smoke test of 42-flatpak-apps.sh: each app once in Bazzite's default list,
# no VulkanLayer runtime and no Firefox in it, the apps alone in their own
# file; the installer's self-test and the recipe's help.
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$(realpath "$0")")/lib.sh"

INSTALL_LIST=/usr/share/ublue-os/bazzite/flatpak/install
IMAGE_APPS=/usr/share/bazzite-63/flatpak-apps
APPS="org.mozilla.thunderbird me.proton.Pass io.dbeaver.DBeaverCommunity org.remmina.Remmina"
APPS+=" com.parsecgaming.parsec com.discordapp.Discord"

check_install_list() {
    local app listed wrong=""

    for app in $APPS; do
        if [ "$(grep -cxF "$app" "$INSTALL_LIST" || true)" != 1 ]; then
            wrong+=" $app"
        fi
    done

    if grep -q -e VulkanLayer -e org.mozilla.firefox "$INSTALL_LIST"; then
        wrong+=" a VulkanLayer runtime or Firefox"
    fi

    # One of Bazzite's own apps, which the list keeps.
    if [ "$(grep -cx com.github.tchx84.Flatseal "$INSTALL_LIST" || true)" != 1 ]; then
        wrong+=" Bazzite's entries lost"
    fi

    if [ -z "$wrong" ]; then
        echo "OK: $INSTALL_LIST keeps Bazzite's apps, adds each app once, no runtime or Firefox"
    else
        echo "FAIL: $INSTALL_LIST:$wrong"
    fi

    listed=$(paste -sd ' ' "$IMAGE_APPS" 2> /dev/null || true)

    if [ "$listed" = "$APPS" ]; then
        echo "OK: $IMAGE_APPS lists the image's apps"
    else
        echo "FAIL: $IMAGE_APPS: ${listed:-missing}"
    fi
}

check_install_list
check_self_test flatpak-manager /usr/libexec/bazzite-63-flatpak-manager
check_recipe_help /usr/share/ublue-os/just/96-bazzite-63.just install-default-flatpaks
