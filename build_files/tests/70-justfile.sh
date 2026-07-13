#!/usr/bin/env bash
# Smoke test of 70-justfile.sh: this image's recipe file defines its recipes,
# the master justfile imports it once and exposes every one of them, the base's
# setup-dev is cut out with the rest of its file intact so ujust runs ours, no
# recipe name is defined twice, setup-dev install replaces an untouched
# profile.ps1 (a fixture sum; the shipped one checked for shape) and keeps an
# edited one and fails when mise install fails, install-ibm-acs takes an
# archive named relative to the caller's directory, install-m365-pwa writes a
# valid launcher where setup-b63 looks for it, setup-dev status ignores a pwsh
# off Homebrew's path, setup-dev install keeps Homebrew's DOTNET_ROOT from mise,
# the script's self-test and the setup helper's run, and every recipe's help.
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$(realpath "$0")")/lib.sh"

JUST_DIR=/usr/share/ublue-os/just
MASTER=/usr/share/ublue-os/justfile
OURS=$JUST_DIR/96-bazzite-63.just
CTX=$(dirname "$(realpath "$0")")/../..
BASE_RECIPES=$JUST_DIR/95-bazzite-mx.just
OUR_RECIPES="install-default-flatpaks install-ibm-acs install-m365-pwa install-sap-gui"
OUR_RECIPES+=" setup-b63 setup-dev"
MX_PROFILE_SUM=/usr/share/bazzite-63/bazzite-mx-profile.sha256
PWSH_SKEL=/etc/skel/.config/powershell/profile.ps1

check_our_recipe_file() {
    local defined

    defined=$(recipe_set "$OURS" | tr '\n' ' ' || true)

    if [ "$defined" = "$OUR_RECIPES " ]; then
        echo "OK: $OURS defines exactly: $OUR_RECIPES"
    else
        echo "FAIL: $OURS defines: ${defined:-nothing (the file does not parse)}"
    fi
}

check_master_justfile() {
    local import_count master_set recipe missing=""

    import_count=$(grep -c "^import \"$OURS\"$" "$MASTER" 2> /dev/null || true)
    master_set=$(recipe_set "$MASTER" || true)

    for recipe in $OUR_RECIPES; do
        if ! grep -qx "$recipe" <<< "$master_set"; then
            missing+=" $recipe"
        fi
    done

    if [ "$import_count" = 1 ] && [ -z "$missing" ]; then
        echo "OK: $MASTER imports $OURS once and exposes its recipes"
    else
        echo "FAIL: $MASTER imports $OURS ${import_count:-0} times, missing:${missing:- none}"
    fi
}

