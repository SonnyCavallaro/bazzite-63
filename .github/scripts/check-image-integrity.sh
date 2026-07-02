#!/usr/bin/env bash
# Cold-read integrity check of every artefact the build mutates, run INSIDE the
# image after rechunk (reusable-build.yml mounts this file into chunked-img).
#
# The 6.17-azure kernel on runner image ubuntu-24.04 20260816+ loses page
# writeback of writes into copied-up overlay files — the base-image files a RUN
# step modifies in place. Every in-build read answers from warm page cache, so
# 10-tests-mx.sh passes while the committed layer carries a NUL tail: release
# 44.20260823 shipped a btree-damaged rpmdb and 44.20260826 a master justfile
# that killed every ujust at parse time (gotcha #40). This check reads the
# chunked image, whose read path surfaces the on-disk bytes.
#
# Two nets, because they fail differently: a NUL sweep over the mutated text
# artefacts catches a torn tail wherever it lands, and per-artefact probes catch
# a tear that ends on a clean boundary — which the sweep cannot see.
#
# Positive control: commit a container with one artefact torn
# (`printf '\0\0\0' >> <file>`, or truncating it) and run this script against
# that image; each section is proven to fail on its own known-bad input before
# a green run is trusted.
set -euo pipefail

fail() {
    echo "::error::$*"
    exit 1
}

# The kernel whose module tree the build extended. Derived from the modules
# directory rather than from rpm, so a damaged rpmdb cannot mask section 7.
mapfile -t KDIRS < <(find /usr/lib/modules -mindepth 2 -maxdepth 2 -name vmlinuz -printf '%h\n' | sort)
[ "${#KDIRS[@]}" -eq 1 ] || fail "expected exactly 1 bootable module tree, found ${#KDIRS[@]}: ${KDIRS[*]}"
KDIR="${KDIRS[0]}"
KVER="${KDIR##*/}"

# --- 1. NUL sweep over the build-mutated text artefacts ---
#
# Every path here is a file the build writes, or writes into: the in-place
# writers of the write-site inventory plus the rename-based ones, since the
# sweep costs nothing and a tear must not depend on our reading of a tool's
# semantics. Binary artefacts are absent by construction — they carry NULs
# legitimately (the SELinux policy store and modules.*.bin are the two large
# ones) and reach their own probes in sections 2-7 instead.
REQUIRED=(
    /usr/share/ublue-os/justfile
    /usr/share/ublue-os/flatpak-blocklist
    /usr/share/ublue-os/bazzite/flatpak/install
    /usr/share/ublue-os/image-info.json
    /usr/lib/os-release
    /etc/xdg/kcm-about-distrorc
    /etc/passwd
    /etc/group
    /etc/dnf/dnf.conf
    /etc/dnf/versionlock.toml
    /etc/sysctl.d/90-bazzite-63-forwarding.conf
    /etc/modules-load.d/90-bazzite-63-nat.conf
    /etc/pki/rpm-gpg/1password.asc
    /etc/skel/.config/Code/User/settings.json
    /usr/lib/modprobe.d/bazzite-63-kvm.conf
    /usr/lib/sysusers.d/bazzite-63-docker.conf
    /usr/lib/bootc/install/01-bazzite-mx.toml
    /usr/libexec/bazzite-dx-kvmfr-setup
    /usr/libexec/sunshine-start-vmon
    /usr/libexec/sunshine-stop-vmon
    "$KDIR/modules.dep"
    "$KDIR/modules.alias"
    "$KDIR/modules.symbols"
    "$KDIR/modules.devname"
    "$KDIR/modules.softdep"
    "$KDIR/modules.order"
)
# Each group must match at least one file: an empty glob would make the sweep
# pass vacuously on a renamed upstream directory.
GLOBS=(
    '/usr/share/ublue-os/just/*.just'
    '/etc/yum.repos.d/*.repo'
    '/usr/share/ublue-os/system-setup.hooks.d/*.sh'
    '/usr/share/ublue-os/user-setup.hooks.d/*.sh'
)

SWEEP=()
for f in "${REQUIRED[@]}"; do
    [ -f "$f" ] || fail "build-mutated artefact missing: $f"
    SWEEP+=("$f")
done
for g in "${GLOBS[@]}"; do
    mapfile -t matches < <(compgen -G "$g" || true)
    [ "${#matches[@]}" -gt 0 ] || fail "no file matches $g (upstream layout changed?)"
    SWEEP+=("${matches[@]}")
done

# grep's status carries the verdict: 0 found NULs, 1 clean, anything else is a
# broken probe that must not read as clean. -a forces text matching, or grep
# answers "binary file matches" instead of naming the file.
set +e
nul_hits=$(grep -laP '\x00' -- "${SWEEP[@]}" 2>&1)
nul_rc=$?
set -e
case "$nul_rc" in
    0) fail "NUL bytes in build-mutated artefacts (torn writeback): ${nul_hits//$'\n'/, }" ;;
    1) : ;;
    *) fail "NUL sweep did not run (grep exit $nul_rc): $nul_hits" ;;
