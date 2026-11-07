#!/usr/bin/env bash
# Prepare the build: dnf keeps its cache across builds, its metadata refreshed
# once here, and fails on a repository it cannot reach unless the repository's
# own file says skip_if_unavailable=True; the base image's repository files and
# enabled repositories are recorded, so the gate that runs later can tell what
# the build changed.
#
# Usage: run by build.sh as the first script; no arguments.
# Writes: $BUILD_TMP/dnf.conf.base, restored by 95-clean-stage.sh;
#   $BUILD_STATE/repos.base.sha256 and repos.base.enabled, read by
#   90-validate-repos.sh; the SHA-256 of the base's skel profile.ps1 in
#   /usr/share/bazzite-63/bazzite-mx-profile.sha256, read by setup-b63 and
#   setup-dev.
# Exit status: 0 done; the build stops on a `FAIL: …` line.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

BASE_PWSH_PROFILE=/etc/skel/.config/powershell/profile.ps1
MX_PROFILE_SUM=/usr/share/bazzite-63/bazzite-mx-profile.sha256

# --- the steps ----------------------------------------------------------------

# The backup, its user xattrs (the base's chunkah component) with it, is put
# back by 95-clean-stage.sh with a rename, so the file the image ships sits on a
# fresh inode; --preserve=xattr fails, the RUN's tmpfs refusing security.selinux.
# timeout=60 rides out COPR and mirror flakes; the base's skip_if_unavailable=1
# would install without an unreachable repository.
set_build_dnf_options() {
    cp /etc/dnf/dnf.conf "$BUILD_TMP/dnf.conf.base"
    getfattr --absolute-names -d -m '^user\.' /etc/dnf/dnf.conf \
        | sed "s|^# file: .*|# file: $BUILD_TMP/dnf.conf.base|" \
        | setfattr -h -P --restore=-
    dnf5 config-manager setopt keepcache=1 timeout=60 skip_if_unavailable=False
}

# The cache outlives a build, so metadata it kept could predate the mirrors.
refresh_dnf_metadata() {
    dnf_retry makecache --refresh
}

# By content: 90-validate-repos.sh refuses a base file the build modified and
# treats a file outside this list as an addition.
record_base_repo_files() {
    local snapshot=$BUILD_STATE/repos.base.sha256

    (cd /etc/yum.repos.d && sha256sum -- *.repo) > "$snapshot"

    log "prep: $(wc -l < "$snapshot") base repo files recorded"
}

# By dnf5's own answer: 90-validate-repos.sh requires the same set at the end,
# so an override file that enables a repository is caught as well.
record_base_enabled_repos() {
    local snapshot=$BUILD_STATE/repos.base.enabled

    enabled_repos > "$snapshot"

    log "prep: enabled in the base: $(paste -sd ' ' "$snapshot")"
}

# Before 01-system-files.sh puts this image's profile.ps1 over bazzite-mx's: a
# home whose copy still matches gets this image's from setup-dev install.
record_base_pwsh_profile() {
    local sum

    if ! sum=$(sha256sum < "$BASE_PWSH_PROFILE"); then
        fail_build "$BASE_PWSH_PROFILE missing from the base"
    fi

    mkdir -p "$(dirname "$MX_PROFILE_SUM")"
    echo "${sum%% *}" > "$MX_PROFILE_SUM"
}

# --- main ---------------------------------------------------------------------

set_build_dnf_options
refresh_dnf_metadata
record_base_repo_files
record_base_enabled_repos
record_base_pwsh_profile
