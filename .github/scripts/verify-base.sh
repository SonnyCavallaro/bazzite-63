#!/usr/bin/env bash
# Verifies the base before a build reads it: the digest resolve-base.sh pinned
# must carry bazzite-mx's signature, checked against base-cosign.pub, the copy
# of bazzite-mx's cosign.pub this repository keeps. A tag is refused: the
# signature is on the digest, and a tag could move between this check and the
# build.
#
# Usage: verify-base.sh <base image>
#          <base image>  name@sha256:<digest>, resolve-base.sh's base_image
#        verify-base.sh --self-test
#          known-good and known-bad references and cosign answers, cosign as a
#          function
# Needs cosign, and base-cosign.pub at the repository root.
# Output: `verified: <base image> (base-cosign.pub)` on stdout.
# Exit status: 0 verified; 1 a reference without a digest, a key that is not a
#   PEM public key, or a signature cosign does not verify, the reason on stderr
#   as `verify-base: …`.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

BASE_KEY=$(dirname "$0")/../../base-cosign.pub
DIGEST_REFERENCE='^[a-z0-9./-]+@sha256:[0-9a-f]{64}$'

# --- the check ----------------------------------------------------------------

# verify_base <base image>: status 0 when cosign verifies the signature on that
# digest with base-cosign.pub; status 1 with the reason otherwise.
verify_base() {
    local reference=$1
    local output

    if [[ ! "$reference" =~ $DIGEST_REFERENCE ]]; then
        print_error "'$reference' is not pinned to a digest"
        return 1
    fi

    if ! grep -q 'BEGIN PUBLIC KEY' "$BASE_KEY" 2> /dev/null; then
        print_error "$BASE_KEY is not a PEM public key"
        return 1
    fi

    if ! output=$(cosign verify --key "$BASE_KEY" "$reference" 2>&1); then
        print_error "cosign verify failed on $reference: ${output//$'\n'/ }"
        return 1
    fi

    echo "verified: $reference (base-cosign.pub)"
}

# --- self-test ----------------------------------------------------------------

SELF_TEST_REFERENCE=ghcr.io/matrixdj96/bazzite-mx@sha256:$(printf '%064d' 0)

# self_test_expect_refused <what> <reference>: verify_base refuses <reference>.
self_test_expect_refused() {
    local what=$1
    local reference=$2

    REFUSED=$((REFUSED + 1))

    if verify_base "$reference" > /dev/null 2>&1; then
        fail_self_test "$what verified"
    fi
}

# cosign is a function here: COSIGN_ANSWER 0 verifies, anything else fails with
# the shape cosign prints for a key mismatch.
self_test() {
    local good_key=$BASE_KEY
    local scratch

    scratch=$(mktemp -d)
    # shellcheck disable=SC2064  # expand now: the local is gone at EXIT
    trap "rm -rf '$scratch'" EXIT

    cosign() {
        if [ "$COSIGN_ANSWER" -ne 0 ]; then
            echo "Error: no matching signatures: error verifying bundle" >&2
            return 1
        fi
    }

    COSIGN_ANSWER=0

    if ! verify_base "$SELF_TEST_REFERENCE" > /dev/null; then
        fail_self_test "a signed digest was refused"
    fi

    self_test_expect_refused "a tag" ghcr.io/matrixdj96/bazzite-mx:stable
    self_test_expect_refused "a short digest" ghcr.io/matrixdj96/bazzite-mx@sha256:abc

    COSIGN_ANSWER=1
    self_test_expect_refused "a signature cosign rejects" "$SELF_TEST_REFERENCE"

    COSIGN_ANSWER=0
    echo "not a key" > "$scratch/base-cosign.pub"
    BASE_KEY=$scratch/base-cosign.pub
    self_test_expect_refused "a key that is not PEM" "$SELF_TEST_REFERENCE"
    BASE_KEY=$good_key

    echo "self-test ok: a signed digest verified, $REFUSED bad inputs refused"
}

# --- main ---------------------------------------------------------------------

case "${1:-}" in
    --self-test)
        self_test
        ;;
    "" | -*)
        exit_with_error "usage: verify-base.sh <name@sha256:digest> | --self-test"
        ;;
    *)
        if ! verify_base "$1"; then
            exit 1
        fi
        ;;
esac
