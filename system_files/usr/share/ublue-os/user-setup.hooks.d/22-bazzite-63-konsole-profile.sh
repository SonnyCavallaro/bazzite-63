#!/usr/bin/bash
# user-setup hook: Konsole PowerShell default profile for accounts that
# predate the image (/etc/skel only reaches accounts created afterwards —
# the primary switch flow starts from stock Bazzite, so the main account
# always predates it). Non-destructive: seeds the profile if absent and
# sets DefaultProfile only when the user has not picked one.
#
# Versioned: bumping the number below re-runs the hook on next login.

set -euo pipefail

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

version-script bazzite-63-konsole user 1 || exit 0

# Guard the skel source: a missing file would abort the hook (set -e)
# after libsetup.sh has already written state → no retry, ever.
if [ ! -e "$HOME/.local/share/konsole/Powershell.profile" ] && \
   [ -e /etc/skel/.local/share/konsole/Powershell.profile ]; then
    mkdir -p "$HOME/.local/share/konsole"
    cp -f /etc/skel/.local/share/konsole/Powershell.profile "$HOME/.local/share/konsole/"
fi

# Respect an existing user choice: set the default only when konsolerc
# has no DefaultProfile yet.
if ! grep -qs '^DefaultProfile=' "$HOME/.config/konsolerc"; then
    mkdir -p "$HOME/.config"
    kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile Powershell.profile || true
fi

echo "user bazzite-63-konsole hook complete."
