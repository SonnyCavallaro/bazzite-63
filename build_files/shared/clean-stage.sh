#!/usr/bin/bash
# Final cleanup before bootc lint + image build completion.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

# Restore the pristine dnf.conf (build.sh raises the dnf timeout for the stage)
if [ -f /tmp/dnf.conf.orig ]; then
    mv /tmp/dnf.conf.orig /etc/dnf/dnf.conf
fi

# Clear any versionlock entries (idempotent)
dnf5 versionlock clear 2>/dev/null || true

# Prevent Fedora flatpak repos from being added (idempotent, safe if absent)
if [ -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service ]; then
    systemctl mask flatpak-add-fedora-repos.service || true
    rm -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service
fi

# Selective /var cleanup (preserve cache and log: both are cache mounts
# in the final RUN, so they are mountpoints rm cannot remove)
find /var/* -maxdepth 0 -type d ! -name cache ! -name log -exec rm -fr {} \;
rm -rf /tmp/*
mkdir -p /var/tmp

echo "::endgroup::"
