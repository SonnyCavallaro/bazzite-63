#!/usr/bin/bash
# MX block 65: Sunshine self-hosted game-streaming host (Moonlight server).
#
# Installs Sunshine as a system RPM from the `lizardbyte/stable` COPR via
# the isolated-COPR pattern. Shipping the RPM avoids the per-user cost of
# Bazzite's brew-based `setup-sunshine` (compiles a 30+ MiB binary on each
# machine).
#
# DNF resolves package names case-insensitively, so the install uses the
# lowercase `sunshine`; `rpm -q` is case-sensitive, so the smoke test
# queries `rpm -q Sunshine`.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

# shellcheck disable=SC1091
source /ctx/build_files/shared/copr-helpers.sh

### Section 1: install Sunshine from lizardbyte/stable (isolated COPR) ###
copr_install_isolated "lizardbyte/stable" "sunshine"

### Section 2: setcap for KMS capture (high-performance path) ###
# Sunshine's KMS-based capture (Wayland and X11) needs CAP_SYS_ADMIN at
# startup for direct `/dev/dri/card*` framebuffer scrape; without it
# Sunshine falls back to slower PipeWire screencast capture. The COPR
# package ships no setcap. `readlink -f` resolves the version-suffixed
# binary so the cap lands on it, not the symlink.
setcap 'cap_sys_admin+p' "$(readlink -f /usr/bin/sunshine)"

### Section 3: keep the user service disabled (opt-in) ###
# The COPR ships no preset, so the unit is disabled by default; this is
# defense-in-depth against a future preset that enables it. The user
# opts in via `ujust setup-sunshine enable`.
systemctl --global disable app-dev.lizardbyte.app.Sunshine.service

### Section 4: drop Bazzite's "switch-to-brew" announcement nag ###
# The nag tells users Sunshine will be removed from base Bazzite and must
# be reinstalled via Bazzite Portal; misleading with our RPM integration.
NAG=/usr/share/ublue-os/announcements/sunshine-brew.msg.json
[ -f "$NAG" ] && rm -f "$NAG"

echo "::endgroup::"
