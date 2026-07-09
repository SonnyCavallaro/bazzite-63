#!/usr/bin/bash
# MX block 61: Google Chrome from Google's official RPM repo, baked into
# the image (system-wide, every user; pattern of bazzite-mx's Firefox RPM
# block). Updates arrive with image rebuilds — watch-upstream rebuilds
# hourly whenever upstream Bazzite moves.
#
# The vendored .repo ships enabled=0; --enablerepo=google-chrome is the
# runtime-only override during install (validate-repos.sh hard-enforces
# the disabled state).

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

### Section 1: keep Chrome's self-updating machinery off ###
# The RPM ships maintenance hooks (%post + cron.daily) that re-create and
# re-enable its own repo entry for classic self-updating systems; on this
# atomic image dnf never drives updates, so the hooks would only leave an
# enabled=1 repo behind. /etc/default/google-chrome is the documented
# opt-out knob and must exist BEFORE the install for %post to honour it.
printf 'repo_add_once=false\nrepo_reenable_on_distupgrade=false\n' > /etc/default/google-chrome

### Section 2: install Chrome from the vendored repo ###
# /opt is an ostree symlink to var/opt, which does not exist at build time:
# without the mkdir RPM's cpio cannot unpack /opt/google ("mkdir failed").
# Pattern: AmyOS build_files/fix-opt.sh (same mechanics for its Brave RPM).
mkdir -p /var/opt

dnf5 -y install --enablerepo=google-chrome google-chrome-stable

# Belt and braces: whatever the %post did, the repo entry ends disabled
# (sed, not setopt — see gotcha #2) and the daily repo-maintenance cron
# does not ship in the image.
sed -i 's/^enabled=1/enabled=0/g' /etc/yum.repos.d/google-chrome.repo
rm -f /etc/cron.daily/google-chrome

### Section 3: relocate the /opt payload into the image ###
# clean-stage wipes /var, so the unpacked tree moves under /usr/lib/opt and
# systemd-tmpfiles recreates the /var/opt/google link at boot: the
# /opt/google/... paths baked into Chrome's wrapper keep resolving
# (/opt -> var/opt -> /usr/lib/opt/google). Pattern: AmyOS fix-opt.sh.
mkdir -p /usr/lib/opt
mv /var/opt/google /usr/lib/opt/google
echo 'L+ /var/opt/google - - - - /usr/lib/opt/google' > /usr/lib/tmpfiles.d/bazzite-63-chrome-opt.conf

### Section 4: Chrome as system-wide default browser ###
# Merged into Bazzite's own /etc/xdg/mimeapps.list (which ships e.g. the
# Bazaar .flatpakref handler) instead of shipping a static file that
# would clobber upstream entries — see gotcha #23. Users can still
# override per-user via ~/.config/mimeapps.list.
XDG_DEFAULTS=/etc/xdg/mimeapps.list
[ -f "$XDG_DEFAULTS" ] || printf '[Default Applications]\n' > "$XDG_DEFAULTS"
grep -q '^\[Default Applications\]' "$XDG_DEFAULTS" || printf '\n[Default Applications]\n' >> "$XDG_DEFAULTS"
for entry in \
    'x-scheme-handler/http=google-chrome.desktop' \
    'x-scheme-handler/https=google-chrome.desktop' \
    'text/html=google-chrome.desktop' \
    'application/xhtml+xml=google-chrome.desktop'; do
    grep -qxF "$entry" "$XDG_DEFAULTS" || sed -i "/^\[Default Applications\]$/a $entry" "$XDG_DEFAULTS"
done

echo "::endgroup::"
