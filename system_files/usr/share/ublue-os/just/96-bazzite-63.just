# vim: set ft=make :
# The image's own recipes, imported after bazzite-mx's by 70-justfile.sh,
# which refuses a name defined twice.

# Install or update the default Flatpak set: Bazzite's list and this image's apps.
[group("apps")]
install-default-flatpaks ACTION="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    OPTION="{{ ACTION }}"
    HELPER=/usr/libexec/bazzite-63-flatpak-manager

    if [ "$OPTION" == "help" ]; then
      echo "Usage: ujust install-default-flatpaks"
      echo "Installs from Flathub, or updates, every Flatpak of Bazzite's default list,"
      echo "Bazzite's apps first, with this image's after them, one ref at a time. Nothing"
      echo "installs at boot; run it again to retry a ref that failed. Remove what you do"
      echo "not want afterwards."
      exit 0
    fi

    if [[ $(id -u) -eq 0 ]]; then
      echo "Please do not run this command as root"
      exit 1
    fi

    if [ "$OPTION" != "" ]; then
      echo "Unknown option: $OPTION (ujust install-default-flatpaks help)"
      exit 1
    fi

    sudo "$HELPER" install

# Set up this user's development environment: mise runtimes, pwsh and sqlcmd. Options: status | install
[group("development")]
setup-dev ACTION="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    OPTION="{{ ACTION }}"
    MISE_SKEL=/etc/skel/.config/mise/config.toml
    MISE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"
    PWSH_SKEL=/etc/skel/.config/powershell/profile.ps1
    PWSH_PROFILE="${XDG_CONFIG_HOME:-$HOME/.config}/powershell/profile.ps1"
    MX_PROFILE_SUM="${MX_PROFILE_SUM:-/usr/share/bazzite-63/bazzite-mx-profile.sha256}"

    if [ "$OPTION" == "help" ]; then
      echo "Usage: ujust setup-dev <option>"
      echo "  status   What mise has configured and installed, and whether pwsh is there"
      echo "  install  Seed $MISE_CONFIG and $PWSH_PROFILE from /etc/skel when you have"
      echo "           none, replacing bazzite-mx's untouched profile.ps1, install pwsh and"
      echo "           sqlcmd from Homebrew, then 'mise install'"
      echo "Without an option a menu asks, status first."
      echo "The runtimes go under ~/.local/share/mise/installs, per user, except dotnet: mise puts"
      echo "every SDK in ~/.local/share/mise/dotnet-root, or in \$DOTNET_ROOT when you export one"
      echo "(next to a hand-installed SDK there); Homebrew's tools under /home/linuxbrew. A"
      echo "project's own mise.toml overrides the global config. Not for root."
      exit 0
    fi

    if [[ $(id -u) -eq 0 ]]; then
      echo "Please do not run this command as root"
      exit 1
    fi

    # seed <skel> <target>: written beside and renamed, so a copy cut short
    # leaves no empty file the next run takes as seeded.
    seed() {
      if [ -f "$2" ]; then
        return 0
      fi

      if ! mkdir -p "$(dirname "$2")" 2> /dev/null \
        || ! cp "$1" "$2.new" 2> /dev/null \
        || ! mv -f "$2.new" "$2" 2> /dev/null; then
        rm -f "$2.new"
        echo "ERROR: cannot seed $2 from $1" >&2
        return 1
      fi

      echo "seeded $2 from $1"
    }

    if [ "$OPTION" == "" ]; then
      OPTION=$(Choose "Show status" "Install the default runtimes and tools")
    fi

    case "${OPTION,,}" in
      *status*)
        if [ -f "$MISE_CONFIG" ]; then
          echo "config: $MISE_CONFIG"
        else
          echo "config: none yet (ujust setup-dev install seeds it from $MISE_SKEL)"
        fi

        # The one Konsole and setup-b63 run, not any pwsh on PATH.
        if [ -x /home/linuxbrew/.linuxbrew/bin/pwsh ]; then
          echo "pwsh: /home/linuxbrew/.linuxbrew/bin/pwsh"
        else
          echo "pwsh: none yet (ujust setup-dev install)"
        fi

        mise ls
        ;;
      *install*)
        # bazzite-mx's profile.ps1, untouched, has no Homebrew or mise.
        PROFILE_SUM=$(sha256sum "$PWSH_PROFILE" 2> /dev/null)
        if [ "${PROFILE_SUM%% *}" == "$(cat "$MX_PROFILE_SUM" 2> /dev/null)" ]; then
          rm -f "$PWSH_PROFILE"
        fi

        if ! seed "$MISE_SKEL" "$MISE_CONFIG" || ! seed "$PWSH_SKEL" "$PWSH_PROFILE"; then
          exit 1
        fi

        # A shell that is not interactive misses /etc/profile.d/brew.sh's PATH.
        if ! command -v brew > /dev/null && [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
          eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        fi

        # The command-line tools are extras: a formula that fails leaves the
        # runtimes to install.
        for formula in powershell sqlcmd; do
          if ! brew install "$formula"; then
            echo "${red}brew install $formula failed${normal}: the runtimes still install"
          fi
        done

        # Homebrew's pwsh launcher exports its dotnet as DOTNET_ROOT, where mise would install.
        if [ "${DOTNET_ROOT:-}" == /home/linuxbrew/.linuxbrew/opt/dotnet/libexec ]; then
          unset DOTNET_ROOT
        fi

        if ! mise install; then
          exit 1
        fi

        mise ls
        echo "${green}Done.${normal} Open a new terminal: Konsole starts pwsh," \
          "with mise's runtimes."
        ;;
      "")
        exit 0
        ;;
      *)
        echo "Unknown option: $OPTION (ujust setup-dev help)"
        exit 1
        ;;
    esac

