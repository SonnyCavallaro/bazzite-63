#!/usr/bin/env bash
# Google Chrome as a system RPM from Google's repository, key asserted first,
# present for every user and the system-wide default browser. The RPM's own
# self-updating machinery stays off: on an image dnf never updates it, and
# its repository entry and daily cron would only re-enable a repository.
# Chrome's Flatpak is denied the way bazzite-mx denies Firefox's beside its
# RPM, and bazzite-mx's helpers, which report a Firefox Flatpak, report
# Chrome's; verify-host's INFO line carries the profile copy.
#
# Usage: run by build.sh after 12-host-helpers.sh; no arguments.
# Writes: /etc/default/google-chrome, read by the RPM's %post and its cron;
#   the google-chrome-stable package, its payload moved from /var/opt/google
#   to /usr/lib/opt/google with the tmpfiles line that links it back at boot;
#   the vendored google-chrome.repo put back after the %post; Chrome as the
#   web browser in /etc/xdg/mimeapps.list, on a fresh inode; the line
#   `deny com.google.Chrome/*` in the Flatpak filter; bazzite-mx-verify-host's
#   Flatpak check and verify-host's help line in 95-bazzite-mx.just turned
#   from Firefox to Chrome, each on a fresh inode.
# Exit status: 0 done; the build stops on a `FAIL: …` line.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

KEY=/etc/pki/rpm-gpg/RPM-GPG-KEY-google-chrome
CHROME_REPO=/etc/yum.repos.d/google-chrome.repo
VENDORED_REPO=$CTX/system_files/etc/yum.repos.d/google-chrome.repo
CHROME_DEFAULTS=/etc/default/google-chrome
TMPFILES_CONF=/usr/lib/tmpfiles.d/bazzite-63-opt.conf
MIMEAPPS=/etc/xdg/mimeapps.list
BROWSER_TYPES=(x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml)
# The base's Flatpak filter, which bazzite-flatpak-manager sets on Flathub.
FLATPAK_BLOCKLIST=/usr/share/ublue-os/flatpak-blocklist
DENY_LINE='deny com.google.Chrome/*'
VERIFY_HOST=/usr/libexec/bazzite-mx-verify-host
VERIFY_HOST_HEADER='# of fstab right and mounted, no residue of an earlier setup, the Firefox'
VERIFY_HOST_COMMENT='# Nothing is required by the image; Firefox is reported.'
BASE_RECIPES=/usr/share/ublue-os/just/95-bazzite-mx.just
VERIFY_HOST_HELP='      echo "GPU and flavour, NTFS driver, ntfsplus residue, Firefox Flatpak,'
VERIFY_HOST_HELP+=' image .repo files."'
# chunkah v0.7.0 cannot read a package built with rpm 6, which Chrome is from
# 157.0.8103.50 (coreos/chunkah#189): pinned until CHUNKAH_VERSION reads one.
CHROME_PIN=https://dl.google.com/linux/chrome/rpm/stable/x86_64/
CHROME_PIN+=google-chrome-stable-157.0.8103.38-1.x86_64.rpm

# --- the steps ----------------------------------------------------------------

# The knobs the %post and /etc/cron.daily/google-chrome read before they add
# or re-enable the repository; they must exist before the install.
disable_self_updating() {
    printf '%s\n' repo_add_once=false repo_reenable_on_distupgrade=false > "$CHROME_DEFAULTS"
}

# The package unpacks under /opt, a link to var/opt that a build lacks.
install_chrome() {
    assert_key_fingerprint "$KEY"

    mkdir -p /var/opt
    curl -fsSL --retry 5 --retry-all-errors -o "$BUILD_TMP/google-chrome.rpm" "$CHROME_PIN"
    rpmkeys --import "$KEY"

    if ! rpmkeys --checksig "$BUILD_TMP/google-chrome.rpm"; then
        fail_build "$CHROME_PIN: signature not verified against $KEY"
    fi

    dnf_retry -y install "$BUILD_TMP/google-chrome.rpm"

    install -m 0644 "$VENDORED_REPO" "$CHROME_REPO"
    rm -f /etc/cron.daily/google-chrome
}

# 95-clean-stage.sh empties /var, so the payload moves into /usr and a
# tmpfiles line recreates /var/opt/google at boot: the /opt/google paths baked
# into the wrapper keep resolving.
relocate_payload() {
    if [ ! -d /var/opt/google ] || [ -e /usr/lib/opt/google ]; then
        fail_build "/var/opt/google missing or /usr/lib/opt/google already taken"
    fi

    mkdir -p /usr/lib/opt
    mv /var/opt/google /usr/lib/opt/google
    echo 'L+ /var/opt/google - - - - /usr/lib/opt/google' > "$TMPFILES_CONF"
}

