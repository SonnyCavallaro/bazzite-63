# vim: set ft=make :
#
# 96-bazzite-63.just — bazzite-63 custom ujust recipes.
#
# Lives alongside upstream's 95-bazzite-mx.just, which is kept verbatim so
# bazzite-mx changes merge at zero cost. `ujust` imports share one namespace,
# so helpers defined there (e.g. `_pkg_layered`) are usable here too.
#
# Convention:
#  - Public recipes grouped via `[group("...")]` for `just --list` UX.
#  - Per-user dev tooling (runtimes, CLI tools) is installed via `mise` and
#    `brew` into $HOME, never layered into the read-only image — see `setup-dev`.
#    GUI apps ship as Flatpaks (default-install), so they update without a
#    rebuild/reboot.

# Set up the per-user dev environment: mise (runtime manager) + CLI tools via
# brew, then install the runtimes pinned in ~/.config/mise/config.toml. Nothing
# touches the read-only image; everything lives in $HOME and auto-updates.
[group("dev")]
setup-dev:
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Setting up the dev environment (per-user: brew + mise)..."
    command -v brew >/dev/null || { echo "brew not found in PATH (Bazzite ships it; try a new shell)."; exit 1; }
    # mise is REQUIRED (everything below depends on it). Homebrew's cask-API
    # cache can break installs with "undefined method 'first' for nil":
    # clear it and retry once before giving up.
    if ! brew install mise; then
        echo "brew install mise failed — clearing brew's API cache and retrying..."
        brew_cache="$(brew --cache 2>/dev/null)"
        [ -n "$brew_cache" ] && rm -rf "$brew_cache/api" || true
        brew update >/dev/null 2>&1 || true
        brew install mise
    fi
    MISE="$(command -v mise || echo /home/linuxbrew/.linuxbrew/bin/mise)"
    [ -x "$MISE" ] || { echo "mise is still missing after install — aborting."; exit 1; }
    # CLI tools (non-blocking: the dev environment works without them)
    brew install powershell || echo "powershell: install failed or formula unavailable, skipping"
    brew install sqlcmd     || echo "sqlcmd: install failed or formula unavailable, skipping"
    # Accounts that predate the image get no /etc/skel: seed the per-user dev
    # config here as well (the 23-…-dev-config first-login hook covers the
    # login path), so a single run yields the complete setup.
    if [ ! -e "$HOME/.config/mise/config.toml" ] && [ -e /etc/skel/.config/mise/config.toml ]; then
        mkdir -p "$HOME/.config/mise"
        cp /etc/skel/.config/mise/config.toml "$HOME/.config/mise/"
    fi
    if [ ! -e "$HOME/.config/powershell/profile.ps1" ] && [ -e /etc/skel/.config/powershell/profile.ps1 ]; then
        mkdir -p "$HOME/.config/powershell"
        cp /etc/skel/.config/powershell/profile.ps1 "$HOME/.config/powershell/"
    fi
    # Runtimes from ~/.config/mise/config.toml (node, python, java, dotnet)
    eval "$("$MISE" activate bash)"
    "$MISE" install
    echo "Done. Open a new shell to activate the runtimes (node/python/java/dotnet)."

# Install WinBoat (run Windows apps in a container; beta) — phase 1 of the
# vendored winboat-office-kit: prerequisites check + per-user AppImage.
# When the Windows VM does not exist yet the kit prints the manual wizard
# steps and stops (exit 2) — tolerated here so the one-shot umbrella
# carries on; after the wizard, `ujust setup-winboat-office` completes the
# Office provisioning.
[group("apps")]
install-winboat:
    #!/usr/bin/env bash
    set -eo pipefail
    /usr/share/bazzite-63/winboat-office-kit/01-install-winboat.sh || {
        rc=$?
        [ "$rc" -eq 2 ] || exit "$rc"
    }

# Provision WinBoat + Office 365 + Teams end to end (vendored
# winboat-office-kit): WinBoat AppImage, winget installs inside the Windows
# VM, taskbar launchers with the original icons. Idempotent; stops with
# instructions when a manual step is due (WinBoat first-run wizard;
# Microsoft 365 login stays manual at first app start). Needs an active
# desktop session (opens temporary RemoteApp windows).
[group("apps")]
setup-winboat-office:
    #!/usr/bin/env bash
    set -eo pipefail
    exec /usr/share/bazzite-63/winboat-office-kit/setup-all.sh

# Install SAP GUI for Java from an installer you provide (needs an SAP S-user).
[group("apps")]
install-sap-gui INSTALLER="":
    #!/usr/bin/env bash
    set -eo pipefail
    if [ -z "{{ INSTALLER }}" ]; then
        echo "Usage: ujust install-sap-gui /path/to/PlatinGUI-Linux-...jar"
        echo "Download SAP GUI for Java from the SAP Software Download Center."
        exit 1
    fi
    command -v java >/dev/null || { echo "java not found — run 'ujust setup-dev' first, then open a new shell."; exit 1; }
    java -jar "{{ INSTALLER }}"

# Install IBM ACS (IBM i Access Client Solutions) from an archive you provide.
[group("apps")]
install-ibm-acs ARCHIVE="":
    #!/usr/bin/env bash
    set -eo pipefail
    if [ -z "{{ ARCHIVE }}" ]; then
        echo "Usage: ujust install-ibm-acs /path/to/IBMiAccess_v1r1.zip"
        echo "Download from https://www.ibm.com/support/pages/ibm-i-access-client-solutions"
        exit 1
    fi
    dest="$HOME/.local/share/ibm-acs"
    mkdir -p "$dest"
    if command -v unzip >/dev/null; then
        unzip -o "{{ ARCHIVE }}" -d "$dest"
    else
        bsdtar -xf "{{ ARCHIVE }}" -C "$dest"
    fi
    echo "IBM ACS extracted to $dest (launch: java -jar \"$dest/.../acsbundle.jar\")."

