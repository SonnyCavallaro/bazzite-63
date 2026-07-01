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
    brew install mise || true
    # CLI tools (non-blocking if a formula is unavailable on this platform)
    brew install powershell || echo "powershell: formula unavailable, skipping"
    brew install sqlcmd     || echo "sqlcmd: formula unavailable, skipping"
    # Runtimes from ~/.config/mise/config.toml (node, python, java, dotnet)
    eval "$(mise activate bash)"
    mise install
    echo "Done. Open a new shell to activate the runtimes (node/python/java/dotnet)."

# Install WinBoat (run Windows apps in a container). Beta; per-user AppImage.
# Requires Docker/Podman + KVM (present in the image) and FreeRDP 3.x.
[group("apps")]
install-winboat:
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Installing WinBoat (beta) AppImage into ~/.local/bin..."
    echo "Requires Docker/Podman + KVM (present) and FreeRDP 3.x."
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
    url=$(curl -fsSL https://api.github.com/repos/TibixDev/winboat/releases/latest \
        | jq -r '.assets[] | select(.name | endswith(".AppImage")) | .browser_download_url' | head -1)
    [ -n "$url" ] || { echo "Could not resolve the WinBoat AppImage URL."; exit 1; }
    curl -fsSL "$url" -o "$HOME/.local/bin/WinBoat.AppImage"
    chmod +x "$HOME/.local/bin/WinBoat.AppImage"
    cat > "$HOME/.local/share/applications/winboat.desktop" <<EOF
    [Desktop Entry]
    Name=WinBoat
    Exec=$HOME/.local/bin/WinBoat.AppImage
    Type=Application
    Categories=Utility;
    Terminal=false
    EOF
    echo "WinBoat installed."

# Install JetBrains Rider (Flatpak). Free for non-commercial use only;
# a commercial licence is required for company work.
[group("apps")]
install-rider:
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Installing JetBrains Rider (Flatpak). Note: commercial licence for work use."
    flatpak install -y --noninteractive flathub com.jetbrains.Rider

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
    unzip -o "{{ ARCHIVE }}" -d "$dest"
    echo "IBM ACS extracted to $dest (launch: java -jar \"$dest/.../acsbundle.jar\")."

# Create a Microsoft 365 web-app (PWA) launcher backed by the Chrome Flatpak.
[group("apps")]
setup-m365-pwa:
    #!/usr/bin/env bash
    set -eo pipefail
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/m365.desktop" <<EOF
    [Desktop Entry]
    Name=Microsoft 365
    Exec=flatpak run com.google.Chrome --app=https://www.office.com
    Type=Application
    Categories=Office;
    Terminal=false
    EOF
    echo "Microsoft 365 (PWA) launcher created."