# Merged into the base's [Default Applications], whose other entries stay; a
# user's own ~/.config/mimeapps.list still wins.
set_default_browser() {
    local type

    if ! grep -qx '\[Default Applications\]' "$MIMEAPPS"; then
        fail_build "$MIMEAPPS has no [Default Applications] group"
    fi

    cp "$MIMEAPPS" "$MIMEAPPS.new"

    for type in "${BROWSER_TYPES[@]}"; do
        sed -i "\\|^${type}=|d" "$MIMEAPPS.new"
        sed -i "/^\\[Default Applications\\]\$/a ${type}=google-chrome.desktop" "$MIMEAPPS.new"
    done

    mv -f "$MIMEAPPS.new" "$MIMEAPPS"
}

deny_chrome_flatpak() {
    local count

    {
        awk 1 "$FLATPAK_BLOCKLIST"
        echo "$DENY_LINE"
    } > "$FLATPAK_BLOCKLIST.new"
    mv -f "$FLATPAK_BLOCKLIST.new" "$FLATPAK_BLOCKLIST"

    count=$(grep -cxF -- "$DENY_LINE" "$FLATPAK_BLOCKLIST" || true)

    if [ "$count" != 1 ]; then
        fail_build "$FLATPAK_BLOCKLIST: '$DENY_LINE' found ${count:-0} times, expected once"
    fi
}

# <file> <line>: status 0 when <file> holds <line> exactly once.
holds_once() {
    local count

    count=$(grep -cxF -- "$2" "$1" || true)
    [ "$count" = 1 ]
}

# The function body from its opening line to the first `}` after it gives way
# to bazzite-mx's own, with Chrome for Firefox.
mirror_verify_host_check() {
    local replacement=$BUILD_TMP/check_flatpaks

    if ! holds_once "$VERIFY_HOST" 'check_flatpaks() {' \
        || ! holds_once "$VERIFY_HOST" "$VERIFY_HOST_HEADER" \
        || ! holds_once "$VERIFY_HOST" "$VERIFY_HOST_COMMENT"; then
        fail_build "$VERIFY_HOST: check_flatpaks() or its comments not found exactly once"
    fi

    cat > "$replacement" << 'EOF'
check_flatpaks() {
    local flatpaks

    if ! flatpaks=$(src_flatpaks 2>&1); then
        report_fail "cannot list the Flatpaks: $(reason_on_one_line "$flatpaks")"
        return 0
    fi

    if grep -qx com.google.Chrome <<< "$flatpaks"; then
        report_info "the Chrome Flatpak is still installed next to the RPM: copy the profile" \
            "before the first RPM start, then remove the Flatpak; the copy:" \
            "[ -e ~/.config/google-chrome ]" \
            "|| [ ! -d ~/.var/app/com.google.Chrome/config/google-chrome ]" \
            "|| cp -a ~/.var/app/com.google.Chrome/config/google-chrome ~/.config/"
    else
        report_ok "no Chrome Flatpak (the RPM is the image's browser)"
    fi
}
EOF

    awk -v body="$replacement" -v header="$VERIFY_HOST_HEADER" -v note="$VERIFY_HOST_COMMENT" '
        $0 == header || $0 == note { sub(/Firefox/, "Chrome"); print; next }
        $0 == "check_flatpaks() {" {
            while ((getline line < body) > 0) print line
            skip = 1
            next
        }
        skip && $0 == "}" { skip = 0; next }
        !skip { print }' "$VERIFY_HOST" > "$VERIFY_HOST.new"
    chmod --reference="$VERIFY_HOST" "$VERIFY_HOST.new"
    mv -f "$VERIFY_HOST.new" "$VERIFY_HOST"
}

mirror_verify_host_help() {
    if ! holds_once "$BASE_RECIPES" "$VERIFY_HOST_HELP"; then
        fail_build "$BASE_RECIPES: verify-host's help line not found exactly once"
    fi

    sed -i 's/ntfsplus residue, Firefox Flatpak,/ntfsplus residue, Chrome Flatpak,/' \
        "$BASE_RECIPES"
}

# --- main ---------------------------------------------------------------------

disable_self_updating
install_chrome
relocate_payload
set_default_browser
deny_chrome_flatpak
mirror_verify_host_check
mirror_verify_host_help

log "chrome: $(rpm -q --qf '%{VERSION}' google-chrome-stable), the default web browser"