# Create a Microsoft 365 web-app (PWA) launcher backed by the system Chrome.
[group("apps")]
setup-m365-pwa:
    #!/usr/bin/env bash
    set -eo pipefail
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/m365.desktop" <<EOF
    [Desktop Entry]
    Name=Microsoft 365
    Exec=/usr/bin/google-chrome-stable --app=https://www.office.com
    Type=Application
    Categories=Office;
    Terminal=false
    EOF
    echo "Microsoft 365 (PWA) launcher created."

# Install/refresh the default GUI Flatpak set (our 7 apps + Bazzite's own
# list entries). ON DEMAND by design — nothing installs silently at boot.
# Idempotent: re-runs reconcile and update the set.
[group("apps")]
install-default-flatpaks:
    #!/usr/bin/env bash
    set -eo pipefail
    sudo /usr/libexec/bazzite63-flatpak-manager

# One-shot setup: everything installable without user-provided files
# (default Flatpak set, dev toolchain, WinBoat, JetBrains Toolbox, M365 launcher),
# then the health check. SAP GUI and IBM ACS stay manual: they need
# licensed files you provide (`ujust install-sap-gui <jar>`,
# `ujust install-ibm-acs <zip>`).
# Idempotent: safe to re-run; uninstall what you don't need afterwards.
[group("dev")]
# install-jetbrains-toolbox is the bazzite-mx override (Bluefin/Aurora
# non-brew method, 96-bazzite-mx-overrides.just): one shared namespace,
# so the dependency resolves across justfiles.
bazzite-63-setup: install-default-flatpaks setup-dev install-winboat install-jetbrains-toolbox setup-m365-pwa
    #!/usr/bin/env bash
    echo
    echo "Setup complete. Left out (need files you provide):"
    echo "  ujust install-sap-gui /path/to/PlatinGUI-Linux-...jar"
    echo "  ujust install-ibm-acs /path/to/IBMiAccess_v1r1.zip"
    echo
    ujust b63-status || echo "(setup done — review the KO lines above)"

# One-glance health check: booted image, default apps,
# default browser and per-user dev tooling. Read-only, safe to run anytime.
[group("system")]
b63-status:
    #!/usr/bin/env bash
    set -o pipefail
    fail=0
    ok() { printf '  \033[1;32mOK\033[0m  %s\n' "$1"; }
    ko() { printf '  \033[1;31mKO\033[0m  %s\n' "$1"; fail=1; }

    echo "== bazzite-63 status =="

    ref=$(rpm-ostree status --json 2>/dev/null | jq -r '.deployments[] | select(.booted==true) | ."container-image-reference" // ""')
    ver=$(rpm-ostree status --json 2>/dev/null | jq -r '.deployments[] | select(.booted==true) | .version // ""')
    if [[ "$ref" == *"bazzite-63"* ]]; then
        ok "booted image: bazzite-63 (version $ver)"
    else
        ko "booted image: ${ref:-unknown} (expected bazzite-63 — did the bootc switch happen?)"
    fi

    # The list mixes apps and runtimes (some pinned as `ref//branch`):
    # compare against ALL installed refs, branch suffix stripped.
    installed=$(flatpak list --columns=application 2>/dev/null)
    missing=0
    while read -r app; do
        grep -qxF "${app%%//*}" <<< "$installed" || { ko "flatpak missing: $app — fix: ujust install-default-flatpaks"; missing=1; }
    done < <(grep -vE '^\s*(#|$)' /usr/share/ublue-os/bazzite/flatpak/install)
    [[ $missing -eq 0 ]] && ok "all Flatpaks from the default-install list are installed"

    # xdg-settings resolves the per-user default (KDE kdeglobals chain); fall
    # back to the XDG mime chain, which also sees /etc/xdg/mimeapps.list.
    browser=$(xdg-settings get default-web-browser 2>/dev/null || true)
    [[ -n "$browser" ]] || browser=$(xdg-mime query default x-scheme-handler/http 2>/dev/null || echo n/a)
    if [[ "$browser" == "google-chrome.desktop" ]] \
       || [[ "$(xdg-mime query default x-scheme-handler/http 2>/dev/null)" == "google-chrome.desktop" ]]; then
        ok "default browser: Chrome (system RPM)"
    else
        # xdg-settings SET is broken on Bazzite (qtpaths missing), so the hint
        # goes through kwriteconfig6 instead. Chrome itself is baked in the
        # image: a wrong default is a per-user config issue, never a missing app.
        ko "default browser: $browser — fix: kwriteconfig6 --file kdeglobals --group General --key BrowserApplication google-chrome.desktop"
    fi

    if command -v mise >/dev/null 2>&1 || [ -x /home/linuxbrew/.linuxbrew/bin/mise ]; then
        # mise alone is not enough: without the pinned-runtimes config
        # `mise install` is a silent no-op (node/python/java/dotnet missing).
        if [ -e "$HOME/.config/mise/config.toml" ]; then
            ok "dev tooling: mise present, runtimes config in place"
        else
            ko "mise present but ~/.config/mise/config.toml missing — fix: ujust setup-dev"
        fi
    else
        ko "dev tooling not initialised — run: ujust setup-dev"
    fi
    if [ -e "$HOME/.config/powershell/profile.ps1" ]; then
        ok "pwsh profile: brew PATH + mise activation wired"
    else
        ko "pwsh profile missing (~/.config/powershell/profile.ps1) — fix: ujust setup-dev"
    fi

    echo
    if [[ $fail -eq 0 ]]; then
        echo "All good."
    else
        echo "Something needs attention (see KO lines above)."
        exit 1
    fi
