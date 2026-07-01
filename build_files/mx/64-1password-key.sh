#!/usr/bin/bash
# MX block 64: fetch the 1Password GPG key on every build from the
# official downloads.1password.com endpoint (1Password ships no
# `*-release` rpm, so build-time fetch is the path; hourly rebuilds
# keep the key fresh across rotations).
#
# The 1password.repo file stays vendored (enabled=0, repo_gpgcheck=1);
# the key is the rotating piece, not the config.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

KEY_URL=https://downloads.1password.com/linux/keys/1password.asc
KEY_PATH=/etc/pki/rpm-gpg/1password.asc

curl -fsSL "$KEY_URL" -o "$KEY_PATH"
chmod 0644 "$KEY_PATH"

# Sanity check: valid PGP block + non-empty. If 1Password replaces the
# file with something else (e.g. HTML 404 page or redirect), the build
# fails here instead of at runtime on the user's machine.
[ -s "$KEY_PATH" ] || { echo "FAIL: $KEY_PATH empty"; exit 1; }
grep -q '^-----BEGIN PGP PUBLIC KEY BLOCK-----$' "$KEY_PATH" || {
    echo "FAIL: $KEY_PATH does not look like a PGP key block"
    exit 1
}

echo "::endgroup::"
