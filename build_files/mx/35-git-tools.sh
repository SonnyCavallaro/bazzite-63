#!/usr/bin/bash
# MX block 35: Git tools (GUI + system helpers).
# Separate from the IDE block because GitKraken is a Git GUI client,
# not an IDE, and `git-credential-libsecret` is a system git helper used
# by every git client (CLI, IDE, GUI) when paired with a Linux keyring.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

### Section 1: GitKraken (RPM from Axosoft CDN, no yum repo upstream) ###
# Axosoft publishes no yum repository and no signed RPM: the stable URL
# redirects to a versioned path (release.gitkraken.dev/…/<version>/<token>/)
# whose content changes on every GitKraken release, and the package carries
# no GPG signature (`rpm -qp --qf '%{SIGPGP:pgpsig}'` → none, MEASURED
# 2026-09-01 on 12.4.0) — unlike download.docker.com, where docker-ce.repo
# has gpgcheck=1. The build always takes the current release: a version+sha256
# pin behind a "latest" redirect made every build fail on each vendor release
# (MEASURED 2026-09-03 → 05: ten Watch Upstream runs red on the sha256 check
# after GitKraken moved past 12.4.0, with the base image updating underneath).
# The trust model is TLS to the vendor plus the RPM's own payload digests:
# `rpm -K --nosignature` verifies the header and payload checksums stored in
# the package, so a truncated or swapped download fails the build before dnf5
# touches the file. The version that shipped is logged for the build record.
# Zero dependency footprint (self-bundled Electron, ~663 MiB).
GITKRAKEN_URL=https://release.gitkraken.com/linux/gitkraken-amd64.rpm
GITKRAKEN_RPM=/tmp/gitkraken-amd64.rpm
curl -fsSL --retry 3 --retry-delay 5 -o "${GITKRAKEN_RPM}" "${GITKRAKEN_URL}"
rpm -K --nosignature "${GITKRAKEN_RPM}" || { echo "::error::gitkraken-amd64.rpm: payload digest check failed" >&2; exit 1; }
GITKRAKEN_VERSION=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "${GITKRAKEN_RPM}")
[ -n "${GITKRAKEN_VERSION}" ] || { echo "::error::gitkraken-amd64.rpm: not an RPM" >&2; exit 1; }
echo "gitkraken: downloaded ${GITKRAKEN_VERSION} ($(stat -c %s "${GITKRAKEN_RPM}") bytes)"
dnf5 -y install "${GITKRAKEN_RPM}"
rm -f "${GITKRAKEN_RPM}"

### Section 2: git-credential-libsecret (Fedora) ###
# Plugs `git` into the Linux keyring (KDE Wallet / GNOME Keyring) so
# every git client — CLI, VSCode, GitKraken — picks up cached HTTPS
# credentials transparently. Aurora ships this in their base layer
# (build_files/base/01-packages.sh:84); Bazzite base does not. Adding
# it here brings the Aurora "secure-by-default" git UX to bazzite-63.
dnf5 -y install git-credential-libsecret

echo "::endgroup::"
