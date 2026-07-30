#!/usr/bin/bash
# MX block 72: install the out-of-tree ntfsplus module built in the kmod-builder
# stage, regenerate modules.dep, and drop the two generic mount.ntfs helper
# symlinks so the driver is reachable by filesystem type. The driver is Linux
# 7.1's in-tree fs/ntfs (NTFSPLUS), which the ogc kernel builds with
# CONFIG_NTFS_FS off; it registers the filesystem type "ntfs" and the kernel
# loads it on demand at the first mount of that type, so no autoload and no ujust
# recipe ship with it. updates/ mirrors the in-tree path, so a later ogc build
# that enables CONFIG_NTFS_FS is overridden by depmod priority.
echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

KVER=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -1)
SRC="/run/kmods/updates/fs/ntfs/ntfs.ko.xz"
DEST="/usr/lib/modules/${KVER}/updates/fs/ntfs/ntfs.ko.xz"

[ -f "$SRC" ] || { echo "FAIL: $SRC missing (kmod-builder stage produced no ntfsplus)"; exit 1; }

install -Dm644 "$SRC" "$DEST"
depmod "$KVER"

# mount(8) hands any type owning a /sbin/mount.<type> helper to that helper before
# it ever reaches the kernel, and ntfs-3g ships both of these as symlinks to
# mount.ntfs-3g — so an fstab line of type "ntfs" silently lands on FUSE while the
# kernel driver stays unused (gotcha #26). The `mount -i` escape is a command-line
# flag with no fstab equivalent, and a systemd .mount unit inherits the trap because
# it executes mount(8) too (systemd.mount(5)). Removing the two generic symlinks is
# what makes the type selectable from fstab. The ntfs-3g PACKAGE stays installed —
# libguestfs-appliance requires it — and mount.ntfs-3g itself survives, so
# `mount -t ntfs-3g` remains the explicit FUSE escape hatch.
MOUNT_NTFS_HELPERS=(
    /usr/sbin/mount.ntfs
    /usr/bin/mount.ntfs
)
for helper in "${MOUNT_NTFS_HELPERS[@]}"; do
    rm -f "$helper"
done

echo "::endgroup::"
