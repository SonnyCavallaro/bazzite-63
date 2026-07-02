#!/usr/bin/env bash
# The paths of a build and the libraries every build script uses. Sourced
# first by build.sh and by every NN-<feature>.sh, which take their `set` from
# here; the paths derive from this file's own location, so the context works
# under any mount point.
#
# Exports: BUILD_FILES, CTX (the repo root), BUILD_TMP (tmpfs, dies with the
# RUN), BUILD_STATE (ships in the image for the test RUN; its own directory,
# so the base's /usr/lib/bazzite-mx/build-state, which bazzite-mx-verify-host
# reads on every host, keeps naming Bazzite's repositories),
# PYTHONDONTWRITEBYTECODE (dnf5 and its scriptlets inherit it).
set -euo pipefail

BUILD_FILES=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
BUILD_FILES=$(realpath "$BUILD_FILES/..")
CTX=$(realpath "$BUILD_FILES/..")
BUILD_TMP=/tmp/bazzite-63-build
BUILD_STATE=/usr/lib/bazzite-63/build-state
# Scriptlets write no .pyc (docs/gotchas.md § A scriptlet rewrote a packaged `.pyc`).
PYTHONDONTWRITEBYTECODE=1
export BUILD_FILES CTX BUILD_TMP BUILD_STATE PYTHONDONTWRITEBYTECODE

mkdir -p "$BUILD_TMP" "$BUILD_STATE"

# shellcheck source=log.sh
source "$BUILD_FILES/lib/log.sh"
# shellcheck source=repos.sh
source "$BUILD_FILES/lib/repos.sh"
# shellcheck source=gpg.sh
source "$BUILD_FILES/lib/gpg.sh"
# shellcheck source=just.sh
source "$BUILD_FILES/lib/just.sh"
