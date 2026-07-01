#!/usr/bin/env bash
# Firefox goes back to Bazzite's Flatpak, the first entry of its default
# install list: bazzite-mx's Fedora RPM is removed with the Bazzite defaults
# copied into it, the Flatpak's deny line leaves the base's filter, and the
# host helpers stop calling the RPM the image's browser.
#
# Usage: run by build.sh after 12-host-helpers.sh; no arguments.
# Writes: firefox and firefox-langpacks removed, /usr/lib64/firefox gone; the
#   `deny org.mozilla.firefox/*` line out of the Flatpak filter; the Firefox
#   check of bazzite-mx-verify-host and the Firefox item of migrate's step 8
#   replaced, each on a fresh inode.
# Exit status: 0 done; the build stops on a `FAIL: …` line when a package, the
#   deny line or an anchor in the helpers is not where the base put it.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

FIREFOX_DIR=/usr/lib64/firefox
# The base's Flatpak filter, which bazzite-flatpak-manager sets on Flathub.
FLATPAK_BLOCKLIST=/usr/share/ublue-os/flatpak-blocklist
DENY_LINE='deny org.mozilla.firefox/*'
VERIFY_HOST=/usr/libexec/bazzite-mx-verify-host
MIGRATE=/usr/libexec/bazzite-mx-migrate
STEP_8_PLAN='    echo "  8. print what is left: Firefox profile copy, reboot, rollback,'
STEP_8_PLAN+=' where they apply"'
STEP_8_FIREFOX='    if ! flatpaks=$(src_flatpaks 2> /dev/null) \'

# --- the steps ----------------------------------------------------------------

# The Bazzite defaults bazzite-mx installed beside the RPM belong to no
# package, so the directory goes with them.
remove_firefox_rpm() {
    dnf5 -y remove firefox firefox-langpacks
    rm -rf "$FIREFOX_DIR"
}

allow_firefox_flatpak() {
    local count

    count=$(grep -cxF -- "$DENY_LINE" "$FLATPAK_BLOCKLIST" || true)

    if [ "$count" != 1 ]; then
        fail_build "$FLATPAK_BLOCKLIST: '$DENY_LINE' found ${count:-0} times, expected once"
    fi

    grep -vxF -- "$DENY_LINE" "$FLATPAK_BLOCKLIST" > "$FLATPAK_BLOCKLIST.new" || true
    mv -f "$FLATPAK_BLOCKLIST.new" "$FLATPAK_BLOCKLIST"
}

# <file> <line>: status 0 when <file> holds <line> exactly once.
holds_once() {
    local count

    count=$(grep -cxF -- "$2" "$1" || true)
    [ "$count" = 1 ]
}

# The function body from its opening line to the first `}` after it gives way
# to the one below: present, the Flatpak is the browser; missing, the user
# installs it.
replace_verify_host_check() {
    local replacement=$BUILD_TMP/check_flatpaks

    if ! holds_once "$VERIFY_HOST" 'check_flatpaks() {'; then
        fail_build "$VERIFY_HOST: check_flatpaks() not found exactly once"
    fi

    cat > "$replacement" << 'EOF'
check_flatpaks() {
    local flatpaks

    if ! flatpaks=$(src_flatpaks 2>&1); then
        report_fail "cannot list the Flatpaks: $(reason_on_one_line "$flatpaks")"
        return 0
    fi

    if grep -qx org.mozilla.firefox <<< "$flatpaks"; then
        report_ok "the Firefox Flatpak is installed (the image's browser)"
    else
        report_info "no Firefox Flatpak: flatpak install flathub org.mozilla.firefox" \
            "installs it"
    fi
}
EOF

    awk -v body="$replacement" '
        $0 == "check_flatpaks() {" { while ((getline line < body) > 0) print line; skip = 1; next }
        skip && $0 == "}" { skip = 0; next }
        !skip { print }' "$VERIFY_HOST" > "$VERIFY_HOST.new"
    chmod --reference="$VERIFY_HOST" "$VERIFY_HOST.new"
    mv -f "$VERIFY_HOST.new" "$VERIFY_HOST"
}

# The profile copy into the RPM goes from the plan and from step 8, the block
# from its `if` to the first `    fi` after it.
drop_migrate_firefox_item() {
    if ! holds_once "$MIGRATE" "$STEP_8_PLAN" || ! holds_once "$MIGRATE" "$STEP_8_FIREFOX"; then
        fail_build "$MIGRATE: the Firefox item of step 8 not found exactly once"
    fi

    awk -v plan="$STEP_8_PLAN" -v start="$STEP_8_FIREFOX" '
        $0 == plan { sub(/Firefox profile copy, /, ""); print; next }
        $0 == start { skip = 1; next }
        skip && $0 == "    fi" { skip = 0; drop_blank = 1; next }
        skip { next }
        drop_blank && $0 == "" { drop_blank = 0; next }
        { drop_blank = 0; print }' "$MIGRATE" > "$MIGRATE.new"
    chmod --reference="$MIGRATE" "$MIGRATE.new"
    mv -f "$MIGRATE.new" "$MIGRATE"
}

# --- main ---------------------------------------------------------------------

remove_firefox_rpm
allow_firefox_flatpak
replace_verify_host_check
drop_migrate_firefox_item

log "firefox-flatpak: the RPM removed, the Flatpak allowed and reported by the helpers"
