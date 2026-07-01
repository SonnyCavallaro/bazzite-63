#!/usr/bin/bash
# bazzite-63 user hook: set Google Chrome as the default browser on first login.
# xdg-settings is per-user, so this runs once via the user-setup framework. The
# `|| true` keeps the hook benign if the Chrome Flatpak isn't installed yet.

set -euo pipefail
# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

version-script default-browser user 1 || exit 0

xdg-settings set default-web-browser com.google.Chrome.desktop || true
