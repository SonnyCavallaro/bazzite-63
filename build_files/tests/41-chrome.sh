#!/usr/bin/env bash
# Smoke test of 41-chrome.sh: the package and its key, the repository read
# through the vendored key, the self-updating machinery off, the payload under
# /usr/lib/opt with its boot link, Chrome the default browser beside the base's
# own entries, its Flatpak denied, and bazzite-mx's helpers reporting and
# copying a Chrome Flatpak's profile, with no Firefox item left there or in
# verify-host's help; verify-host, which has no self-test, still parses and
# ends on its main call, and its check and migrate's step 8, each run alone,
# tell a Chrome Flatpak from none (migrate's self-test runs in test 12).
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$(realpath "$0")")/lib.sh"

KEY=/etc/pki/rpm-gpg/RPM-GPG-KEY-google-chrome
TMPFILES_CONF=/usr/lib/tmpfiles.d/bazzite-63-opt.conf
MIMEAPPS=/etc/xdg/mimeapps.list
FLATPAK_BLOCKLIST=/usr/share/ublue-os/flatpak-blocklist
VERIFY_HOST=/usr/libexec/bazzite-mx-verify-host
MIGRATE=/usr/libexec/bazzite-mx-migrate
BASE_RECIPES=/usr/share/ublue-os/just/95-bazzite-mx.just

check_self_updating_off() {
    if grep -qx repo_add_once=false /etc/default/google-chrome 2> /dev/null \
        && grep -qx repo_reenable_on_distupgrade=false /etc/default/google-chrome \
        && [ ! -e /etc/cron.daily/google-chrome ]; then
        echo "OK: /etc/default/google-chrome turns the repository upkeep off, no daily cron"
    else
        echo "FAIL: /etc/default/google-chrome incomplete or /etc/cron.daily/google-chrome shipped"
    fi
}

# The wrapper's /opt path dangles in the build, /var being empty: the link is
# read, not followed.
check_payload() {
    local wrapper

    wrapper=$(readlink /usr/bin/google-chrome-stable || true)

    if [ -x /usr/lib/opt/google/chrome/chrome ] \
        && [ "$wrapper" = /opt/google/chrome/google-chrome ] \
        && grep -qx 'L+ /var/opt/google - - - - /usr/lib/opt/google' "$TMPFILES_CONF"; then
        echo "OK: Chrome under /usr/lib/opt/google, linked back by $TMPFILES_CONF"
    else
        echo "FAIL: Chrome payload: wrapper '${wrapper:-none}', tmpfiles or chrome binary missing"
    fi
}

check_default_browser() {
    local type missing=""

    for type in x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml; do
        if [ "$(grep -c "^${type}=" "$MIMEAPPS" || true)" != 1 ] \
            || ! grep -qxF "${type}=google-chrome.desktop" "$MIMEAPPS"; then
            missing+=" $type"
        fi
    done

    if [ -z "$missing" ] && grep -q '^application/vnd.flatpak.ref=' "$MIMEAPPS"; then
        echo "OK: $MIMEAPPS opens the web in Chrome and keeps the base's entries"
    else
        echo "FAIL: $MIMEAPPS:${missing:- lost the flatpakref entry of the base}"
    fi
}

# holds_line <line> <file>: <file> holds <line> exactly once.
holds_line() {
    [ "$(grep -cxF -- "$1" "$2" || true)" = 1 ]
}

check_flatpak_denied() {
    if holds_line 'deny com.google.Chrome/*' "$FLATPAK_BLOCKLIST" \
        && holds_line 'deny com.valvesoftware.Steam/*' "$FLATPAK_BLOCKLIST"; then
        echo "OK: $FLATPAK_BLOCKLIST denies com.google.Chrome once, the base's lines kept"
    else
        echo "FAIL: $FLATPAK_BLOCKLIST: com.google.Chrome or the base's Steam not denied once"
    fi
}

# The rewritten check run alone on a Flatpak list, its reporters stubbed.
run_verify_host_check() {
    local body

    body=$(sed -n '/^check_flatpaks() {$/,/^}$/p' "$VERIFY_HOST")
    bash -c "src_flatpaks() { echo $1; }
        report_ok() { echo \"OK: \$*\"; }
        report_info() { echo \"INFO: \$*\"; }
        report_fail() { echo \"FAIL: \$*\"; }
        $body
        check_flatpaks" 2>&1 || true
}

# Migrate's step 8 run alone on a Flatpak list, nothing queued or backed up.
run_migrate_step_8() {
    local body

    body=$(sed -n '/^print_step_8_what_stays_with_the_user() {$/,/^}$/p' "$MIGRATE")
    bash -c "src_flatpaks() { echo $1; }
        DEPLOYMENT_QUEUED=0 FSTAB_REWRITTEN=0 BACKUP=
        $body
        print_step_8_what_stays_with_the_user" 2>&1 || true
}

check_verify_host_flatpaks() {
    local with without

    with=$(run_verify_host_check com.google.Chrome)
    without=$(run_verify_host_check org.mozilla.firefox)

    if [[ $with == "INFO: the Chrome Flatpak is still installed next to the RPM"* ]] \
        && [ "$without" = "OK: no Chrome Flatpak (the RPM is the image's browser)" ] \
        && grep -q '^  - Chrome: ' <<< "$(run_migrate_step_8 com.google.Chrome)" \
        && ! grep -q '^  - Chrome: ' <<< "$(run_migrate_step_8 org.mozilla.firefox)"; then
        echo "OK: verify-host reports a Chrome Flatpak, migrate's step 8 lists it, both only then"
    else
        echo "FAIL: verify-host or step 8 on a Chrome Flatpak: $(on_one_line none <<< "$with")"
    fi
}

check_helpers() {
    if bash -n "$VERIFY_HOST" 2> /dev/null \
        && [ "$(tail -n1 "$VERIFY_HOST")" = 'main "$@"' ] \
        && ! grep -qiE 'firefox|mozilla' "$VERIFY_HOST" "$MIGRATE" "$BASE_RECIPES"; then
        echo "OK: verify-host parses and ends on main, no Firefox item in the helpers or help"
    else
        echo "FAIL: verify-host does not parse, or a helper or its help still has a Firefox item"
    fi
}

check_pkg google-chrome-stable
check_key_fingerprint "$KEY"
check_rpm_key d38b4796 Google
check_repo_reads_key /etc/yum.repos.d/google-chrome.repo "$KEY"
check_self_updating_off
check_payload
check_default_browser
check_flatpak_denied
check_helpers
check_verify_host_flatpaks
