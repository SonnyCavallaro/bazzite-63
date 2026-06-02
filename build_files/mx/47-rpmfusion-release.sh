#!/usr/bin/bash
# MX block 47: install rpmfusion-nonfree-release to ship the GPG keys
# and .repo files for RPM Fusion non-free without static vendoring
# (the release package's keys auto-update via `bootc upgrade`).
#
# The .repo files arrive enabled=1 from upstream; we disable them
# immediately to align with the project's enabled=0 baseline (opt-in
# via --enablerepo= at build time or a ujust recipe at runtime).

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

dnf5 -y install \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Disable every main section of the .repo files shipped by the package.
# The `g` flag is necessary because each file has 3 sections (main +
# debuginfo + source), with enabled=1 only on release/updates main and
# enabled=0 on debuginfo/source. The `g` flips only the mains (the
# others are already 0).
sed -i 's/^enabled=1/enabled=0/g' \
    /etc/yum.repos.d/rpmfusion-nonfree.repo \
    /etc/yum.repos.d/rpmfusion-nonfree-updates.repo \
    /etc/yum.repos.d/rpmfusion-nonfree-updates-testing.repo

echo "::endgroup::"
