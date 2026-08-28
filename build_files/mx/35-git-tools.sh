#!/usr/bin/bash
# MX block 35: Git tools (GUI + system helpers).
# Separate from the IDE block because GitKraken is a Git GUI client,
# not an IDE, and `git-credential-libsecret` is a system git helper used
# by every git client (CLI, IDE, GUI) when paired with a Linux keyring.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

### Section 1: GitKraken (RPM from Axosoft CDN, no yum repo upstream) ###
# Axosoft publishes no yum repository, only a stable direct-RPM URL that
# redirects to the latest version — each rebuild pulls the current release,
# no pinning by design (closed-source desktop app, same trust model as
# download.docker.com). No auditable .repo in git because none exists
# upstream; zero dependency footprint (self-bundled Electron, ~663 MiB).
dnf5 -y install https://release.gitkraken.com/linux/gitkraken-amd64.rpm

### Section 2: git-credential-libsecret (Fedora) ###
# Plugs `git` into the Linux keyring (KDE Wallet / GNOME Keyring) so
# every git client — CLI, VSCode, GitKraken — picks up cached HTTPS
# credentials transparently. Aurora ships this in their base layer
# (build_files/base/01-packages.sh:84); Bazzite base does not. Adding
# it here brings the Aurora "secure-by-default" git UX to bazzite-mx.
dnf5 -y install git-credential-libsecret

echo "::endgroup::"
