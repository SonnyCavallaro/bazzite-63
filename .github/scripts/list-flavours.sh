#!/usr/bin/env bash
# Single owner of the flavour set: one line per image, "<image_name> <base_image>".
#
# Usage:
#   list-flavours.sh            # bazzite-63 bazzite
#   list-flavours.sh --names    # image names only, one per line
#
# Every workflow and script that enumerates the images reads this list (the
# build matrix plan, the upstream watcher, the release job, the GHCR cleanup,
# the release-tag resolver, the changelog), so adding or renaming a flavour is
# one edit here. Order matters: it is the order the release notes list them in.
# bazzite-63 builds ONE flavour, from the plain (non-NVIDIA) base.
set -euo pipefail

FLAVOURS=(
  "bazzite-63 bazzite"
)

case "${1:-}" in
  "")       printf '%s\n' "${FLAVOURS[@]}" ;;
  --names)  printf '%s\n' "${FLAVOURS[@]}" | cut -d' ' -f1 ;;
  *) echo "usage: $0 [--names]" >&2; exit 2 ;;
esac
