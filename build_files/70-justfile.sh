#!/usr/bin/env bash
# Joins this image's recipe file to the base justfile, after bazzite-mx's.
# On a duplicate recipe name the earlier import wins, so a name this file
# shares with another is refused.
#
# Usage: run by build.sh; no arguments.
# Writes: the import of 96-bazzite-63.just appended to the master justfile, on
#   a fresh inode; a second run by hand appends it again, which
#   tests/70-justfile.sh refuses.
# Exit status: 0 done; the build stops on a `FAIL: …` line.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

JUST_DIR=/usr/share/ublue-os/just
MASTER=/usr/share/ublue-os/justfile
OURS=96-bazzite-63.just

# --- the steps ----------------------------------------------------------------

one_line() {
    paste -sd ' ' <<< "$1"
}

import_our_recipes() {
    {
        cat "$MASTER"
        echo "import \"$JUST_DIR/$OURS\""
    } > "$MASTER.new"
    mv -f "$MASTER.new" "$MASTER"
}

require_unique_recipe_names() {
    local file all_names duplicates

    all_names=$(
        for file in "$JUST_DIR"/*.just; do
            recipe_set "$file"
        done | sort || true
    )
    duplicates=$(uniq -d <<< "$all_names")

    if [ -n "$duplicates" ]; then
        fail_build "recipes defined in more than one file (the earlier import would win):" \
            "$(one_line "$duplicates")"
    fi
}

# <master-set> and <our-set> are recipe sets, one name per line.
require_master_exposes_ours() {
    local master_set=$1
    local our_set=$2
    local name

    while IFS= read -r name; do
        if ! grep -qx "$name" <<< "$master_set"; then
            fail_build "$MASTER does not expose $name"
        fi
    done <<< "$our_set"
}

# --- main ---------------------------------------------------------------------

if ! just --unstable --fmt --check --justfile "$JUST_DIR/$OURS" > /dev/null 2>&1; then
    fail_build "$OURS is not just --fmt clean"
fi

import_our_recipes
require_unique_recipe_names

if ! master_set=$(recipe_set "$MASTER"); then
    fail_build "$MASTER does not parse after the import"
fi

our_set=$(recipe_set "$JUST_DIR/$OURS")
require_master_exposes_ours "$master_set" "$our_set"

log "justfile: $OURS imported ($(wc -l <<< "$our_set") recipes: $(one_line "$our_set"))," \
    "$(wc -l <<< "$master_set") recipes in ujust"