esac
echo "NUL sweep clean (${#SWEEP[@]} artefacts)"

# --- 2. the rpm databases the build rewrites (build.sh steps 4 and 5) ---
#
# PRAGMA integrity_check walks every btree page, so partial damage cannot hide
# behind the pages a query happens to read. Heavy corruption makes sqlite RAISE
# instead of returning findings rows, so both paths report. rpm-ostree's
# base-db is the same file hardlinked (step 5), and the equality check below is
# what proves the relink: a base-db still carrying the base image's package set
# passes every probe above it on its own.
python3 - <<'PYEOF'
import os
import sqlite3
import sys

# path -> minimum row count that makes the database plausible
RPMDB = "/usr/share/rpm/rpmdb.sqlite"
BASE_DB = "/usr/lib/sysimage/rpm-ostree-base-db/rpmdb.sqlite"
DATABASES = {
    RPMDB: ("Packages", 2000),
    BASE_DB: ("Packages", 2000),
}
counts = {}

for db, (table, minimum) in DATABASES.items():
    # build.sh step 4 folds the WAL into the vacuumed copy and drops the
    # sidecars, and step 5 drops the base image's own beside the base-db: one
    # surviving here means that step never ran.
    for sidecar in (db + "-wal", db + "-shm"):
        if os.path.exists(sidecar):
            print(f"::error::{sidecar} present — build.sh left a stale sidecar")
            sys.exit(1)
    try:
        conn = sqlite3.connect(f"file:{db}?mode=ro&immutable=1", uri=True)
        rows = conn.execute("PRAGMA integrity_check").fetchall()
        if rows != [("ok",)]:
            print(f"::error::{db} integrity_check reports corruption:", str(rows)[:300])
            sys.exit(1)
        count = conn.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
    except sqlite3.Error as exc:
        print(f"::error::{db} unreadable: {exc}")
        sys.exit(1)
    if count < minimum:
        print(f"::error::{db} implausibly small ({count} rows in {table})")
        sys.exit(1)
    counts[db] = count
    print(f"{db} integrity ok ({count} rows in {table})")

if counts[RPMDB] != counts[BASE_DB]:
    print(f"::error::{BASE_DB} holds {counts[BASE_DB]} packages against the "
          f"rpmdb's {counts[RPMDB]} — build.sh step 5 did not relink it")
    sys.exit(1)
print("rpm-ostree base-db relinked to the built rpmdb")
PYEOF

# --- 3. libdnf5 build state is gone (clean-stage.sh) ---
#
# The directory's contents change on every build, so leaving them in makes the
# libdnf5 package's chunk unique per build and every `bootc upgrade` re-download
# it (aurora cf4bc197). It is also where transaction_history.sqlite used to sit:
# the delete is what retired its VACUUM INTO in build.sh step 4, so a silently
# reverted delete would leave that database shipped and unguarded.
if compgen -G '/usr/lib/sysimage/libdnf5/*' > /dev/null; then
    fail "/usr/lib/sysimage/libdnf5 is not empty: $(echo /usr/lib/sysimage/libdnf5/*)"
fi
echo "libdnf5 build state cleared"

# --- 4. justfile tree: imports present and the whole tree parses ---
#
# 55-justfile-reconcile.sh appends the two imports to the master and rewrites
# three upstream files; a tear eats exactly the appended tail. The parse catches
# a tear that ends on a clean line boundary, and just's exit status is read
# directly — never piped, where `| head` would mask it.
for f in 95-bazzite-mx.just 96-bazzite-mx-overrides.just; do
    grep -qxF "import \"/usr/share/ublue-os/just/$f\"" /usr/share/ublue-os/justfile \
        || fail "import line for $f missing from the master justfile"
done
just --unstable --justfile /usr/share/ublue-os/justfile --summary > /dev/null \
    || fail "master justfile does not parse with its import tree"
echo "justfile tree ok"

# --- 5. image identity (00-image-info.sh) ---
#
# The three sed-rewritten fields are what bootc and ublue-update read to find
# the upgrade source, so a torn image-info.json points a deployed host at
# nothing. Parsing it as JSON also catches a tear inside the structure.
python3 -c 'import json,sys; json.load(open("/usr/share/ublue-os/image-info.json"))' \
    || fail "/usr/share/ublue-os/image-info.json is not valid JSON"
for field in image-name image-ref image-vendor; do
    grep -q "\"$field\":" /usr/share/ublue-os/image-info.json \
        || fail "image-info.json lost its $field field"
done
grep -qxF 'VARIANT_ID=bazzite-63' /usr/lib/os-release \
    || fail "/usr/lib/os-release lost its rewritten VARIANT_ID"
grep -qxF 'Variant=bazzite-63' /etc/xdg/kcm-about-distrorc \
    || fail "/etc/xdg/kcm-about-distrorc lost its rewritten Variant"
grep -qxF 'Website=https://github.com/SonnyCavallaro/bazzite-63' /etc/xdg/kcm-about-distrorc \
    || fail "/etc/xdg/kcm-about-distrorc lost its rewritten Website"
echo "image identity ok"