# Set up this user's half of the host, after ujust migrate. Options: status | plan | apply
[group("system")]
setup-b63 ACTION="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    OPTION="{{ ACTION }}"
    HELPER=/usr/libexec/bazzite-63-setup

    if [ "$OPTION" == "help" ]; then
      echo "Usage: ujust setup-b63 <option>"
      echo "  status  One OK/FAIL/INFO line per check of your setup, each FAIL naming its fix"
      echo "  plan    Read-only: the steps apply would run for you"
      echo "  apply   Run them, asking before each step"
      echo "Without an option a menu asks, status first. plan and apply need the host on"
      echo "bazzite-63's signed origin: ujust migrate first; ujust verify-host checks the system."
      echo "Not for root."
      exit 0
    fi

    if [[ $(id -u) -eq 0 ]]; then
      echo "Please do not run this command as root"
      exit 1
    fi

    if [ "$OPTION" == "" ]; then
      OPTION=$(Choose "Show status" "Plan the setup" "Apply the setup")
    fi

    case "${OPTION,,}" in
      *status*)
        "$HELPER" status
        ;;
      *plan*)
        "$HELPER" plan
        ;;
      *apply*)
        "$HELPER" apply
        ;;
      "")
        exit 0
        ;;
      *)
        echo "Unknown option: $OPTION (ujust setup-b63 help)"
        exit 1
        ;;
    esac

# Install SAP GUI for Java from the installer you downloaded (needs an SAP S-user).
[group("apps")]
[no-cd]
install-sap-gui INSTALLER="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    INSTALLER="{{ INSTALLER }}"

    if [ "$INSTALLER" == "" ] || [ "$INSTALLER" == "help" ]; then
      echo "Usage: ujust install-sap-gui <PlatinGUI-Linux-….jar>"
      echo "Runs the SAP GUI for Java installer from the SAP Software Download Center with"
      echo "the Java of ujust setup-dev install (Temurin 21)."
      exit 0
    fi

    if ! command -v java > /dev/null; then
      echo "No java on PATH: ujust setup-dev install, then a new terminal"
      exit 1
    fi

    java -jar "$INSTALLER"

# Unpack IBM i Access Client Solutions from the archive you downloaded.
[group("apps")]
[no-cd]
install-ibm-acs ARCHIVE="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    ARCHIVE="{{ ARCHIVE }}"
    DEST="${XDG_DATA_HOME:-$HOME/.local/share}/ibm-acs"

    if [ "$ARCHIVE" == "" ] || [ "$ARCHIVE" == "help" ]; then
      echo "Usage: ujust install-ibm-acs <IBMiAccess_v1r1.zip>"
      echo "Unpacks the archive from"
      echo "https://www.ibm.com/support/pages/ibm-i-access-client-solutions"
      echo "into $DEST; start it with java -jar on its acsbundle.jar."
      exit 0
    fi

    mkdir -p "$DEST"

    if ! unzip -o "$ARCHIVE" -d "$DEST"; then
      exit 1
    fi

    echo "IBM i Access unpacked in $DEST"

# Add a Microsoft 365 launcher, a web app of the system Chrome.
[group("apps")]
install-m365-pwa ACTION="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    OPTION="{{ ACTION }}"
    LAUNCHER="${XDG_DATA_HOME:-$HOME/.local/share}/applications/m365.desktop"

    if [ "$OPTION" == "help" ]; then
      echo "Usage: ujust install-m365-pwa"
      echo "Writes $LAUNCHER, which opens https://www.office.com"
      echo "as a Chrome app window. Remove the file to remove the launcher. Not for root."
      exit 0
    fi

    if [[ $(id -u) -eq 0 ]]; then
      echo "Please do not run this command as root"
      exit 1
    fi

    if [ "$OPTION" != "" ]; then
      echo "Unknown option: $OPTION (ujust install-m365-pwa help)"
      exit 1
    fi

    # A write cut short leaves no empty launcher that status takes as done.
    if ! mkdir -p "$(dirname "$LAUNCHER")" 2> /dev/null \
      || ! printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Microsoft 365' \
        'Exec=/usr/bin/google-chrome-stable --app=https://www.office.com' 'Categories=Office;' \
        'Terminal=false' 2> /dev/null > "$LAUNCHER.new" \
      || ! mv -f "$LAUNCHER.new" "$LAUNCHER" 2> /dev/null; then
      rm -f "$LAUNCHER.new"
      echo "ERROR: cannot write $LAUNCHER" >&2
      exit 1
    fi

    echo "Microsoft 365 launcher written: $LAUNCHER"
