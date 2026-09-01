#!/usr/bin/bash
# Repo isolation validator.
# Ported from ublue-os/aurora with bazzite-mx specific repo additions.
# Build fails if any third-party repo is left with enabled=1.

echo "::group:: ===$(basename "$0")==="

set -eou pipefail

REPOS_DIR="/etc/yum.repos.d"
VALIDATION_FAILED=0
ENABLED_REPOS=()
declare -A CHECKED=()

echo "Validating all repository files are disabled..."

if [[ ! -d "$REPOS_DIR" ]]; then
    echo "Warning: $REPOS_DIR does not exist"
    exit 0
fi

check_repo_file() {
    local repo_file="$1"
    local basename_file
    basename_file=$(basename "$repo_file")

    [[ ! -f "$repo_file" ]] && return 0
    [[ ! -r "$repo_file" ]] && return 0
    CHECKED["$basename_file"]=1

    if grep -q "^enabled=1" "$repo_file" 2>/dev/null; then
        echo "ENABLED: $basename_file"
        ENABLED_REPOS+=("$basename_file")
        VALIDATION_FAILED=1

        echo "   Enabled sections:"
        local section_name=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[.*\]$ ]]; then
                section_name="$line"
            elif [[ "$line" =~ ^enabled=1 ]]; then
                echo "     - $section_name"
            fi
        done < "$repo_file"
    else
        echo "Disabled: $basename_file"
    fi
}

echo ""
echo "Checking COPR repositories (standard naming)..."
echo "NOTE: With secure isolated installation, NO COPRs should be globally enabled!"
for repo in "$REPOS_DIR"/_copr:copr.fedorainfracloud.org:*.repo; do
    [[ -f "$repo" ]] && check_repo_file "$repo"
done

echo ""
echo "Checking COPR repositories (non-standard naming)..."
for repo in "$REPOS_DIR"/_copr_*.repo; do
    [[ -f "$repo" ]] && check_repo_file "$repo"
done

echo ""
echo "Checking third-party repositories (bazzite-mx + bazzite + aurora known)..."
# The enforced list lives in third-party-repos.list beside this script, so the
# post-rechunk check-image-integrity.sh enforces the same entries on the cold
# bytes without a second copy drifting from this one. Aurora upstream keeps the
# array inline; the file is bazzite-mx's deviation, and it buys the cold half.
REPO_LIST="$(dirname "$(readlink -f "$0")")/third-party-repos.list"
if [[ ! -f "$REPO_LIST" ]]; then
    echo "FAIL: $REPO_LIST missing (the enforced repo list has no other source)"
    exit 1
fi
mapfile -t OTHER_REPOS < <(grep -vE '^[[:space:]]*(#|$)' "$REPO_LIST")
if [[ ${#OTHER_REPOS[@]} -eq 0 ]]; then
    echo "FAIL: $REPO_LIST lists no repo (an empty list enforces nothing)"
    exit 1
fi

for repo_name in "${OTHER_REPOS[@]}"; do
    # A '?' prefix marks an optional entry: enforced enabled=0 when present,
    # tolerated when absent (a repo the base has shipped before and may ship
    # again, e.g. fedora-coreos-pool.repo — dropping it entirely would leave
    # a reintroduced file unenforced in the informational sweep).
    optional=0
    if [[ "$repo_name" == \?* ]]; then
        optional=1
        repo_name="${repo_name#\?}"
    fi
    # A malformed entry ('? name' with a space, a bare '?', a non-.repo name)
    # must fail loudly: stripped to a nonexistent path it would ride the
    # optional branch into a silent skip, evaporating its enforcement.
    if [[ ! "$repo_name" =~ ^[A-Za-z0-9._-]+\.repo$ ]]; then
        echo "MALFORMED: '$repo_name' in third-party-repos.list is not a bare .repo basename"
        ENABLED_REPOS+=("$repo_name (malformed entry)")
        VALIDATION_FAILED=1
        continue
    fi
    repo_path="$REPOS_DIR/$repo_name"
    # The list is authoritative in both directions (same rule as the cold
    # check): a listed file absent from the image means a renamed upstream
    # repo file or an install script that stopped shipping it. Skipping it
    # would leave the renamed file unenforced and fail only post-rechunk
    # (base 44.20260831 renamed fedora-multimedia.repo to
    # negativo17-fedora-multimedia.repo and this loop said nothing).
    if [[ ! -f "$repo_path" ]]; then
        if [[ "$optional" -eq 1 ]]; then
            echo "Optional (absent): $repo_name"
            continue
        fi
        echo "ABSENT: $repo_name is listed in third-party-repos.list but not in the image"
        ENABLED_REPOS+=("$repo_name (absent)")
        VALIDATION_FAILED=1
        continue
    fi
    check_repo_file "$repo_path"
done

echo ""
echo "Checking RPM Fusion repositories..."
for repo in "$REPOS_DIR"/rpmfusion-*.repo; do
    [[ -f "$repo" ]] || continue
    [[ -n "${CHECKED[$(basename "$repo")]:-}" ]] && continue
    check_repo_file "$repo"
done

# Informational catch-all: list every .repo file not covered by the
# explicit lists above WITHOUT failing the build. Core Fedora repos
# (fedora.repo, fedora-updates.repo, fedora-updates-archive.repo) are
# legitimately enabled=1 and must stay that way -- they are the only
# three left in the image once clean-stage.sh has disabled terra-mesa
# (MEASURED 2026-09-01 on localhost/bazzite-mx:preflight).
#
# Purpose: during PR review, this section makes it visible whether a
# new repo file appeared in the image without being registered in
# third-party-repos.list. If you add a third-party repo, add it to that
# file so it gets hard-enforced disabled instead of just listed here.
echo ""
echo "Informational: other .repo files seen in the image (not enforced)..."
for repo in "$REPOS_DIR"/*.repo; do
    [[ -f "$repo" ]] || continue
    basename_file=$(basename "$repo")
    [[ -n "${CHECKED[$basename_file]:-}" ]] && continue
    if grep -q "^enabled=1" "$repo" 2>/dev/null; then
        echo "  enabled=1: $basename_file"
    else
        echo "  enabled=0: $basename_file"
    fi
done

echo ""
echo "======================================"
if [[ $VALIDATION_FAILED -eq 1 ]]; then
    echo "VALIDATION FAILED"
    echo "======================================"
    echo ""
    echo "The following repositories failed isolation (enabled=1, or listed but absent):"
    for repo in "${ENABLED_REPOS[@]}"; do
        echo "  - $repo"
    done
    echo "::endgroup::"
    exit 1
fi

echo "::endgroup::"
