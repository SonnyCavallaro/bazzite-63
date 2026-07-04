#!/usr/bin/bash
# user-setup hook: per-user dev config for accounts that predate the image
# (/etc/skel only reaches accounts created afterwards — the primary switch
# flow starts from stock Bazzite, so the main account always predates it).
# Non-destructive: seeds each file only when the user has none.
# `ujust setup-dev` seeds the same files, so either path yields a full setup.
#
# Versioned: bumping the number below re-runs the hook on next login.

set -euo pipefail

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

version-script bazzite-63-dev-config user 1 || exit 0

# Guard each skel source: a missing file would abort the hook (set -e)
# after libsetup.sh has already written state → no retry, ever.

# mise pinned-runtimes config (consumed by `ujust setup-dev` → mise install)
if [ ! -e "$HOME/.config/mise/config.toml" ] && \
   [ -e /etc/skel/.config/mise/config.toml ]; then
    mkdir -p "$HOME/.config/mise"
    cp /etc/skel/.config/mise/config.toml "$HOME/.config/mise/"
fi

# PowerShell profile: brew on PATH + mise activation (pwsh reads its own
# per-user profile, never /etc/profile.d)
if [ ! -e "$HOME/.config/powershell/profile.ps1" ] && \
   [ -e /etc/skel/.config/powershell/profile.ps1 ]; then
    mkdir -p "$HOME/.config/powershell"
    cp /etc/skel/.config/powershell/profile.ps1 "$HOME/.config/powershell/"
fi

echo "user bazzite-63-dev-config hook complete."