# --- 6. flatpak lists (21-virt-manager-flatpak-exclude.sh) ---
#
# The deny line is an append onto a base-image file — the shape that tore the
# master justfile. Firefox stays the base Bazzite Flatpak on this image: no
# firefox deny line, and the install list keeps its firefox entry.
grep -qxF 'deny org.virt_manager.virt-manager/*' /usr/share/ublue-os/flatpak-blocklist \
    || fail "flatpak-blocklist lost its deny line for org.virt_manager.virt-manager"
# 68-flatpak-apps.sh appends the bazzite-63 apps to the install list, the same
# in-place shape; a tear eats the tail, so the last appended id is the probe.
grep -qxF 'com.discordapp.Discord' /usr/share/ublue-os/bazzite/flatpak/install \
    || fail "the flatpak install list lost its appended bazzite-63 tail (com.discordapp.Discord)"
echo "flatpak lists ok"

# --- 7. module index (70/71/72 install + depmod) ---
#
# depmod rewrites modules.dep.bin, a binary index the NUL sweep cannot read.
# Resolving each out-of-tree module through it proves the cold index is intact
# and still ranks updates/ above the in-tree copy.
for m in msi-ec acpi_ec ntfs; do
    path=$(modinfo -k "$KVER" -F filename "$m" 2>/dev/null) \
        || fail "module $m does not resolve through the cold module index"
    case "$path" in
        */updates/*) ;;
        *) fail "module $m resolves to '$path' (expected …/updates/…)" ;;
    esac
done
echo "module index ok ($KVER)"

# --- 8. repo isolation on the cold bytes (AGENTS.md convention 2) ---
#
# validate-repos.sh enforces enabled=0 during the build, warm. A tear that eats
# the tail of a .repo file drops that very line, and dnf treats a section with no
# enabled= as ENABLED — a third-party repo silently live on the deployed host.
# reusable-build.yml passes the same third-party-repos.list the validator reads,
# so there is one authoritative list; an empty value is a broken hand-off, not an
# empty list, and fails here rather than passing vacuously.
[ -n "${THIRD_PARTY_REPOS:-}" ] || fail "THIRD_PARTY_REPOS is empty (the repo list never reached this check)"
checked=0
while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    # '?' prefix = optional entry (same contract as validate-repos.sh):
    # enforced enabled=0 when present, tolerated when absent. A malformed
    # entry must fail loudly, not ride the optional branch into a silent
    # skip that evaporates its enforcement.
    optional=0
    case "$repo" in \?*) optional=1; repo="${repo#\?}" ;; esac
    case "$repo" in
        *[!A-Za-z0-9._-]*) fail "malformed entry '$repo' in the third-party repo list" ;;
        *.repo) ;;
        *) fail "malformed entry '$repo' in the third-party repo list" ;;
    esac
    path="/etc/yum.repos.d/$repo"
    # The list is authoritative in both directions: a listed file that is
    # absent means a renamed repo file or an install script that stopped
    # shipping it, and skipping it here would let that regression pass on
    # the strength of the remaining entries.
    if [ ! -f "$path" ]; then
        if [ "$optional" -eq 1 ]; then
            echo "optional repo absent (tolerated): $repo"
            continue
        fi
        fail "$path is listed in third-party-repos.list but absent from the image"
    fi
    grep -q "^enabled=" "$path" || fail "$path carries no enabled= line (torn tail?)"
    if grep -q "^enabled=1" "$path"; then
        fail "$path is enabled=1 in the shipped image"
    fi
    checked=$((checked + 1))
done <<< "$THIRD_PARTY_REPOS"
[ "$checked" -gt 0 ] || fail "none of the listed third-party repos is present in the image"
echo "repo isolation ok ($checked third-party repos disabled)"

# --- 9. upstream versionlock pins survive our stage ---
#
# Bazzite pins its kernel stack and the Valve-patched mesa packages with
# `versionlock add` (upstream Containerfile:152,671). Our clean-stage used to
# run `dnf5 versionlock clear`, shipping `packages = []`; nothing else in the
# build touches versionlock, so the shipped file must still carry the base's
# names. Classes, not the exact set: upstream is free to add or drop a pin, and
# what this catches is the wholesale wipe.
VERSIONLOCK=/etc/dnf/versionlock.toml
mapfile -t VL_NAMES < <(sed -n 's/^name = "\(.*\)"$/\1/p' "$VERSIONLOCK")
[ "${#VL_NAMES[@]}" -ge 10 ] \
    || fail "$VERSIONLOCK carries ${#VL_NAMES[@]} pins (the base ships 21) — versionlock cleared?"
for pkg in kernel kernel-core; do
    printf '%s\n' "${VL_NAMES[@]}" | grep -qxF "$pkg" \
        || fail "$VERSIONLOCK lost its upstream pin for $pkg"
done
printf '%s\n' "${VL_NAMES[@]}" | grep -q '^mesa-' \
    || fail "$VERSIONLOCK lost the upstream mesa-* pins"
echo "versionlock ok (${#VL_NAMES[@]} upstream pins)"

echo "image integrity ok"
