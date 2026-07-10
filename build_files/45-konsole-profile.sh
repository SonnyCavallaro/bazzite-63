#!/usr/bin/env bash
# Konsole opens PowerShell: system_files/ ships the profile, the skel konsolerc
# that names it and the hook for older accounts, and the skel profile.ps1
# wired to Homebrew and mise. That profile.ps1 reaches an older account
# through bazzite-mx's copy-paste hook, so the build refuses a base whose hook
# no longer seeds it.
#
# Usage: run by build.sh after 01-system-files.sh; no arguments.
# Writes: nothing; the files come from system_files/.
# Exit status: 0 the base still does its part; the build stops on a `FAIL: …`
#   line otherwise.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

COPY_PASTE_HOOK=/usr/share/ublue-os/user-setup.hooks.d/12-bazzite-mx-copy-paste.sh

if ! grep -qxF '    .config/powershell/profile.ps1' "$COPY_PASTE_HOOK" 2> /dev/null; then
    fail_build "$COPY_PASTE_HOOK no longer seeds .config/powershell/profile.ps1"
fi

log "konsole-profile: PowerShell profile, skel konsolerc and hook in place"
