#!/usr/bin/env bash
# Smoke test of 70-justfile.sh: this image's recipe file defines its recipes,
# the master justfile imports it once and exposes every one of them, and no
# recipe name is defined twice.
#
# Usage: run by tests/run.sh inside the image (offline, on the cleaned tree).
# Output: one `OK: <what>` or `FAIL: <what>` line per check, on stdout.
# Exit status: 0 on any outcome; the runner judges the FAIL lines.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$(realpath "$0")")/lib.sh"

JUST_DIR=/usr/share/ublue-os/just
MASTER=/usr/share/ublue-os/justfile
OURS=$JUST_DIR/96-bazzite-63.just
OUR_RECIPES="install-default-flatpaks"

check_our_recipe_file() {
    local defined

    defined=$(recipe_set "$OURS" | tr '\n' ' ' || true)

    if [ "$defined" = "$OUR_RECIPES " ]; then
        echo "OK: $OURS defines exactly: $OUR_RECIPES"
    else
        echo "FAIL: $OURS defines: ${defined:-nothing (the file does not parse)}"
    fi
}

check_master_justfile() {
    local import_count master_set recipe missing=""

    import_count=$(grep -c "^import \"$OURS\"$" "$MASTER" 2> /dev/null || true)
    master_set=$(recipe_set "$MASTER" || true)

    for recipe in $OUR_RECIPES; do
        if ! grep -qx "$recipe" <<< "$master_set"; then
            missing+=" $recipe"
        fi
    done

    if [ "$import_count" = 1 ] && [ -z "$missing" ]; then
        echo "OK: $MASTER imports $OURS once and exposes its recipes"
    else
        echo "FAIL: $MASTER imports $OURS ${import_count:-0} times, missing:${missing:- none}"
    fi
}

check_unique_names() {
    local file duplicates

    duplicates=$(
        for file in "$JUST_DIR"/*.just; do
            recipe_set "$file"
        done | sort | uniq -d || true
    )

    if [ -z "$duplicates" ]; then
        echo "OK: no recipe name defined in two files"
    else
        echo "FAIL: defined twice: $(on_one_line none <<< "$duplicates")"
    fi
}

check_our_recipe_file
check_master_justfile
check_unique_names