check_unique_names() {
    local file duplicates

    duplicates=$(
        for file in "$JUST_DIR"/*.just; do
            recipe_set "$file"
        done | sort | uniq -d || true
    )

    if [ -z "$duplicates" ]; then
        echo "OK: no recipe name defined in two files"
    else
        echo "FAIL: defined twice: $(on_one_line none <<< "$duplicates")"
    fi
}

# ujust runs our setup-dev: the base's is gone from its file, whose other
# recipes stay.
check_setup_dev_override() {
    local base_set shown

    base_set=$(recipe_set "$BASE_RECIPES" | tr '\n' ' ' || true)
    shown=$(just --justfile "$MASTER" --show setup-dev 2>&1 || true)

    if [ "$base_set" = "install-jetbrains-toolbox migrate setup-msi setup-panels verify-host " ] \
        && grep -q 'brew install "$formula"' <<< "$shown"; then
        echo "OK: setup-dev is ours, the base's other recipes stay"
    else
        echo "FAIL: setup-dev override: base recipes [${base_set:-unparsed}]"
    fi
}

# The recipe on fixture homes, as a user (a stub id), with stub brew and mise;
# the shipped sum must be the base's, not this image's skel copy.
check_profile_replacement() {
    local fixture sum skel_sum home stops=0

    sum=$(cat "$MX_PROFILE_SUM" 2> /dev/null || true)
    skel_sum=$(sha256sum < "$PWSH_SKEL" || true)
    fixture=$(mktemp -d)
    mkdir -p "$fixture/bin" "$fixture/fail" "$fixture/stock/.config/powershell" \
        "$fixture/edited/.config/powershell"
    printf '#!/usr/bin/env bash\necho 1000\n' > "$fixture/bin/id"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/bin/brew"
    cp "$fixture/bin/brew" "$fixture/bin/mise"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$fixture/fail/mise"
    chmod +x "$fixture/bin"/* "$fixture/fail/mise"
    echo stock > "$fixture/stock/.config/powershell/profile.ps1"
    echo edited > "$fixture/edited/.config/powershell/profile.ps1"
    sha256sum < "$fixture/stock/.config/powershell/profile.ps1" | cut -d' ' -f1 > "$fixture/sum"

    for home in stock edited; do
        env -u XDG_CONFIG_HOME HOME="$fixture/$home" PATH="$fixture/bin:$PATH" \
            MX_PROFILE_SUM="$fixture/sum" just --justfile "$OURS" setup-dev install \
            > /dev/null 2>&1 || true
    done

    if ! env -u XDG_CONFIG_HOME HOME="$fixture/edited" PATH="$fixture/fail:$fixture/bin:$PATH" \
        MX_PROFILE_SUM="$fixture/sum" just --justfile "$OURS" setup-dev install \
        > /dev/null 2>&1; then
        stops=1
    fi

    if [[ $sum =~ ^[0-9a-f]{64}$ ]] && [ "$sum" != "${skel_sum%% *}" ] \
        && cmp -s "$PWSH_SKEL" "$fixture/stock/.config/powershell/profile.ps1" \
        && cmp -s /etc/skel/.config/mise/config.toml "$fixture/stock/.config/mise/config.toml" \
        && grep -qx edited "$fixture/edited/.config/powershell/profile.ps1" \
        && [ "$stops" = 1 ]; then
        echo "OK: setup-dev install seeds the mise config, replaces bazzite-mx's profile.ps1," \
            "keeps an edited one, fails with mise"
    else
        echo "FAIL: setup-dev install: sum '${sum:-none}', fixture homes or the mise" \
            "failure not as expected"
    fi

    rm -rf "$fixture"
}

# ujust runs a recipe in the justfile's directory unless it is [no-cd].
check_relative_archive() {
    local fixture

    fixture=$(mktemp -d)
    echo acs > "$fixture/acsbundle.jar"
    (cd "$fixture" && zip -q acs.zip acsbundle.jar)

    if (cd "$fixture" && env -u XDG_DATA_HOME HOME="$fixture/home" \
        just --justfile "$OURS" install-ibm-acs acs.zip > /dev/null 2>&1) \
        && [ -f "$fixture/home/.local/share/ibm-acs/acsbundle.jar" ]; then
        echo "OK: install-ibm-acs unpacks an archive named relative to the caller"
    else
        echo "FAIL: install-ibm-acs does not find an archive named relative to the caller"
    fi

    rm -rf "$fixture"
}

# The literal path is setup-b63's M365_LAUNCHER; the stub id runs it as a user.
check_m365_launcher() {
    local fixture

    fixture=$(mktemp -d)
    mkdir "$fixture/bin"
    printf '#!/usr/bin/env bash\necho 1000\n' > "$fixture/bin/id"
    chmod +x "$fixture/bin/id"
    env -u XDG_DATA_HOME HOME="$fixture" PATH="$fixture/bin:$PATH" \
        just --justfile "$OURS" install-m365-pwa > /dev/null 2>&1 || true
    check_desktop_file "$fixture/.local/share/applications/m365.desktop"
    rm -rf "$fixture"
}

# The base has no /home/linuxbrew: only the not-found answer can be staged.
check_dev_status_pwsh() {
    local fixture output

    fixture=$(mktemp -d)
    mkdir "$fixture/bin"
    printf '#!/usr/bin/env bash\necho 1000\n' > "$fixture/bin/id"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/bin/mise"
    cp "$fixture/bin/mise" "$fixture/bin/pwsh"
    chmod +x "$fixture/bin"/*
    output=$(env -u XDG_CONFIG_HOME HOME="$fixture" PATH="$fixture/bin:$PATH" \
        just --justfile "$OURS" setup-dev status 2>&1 || true)

    if grep -qxF 'pwsh: none yet (ujust setup-dev install)' <<< "$output"; then
        echo "OK: setup-dev status counts only Homebrew's pwsh, not one on PATH"
    else
        echo "FAIL: setup-dev status counts a pwsh on PATH: $(on_one_line none <<< "$output")"
    fi

    rm -rf "$fixture"
}

# Homebrew's pwsh launcher value; mise would install the .NET SDK into it.
check_dev_install_dotnet_root() {
    local fixture seen

    fixture=$(mktemp -d)
    mkdir "$fixture/bin"
    printf '#!/usr/bin/env bash\necho 1000\n' > "$fixture/bin/id"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/bin/brew"
    printf '#!/usr/bin/env bash\necho "${DOTNET_ROOT:-unset}" > "$HOME/got"\n' > "$fixture/bin/mise"
    chmod +x "$fixture/bin"/*
    env -u XDG_CONFIG_HOME HOME="$fixture" PATH="$fixture/bin:$PATH" \
        DOTNET_ROOT=/home/linuxbrew/.linuxbrew/opt/dotnet/libexec \
        just --justfile "$OURS" setup-dev install > /dev/null 2>&1 || true
    seen=$(cat "$fixture/got" 2> /dev/null || true)

    if [ "$seen" = unset ]; then
        echo "OK: setup-dev install runs mise without Homebrew's DOTNET_ROOT"
    else
        echo "FAIL: setup-dev install ran mise with DOTNET_ROOT '${seen:-mise never ran}'"
    fi

    rm -rf "$fixture"
}

check_our_recipe_file
check_master_justfile
check_unique_names
check_setup_dev_override
check_profile_replacement
check_relative_archive
check_m365_launcher
check_dev_status_pwsh
check_dev_install_dotnet_root
check_self_test 70-justfile.sh bash "$CTX/build_files/70-justfile.sh"
check_self_test bazzite-63-setup /usr/libexec/bazzite-63-setup

for recipe in $OUR_RECIPES; do
    check_recipe_help "$OURS" "$recipe"
done
