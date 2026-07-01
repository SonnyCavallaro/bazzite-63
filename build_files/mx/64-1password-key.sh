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

# The key is served by the same host as the packages it will verify, so
# gpgcheck alone trusts whatever key that host hands out. Pinning the
# fingerprint (MEASURED 2026-09-01: rsa4096, expires 2032-05-16) turns the
# check from structural into cryptographic: a rotated or swapped key fails
# the build, and the bump is a reviewed change (upstream-refresh round).
KEY_FINGERPRINT=3FEF9748469ADBE15DA7CA80AC2D62742012EA22
GNUPGHOME=$(mktemp -d)
export GNUPGHOME
gpg --batch --with-colons --show-keys "$KEY_PATH" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10; exit }' \
    | grep -qxF "$KEY_FINGERPRINT" || {
    echo "FAIL: $KEY_PATH fingerprint differs from the pinned $KEY_FINGERPRINT"
    exit 1
}
rm -rf "$GNUPGHOME"
unset GNUPGHOME

echo "::endgroup::"
