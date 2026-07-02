#!/usr/bin/bash
# bazzite-63 smoke tests. Runs after the build orchestrator, immediately before
# bootc container lint. Blocking: every assertion exits 1 on failure.
#
# Each domain script in build_files/mx/ extends this file with rpm-q +
# systemctl is-enabled + file-existence assertions for the things it
# adds, so the test grows in parallel with the build.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

# --- IP forwarding sysctl marker ---
if [ ! -f /etc/sysctl.d/90-bazzite-63-forwarding.conf ]; then
    echo "FAIL: missing /etc/sysctl.d/90-bazzite-63-forwarding.conf"
    exit 1
fi

# --- iptable_nat modules-load marker ---
if [ ! -f /etc/modules-load.d/90-bazzite-63-nat.conf ]; then
    echo "FAIL: missing /etc/modules-load.d/90-bazzite-63-nat.conf"
    exit 1
fi

# --- Image identity + KDE about-page branding (00-image-info.sh) ---
grep -qE '"image-name":[[:space:]]*"bazzite-63(-nvidia(-open)?)?"' /usr/share/ublue-os/image-info.json || {
    echo "FAIL: /usr/share/ublue-os/image-info.json image-name not rewritten"
    cat /usr/share/ublue-os/image-info.json
    exit 1
}
grep -qE '"image-vendor":[[:space:]]*"sonnycavallaro"' /usr/share/ublue-os/image-info.json || {
    echo "FAIL: /usr/share/ublue-os/image-info.json image-vendor not rewritten to sonnycavallaro"
    grep image-vendor /usr/share/ublue-os/image-info.json || true
    exit 1
}
grep -qE '"image-ref":[[:space:]]*"ostree-image-signed:docker://ghcr.io/sonnycavallaro/bazzite-63(-nvidia(-open)?)?"' /usr/share/ublue-os/image-info.json || {
    echo "FAIL: /usr/share/ublue-os/image-info.json image-ref not rewritten"
    grep image-ref /usr/share/ublue-os/image-info.json || true
    exit 1
}
grep -qE '^VARIANT_ID=bazzite-63(-nvidia(-open)?)?$' /usr/lib/os-release || {
    echo "FAIL: /usr/lib/os-release VARIANT_ID not rewritten"
    grep ^VARIANT_ID= /usr/lib/os-release || true
    exit 1
}
grep -qE '^Variant=bazzite-63( \(NVIDIA( Open)?\))?$' /etc/xdg/kcm-about-distrorc || {
    echo "FAIL: /etc/xdg/kcm-about-distrorc Variant not rewritten or malformed"
    grep ^Variant= /etc/xdg/kcm-about-distrorc || true
    exit 1
}
grep -q '^Website=https://github.com/SonnyCavallaro/bazzite-63$' /etc/xdg/kcm-about-distrorc || {
    echo "FAIL: /etc/xdg/kcm-about-distrorc Website not rewritten"
    grep ^Website= /etc/xdg/kcm-about-distrorc || true
    exit 1
}

# --- Phase 3: Container runtime packages ---
CONTAINER_RPMS=(
    podman-compose podman-machine podman-tui podman-bootc
    docker-ce docker-ce-cli containerd.io
    docker-buildx-plugin docker-compose-plugin docker-model-plugin
)
for p in "${CONTAINER_RPMS[@]}"; do
    rpm -q "$p" >/dev/null || { echo "FAIL: rpm $p missing"; exit 1; }
done

# --- Phase 3: Container runtime services ---
# `is-enabled` returns exit 0 also for static/linked/indirect/alias states,
# which are not what we want. Compare the literal string instead.
CONTAINER_UNITS=( docker.socket podman.socket )
for u in "${CONTAINER_UNITS[@]}"; do
    state=$(systemctl is-enabled "$u" 2>/dev/null || echo missing)
    if [ "$state" != "enabled" ]; then
        echo "FAIL: $u not enabled (state=$state)"
        exit 1
    fi
done

# --- Phase 4: Virtualization packages ---
VIRT_RPMS=(
    libvirt libvirt-nss
    qemu-img qemu-kvm qemu-system-x86-core
    qemu-char-spice qemu-device-display-virtio-gpu
    qemu-device-display-virtio-vga qemu-device-usb-redirect
    qemu-user-binfmt qemu-user-static
    virt-manager virt-viewer virt-install
    edk2-ovmf
    swtpm swtpm-tools
    waypipe
    guestfs-tools
    ublue-os-libvirt-workarounds
)
for p in "${VIRT_RPMS[@]}"; do
    rpm -q "$p" >/dev/null || { echo "FAIL: rpm $p missing"; exit 1; }
done

# --- Phase 4: Virtualization services ---
VIRT_UNITS=(
    ublue-os-libvirt-workarounds.service
    libvirtd.service
)
for u in "${VIRT_UNITS[@]}"; do
    state=$(systemctl is-enabled "$u" 2>/dev/null || echo missing)
    if [ "$state" != "enabled" ]; then
        echo "FAIL: $u not enabled (state=$state)"
        exit 1
    fi
done

# --- Phase 4: KVM module options (kvm.ignore_msrs / kvm.report_ignored_msrs) ---
# Shipped as modprobe.d options: kmod applies them at every kvm.ko load on
# any deployment kind. A bootc kargs.d TOML reaches only bootc-managed
# deployments (rpm-ostree never reads /usr/lib/bootc/kargs.d), so the
# modprobe.d file is the single source of the KVM tuning.
KVM_MODPROBE_FILE=/usr/lib/modprobe.d/bazzite-63-kvm.conf
if [ ! -f "$KVM_MODPROBE_FILE" ]; then
    echo "FAIL: $KVM_MODPROBE_FILE missing"
    exit 1
fi
grep -qE '^options kvm ignore_msrs=1 report_ignored_msrs=0$' "$KVM_MODPROBE_FILE" || {
    echo "FAIL: $KVM_MODPROBE_FILE missing 'options kvm ignore_msrs=1 report_ignored_msrs=0'"
    exit 1
}
if [ -e /usr/lib/bootc/kargs.d/01-bazzite-63-virt.toml ]; then
    echo "FAIL: stale KVM kargs.d TOML shipped alongside the modprobe.d options"
    exit 1
fi

# --- Phase 4: setup-virtualization recipe override ---
VIRT_JUSTFILE=/usr/share/ublue-os/just/84-bazzite-virt.just
if [ ! -f "$VIRT_JUSTFILE" ]; then
    echo "FAIL: $VIRT_JUSTFILE missing"
    exit 1
fi
grep -q 'bazzite-63 OVERRIDE of Bazzite' "$VIRT_JUSTFILE" || {
    echo "FAIL: $VIRT_JUSTFILE is the upstream version (override not applied)"
    exit 1
}
if grep -qE '^[[:space:]]*flatpak install.*org\.virt_manager\.virt-manager' "$VIRT_JUSTFILE"; then
    echo "FAIL: $VIRT_JUSTFILE contains a residual 'flatpak install' line for virt-manager"
    exit 1
fi

# --- Phase 4: virt-manager flatpak blocklist (21-virt-manager-flatpak-exclude.sh) ---
FLATPAK_BLOCKLIST=/usr/share/ublue-os/flatpak-blocklist
grep -q '^deny org\.virt_manager\.virt-manager/\*$' "$FLATPAK_BLOCKLIST" || {
    echo "FAIL: $FLATPAK_BLOCKLIST missing virt-manager deny line"
    exit 1
}

# --- Phase 4: virt-manager flatpak cleanup hooks ---
VIRT_HOOK_SYSTEM=/usr/share/ublue-os/system-setup.hooks.d/16-bazzite-mx-virt-manager-flatpak-cleanup.sh
VIRT_HOOK_USER=/usr/share/ublue-os/user-setup.hooks.d/16-bazzite-mx-virt-manager-flatpak-cleanup.sh
if [ ! -x "$VIRT_HOOK_SYSTEM" ]; then
    echo "FAIL: $VIRT_HOOK_SYSTEM missing or not executable"
    exit 1
fi
if [ ! -x "$VIRT_HOOK_USER" ]; then
    echo "FAIL: $VIRT_HOOK_USER missing or not executable"
    exit 1
fi

# --- Phase 5: IDE packages ---
IDE_RPMS=( code )
for p in "${IDE_RPMS[@]}"; do
    rpm -q "$p" >/dev/null || { echo "FAIL: rpm $p missing"; exit 1; }
done

# --- Phase 5: VSCode atomic-aware default settings ---
# Shipped via /etc/skel/.config/Code/User/settings.json so first-login
# user accounts inherit `update.mode=none` (atomic /usr is read-only,
# VSCode self-updater would fail).
VSCODE_SETTINGS=/etc/skel/.config/Code/User/settings.json
if [ ! -f "$VSCODE_SETTINGS" ]; then
    echo "FAIL: $VSCODE_SETTINGS missing"
    exit 1
fi
grep -q '"update.mode": "none"' "$VSCODE_SETTINGS" || {
    echo "FAIL: $VSCODE_SETTINGS missing update.mode=none guard"
    exit 1
}

# --- Phase 5: Git tools (GUI + system helper) ---
GIT_TOOLS_RPMS=( gitkraken git-credential-libsecret )
for p in "${GIT_TOOLS_RPMS[@]}"; do
    rpm -q "$p" >/dev/null || { echo "FAIL: rpm $p missing"; exit 1; }
done

# --- Phase 6: Dev/sysadmin CLI tools ---
DEV_CLI_RPMS=(
    android-tools
    bcc bcc-tools bpftrace bpftop
    sysprof iotop-c nicstat numactl trace-cmd
    flatpak-builder
    ripgrep
    cosign # shipped by the Bazzite base; asserted because image verification relies on it
)
for p in "${DEV_CLI_RPMS[@]}"; do
    rpm -q "$p" >/dev/null || { echo "FAIL: rpm $p missing"; exit 1; }
done

# --- Phase 6: CLI binaries from official releases (41-dev-cli-pinned.sh) ---
CLI_BINARIES=( gh glab shellcheck shfmt )
for b in "${CLI_BINARIES[@]}"; do
    [ -x "/usr/bin/$b" ] || { echo "FAIL: /usr/bin/$b missing or not executable"; exit 1; }
done

# --- Phase 8: 1Password vendored repo + GPG key fetched at build ---
ONEPW_REPO=/etc/yum.repos.d/1password.repo
ONEPW_GPGKEY=/etc/pki/rpm-gpg/1password.asc
if [ ! -f "$ONEPW_REPO" ]; then
    echo "FAIL: $ONEPW_REPO missing"
    exit 1
fi
if grep -q "^enabled=1" "$ONEPW_REPO"; then
    echo "FAIL: $ONEPW_REPO should be enabled=0 (runtime-enabled by ujust install-1password)"
    exit 1
fi
if [ ! -s "$ONEPW_GPGKEY" ]; then
    echo "FAIL: $ONEPW_GPGKEY missing or empty (64-1password-key.sh broken?)"
    exit 1
fi

# --- Phase 9: Bazzite-DX gems (ccache + ublue-setup-services COPR) ---
EXTRAS_RPMS=( ccache ublue-setup-services )
for p in "${EXTRAS_RPMS[@]}"; do
    rpm -q "$p" >/dev/null || { echo "FAIL: rpm $p missing"; exit 1; }
done

# --- Phase 9: ublue setup-services framework wiring ---
EXTRAS_UNITS=( ublue-system-setup.service )
for u in "${EXTRAS_UNITS[@]}"; do
    state=$(systemctl is-enabled "$u" 2>/dev/null || echo missing)
    if [ "$state" != "enabled" ]; then
        echo "FAIL: $u not enabled (state=$state)"
        exit 1
    fi
done
if [ ! -f /usr/lib/systemd/user/ublue-user-setup.service ]; then
    echo "FAIL: ublue-user-setup.service unit file missing"
    exit 1
fi

# --- Phase 9: bazzite-63-groups system-setup hook (v2) ---
GROUPS_HOOK=/usr/share/ublue-os/system-setup.hooks.d/10-bazzite-63-groups.sh
if [ ! -x "$GROUPS_HOOK" ]; then
    echo "FAIL: $GROUPS_HOOK missing or not executable"
    exit 1
fi
if [ ! -f /usr/lib/ublue/setup-services/libsetup.sh ]; then
    echo "FAIL: /usr/lib/ublue/setup-services/libsetup.sh missing"
    exit 1
fi
grep -qE '^version-script bazzite-63-groups system 2[[:space:]]' "$GROUPS_HOOK" || {
    echo "FAIL: $GROUPS_HOOK is not at version 2 (regression on docker-group fix)"
    exit 1
}

# --- Phase 9: docker group via sysusers.d (compensates rpm-ostree scriptlet suppression) ---
DOCKER_SYSUSERS=/usr/lib/sysusers.d/bazzite-63-docker.conf
if [ ! -f "$DOCKER_SYSUSERS" ]; then
    echo "FAIL: $DOCKER_SYSUSERS missing (docker-ce group gap not patched)"
    exit 1
fi
grep -qE '^g[[:space:]]+docker[[:space:]]+-' "$DOCKER_SYSUSERS" || {
    echo "FAIL: $DOCKER_SYSUSERS does not declare 'g docker -' (malformed sysusers)"
    exit 1
}

# --- Phase 10: 95-bazzite-mx.just shipped + master justfile import wired ---
MX_JUSTFILE=/usr/share/ublue-os/just/95-bazzite-mx.just
if [ ! -f "$MX_JUSTFILE" ]; then
    echo "FAIL: $MX_JUSTFILE missing"
    exit 1
fi
grep -q '^install-1password:' "$MX_JUSTFILE" || {
    echo "FAIL: install-1password recipe not found in $MX_JUSTFILE"
    exit 1
}
grep -q '^_pkg_layered ' "$MX_JUSTFILE" || {
    echo "FAIL: _pkg_layered private helper not found in $MX_JUSTFILE"
    exit 1
}
grep -q '^reset-repos:' "$MX_JUSTFILE" || {
    echo "FAIL: reset-repos recipe not found in $MX_JUSTFILE"
    exit 1
}
grep -q "import \"/usr/share/ublue-os/just/95-bazzite-mx.just\"" /usr/share/ublue-os/justfile || {
    echo "FAIL: import line for 95-bazzite-mx.just missing from master justfile"
    exit 1
}

# --- bazzite-63: companion justfile (96) shipped + import wired ---
B63_JUSTFILE=/usr/share/ublue-os/just/96-bazzite-63.just
if [ ! -f "$B63_JUSTFILE" ]; then
    echo "FAIL: $B63_JUSTFILE missing"
    exit 1
fi
for recipe in setup-dev install-winboat install-rider install-sap-gui install-ibm-acs setup-m365-pwa b63-status; do
    grep -q "^${recipe}" "$B63_JUSTFILE" || {
        echo "FAIL: ${recipe} recipe not found in $B63_JUSTFILE"
        exit 1
    }
done
grep -q "import \"/usr/share/ublue-os/just/96-bazzite-63.just\"" /usr/share/ublue-os/justfile || {
    echo "FAIL: import line for 96-bazzite-63.just missing from master justfile"
    exit 1
}

# --- Phase 11: Desktop apps (gparted + ptyxis) ---
DESKTOP_RPMS=( gparted ptyxis )
for p in "${DESKTOP_RPMS[@]}"; do
    rpm -q "$p" >/dev/null || { echo "FAIL: rpm $p missing"; exit 1; }
done

# --- Phase 11: vscode-extensions user-setup hook ---
VSCODE_HOOK=/usr/share/ublue-os/user-setup.hooks.d/11-bazzite-mx-vscode-extensions.sh
if [ ! -x "$VSCODE_HOOK" ]; then
    echo "FAIL: $VSCODE_HOOK missing or not executable"
    exit 1
fi
VSCODE_EXTENSIONS=(
    ms-vscode-remote.remote-containers
    ms-vscode-remote.remote-ssh
    ms-azuretools.vscode-containers
)
for ext in "${VSCODE_EXTENSIONS[@]}"; do
    grep -qF "$ext" "$VSCODE_HOOK" || {
        echo "FAIL: $VSCODE_HOOK does not install $ext (regression?)"
        exit 1
    }
done

# --- Phase 12: Sunshine reintegration (build-time RPM, opt-in user service) ---
rpm -q Sunshine >/dev/null || {
    echo "FAIL: Sunshine rpm missing (65-sunshine.sh broken? COPR offline?)"
    exit 1
}
SUNSHINE_BIN=$(readlink -f /usr/bin/sunshine)
SUNSHINE_CAPS=$(getcap "$SUNSHINE_BIN" 2>/dev/null || true)
case "$SUNSHINE_CAPS" in
    *cap_sys_admin*) ;;
    *)
        echo "FAIL: $SUNSHINE_BIN missing cap_sys_admin (getcap output: '$SUNSHINE_CAPS')"
        exit 1
        ;;
esac
SUNSHINE_UNIT=app-dev.lizardbyte.app.Sunshine.service
sun_state=$(systemctl --global is-enabled "$SUNSHINE_UNIT" 2>/dev/null || true)
if [ -z "$sun_state" ]; then
    echo "FAIL: $SUNSHINE_UNIT lookup returned empty stdout"
    exit 1
fi
if [ "$sun_state" != "disabled" ]; then
    echo "FAIL: $SUNSHINE_UNIT --global state is '$sun_state' (expected 'disabled')"
    exit 1
fi
SUNSHINE_JUSTFILE=/usr/share/ublue-os/just/82-bazzite-sunshine.just
if [ ! -f "$SUNSHINE_JUSTFILE" ]; then
    echo "FAIL: $SUNSHINE_JUSTFILE missing"
    exit 1
fi
grep -q 'bazzite-63 OVERRIDE of Bazzite' "$SUNSHINE_JUSTFILE" || {
    echo "FAIL: $SUNSHINE_JUSTFILE is the upstream brew-flavored version"
    exit 1
}
if grep -qE '^[[:space:]]*[^#].*homebrew\.sunshine' "$SUNSHINE_JUSTFILE"; then
    echo "FAIL: $SUNSHINE_JUSTFILE contains a residual 'homebrew.sunshine' reference outside comments"
    exit 1
fi
SUNSHINE_NAG=/usr/share/ublue-os/announcements/sunshine-brew.msg.json
if [ -f "$SUNSHINE_NAG" ]; then
    echo "FAIL: $SUNSHINE_NAG should have been removed by 65-sunshine.sh"
    exit 1
fi

# --- Phase 16: msi-ec out-of-tree module (build-time, opt-in) ---
MSI_KVER=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -1)
MSI_EC_KO="/usr/lib/modules/${MSI_KVER}/updates/drivers/platform/x86/msi-ec.ko.xz"
if [ ! -f "$MSI_EC_KO" ]; then
    echo "FAIL: $MSI_EC_KO missing (msi-ec build/install broken?)"
    exit 1
fi
# modules.dep must resolve msi-ec to the updates/ copy, not the in-tree kernel/ one
msi_ec_path=$(modinfo -k "$MSI_KVER" -F filename msi-ec 2>/dev/null || true)
case "$msi_ec_path" in
    */updates/*) ;;
    *) echo "FAIL: msi-ec resolves to '$msi_ec_path' (expected …/updates/…; in-tree not overridden)"; exit 1 ;;
esac
# the installed module must be the upstream build that whitelists the device EC firmware.
# Decompress to a temp file first, then grep -a: a `xz -dc | grep -q` pipe trips
# `set -o pipefail` because grep -q exits on first match, SIGPIPEs xz, and xz's
# resulting non-zero status reads as a false failure. (grep -a also avoids
# depending on `strings`, which the final image may not ship.)
msi_ec_tmp=$(mktemp)
xz -dc "$MSI_EC_KO" > "$msi_ec_tmp" 2>/dev/null || true
if ! grep -aqF '17L5EMS1.115' "$msi_ec_tmp"; then
    rm -f "$msi_ec_tmp"
    echo "FAIL: installed msi-ec lacks firmware id 17L5EMS1.115 (stale/wrong source)"
    exit 1
fi
rm -f "$msi_ec_tmp"
# the .ko.xz MUST be CRC32-checked: the kernel's module XZ decompressor rejects
# the default CRC64 stream at modprobe ("decompression failed"). userspace xz
# decompresses either, so this is the only build-time guard against that class.
if ! LC_ALL=C xz --list "$MSI_EC_KO" 2>/dev/null | grep -q 'CRC32'; then
    echo "FAIL: $MSI_EC_KO is not CRC32-compressed (kernel cannot decompress it at modprobe)"
    LC_ALL=C xz --list "$MSI_EC_KO" 2>&1 || true
    exit 1
fi
# opt-in invariant: the image ships NO EC-module autoload (only `ujust setup-msi
# enable` adds /etc/modules-load.d/bazzite-mx-msi.conf at runtime)
shopt -s nullglob
ec_autoload=(
    /usr/lib/modules-load.d/*{msi-ec,acpi_ec,bazzite-mx-msi}*
    /etc/modules-load.d/*{msi-ec,acpi_ec,bazzite-mx-msi}*
)
shopt -u nullglob
if [ "${#ec_autoload[@]}" -gt 0 ]; then
    echo "FAIL: an EC-module modules-load.d autoload is shipped (breaks opt-in)"
    exit 1
fi
# ujust recipe present (MX_JUSTFILE defined in the Phase 10 block above)
grep -q '^setup-msi ' "$MX_JUSTFILE" || {
    echo "FAIL: setup-msi recipe missing from $MX_JUSTFILE"
    exit 1
}

# --- Phase 17: acpi_ec out-of-tree module (build-time, opt-in) ---
# acpi_ec creates the root-only /dev/ec chardev (fan RPM + curves for
# MControlCenter). Unlike msi-ec there is no in-tree copy, but it still
# ships under updates/.
ACPI_EC_KO="/usr/lib/modules/${MSI_KVER}/updates/drivers/acpi/acpi_ec.ko.xz"
if [ ! -f "$ACPI_EC_KO" ]; then
    echo "FAIL: $ACPI_EC_KO missing (acpi_ec build/install broken?)"
    exit 1
fi
acpi_ec_path=$(modinfo -k "$MSI_KVER" -F filename acpi_ec 2>/dev/null || true)
case "$acpi_ec_path" in
    */updates/*) ;;
    *) echo "FAIL: acpi_ec resolves to '$acpi_ec_path' (expected …/updates/…)"; exit 1 ;;
esac
# same CRC32 invariant as msi-ec: the kernel XZ module decompressor rejects CRC64
if ! LC_ALL=C xz --list "$ACPI_EC_KO" 2>/dev/null | grep -q 'CRC32'; then
    echo "FAIL: $ACPI_EC_KO is not CRC32-compressed (kernel cannot decompress it at modprobe)"
    LC_ALL=C xz --list "$ACPI_EC_KO" 2>&1 || true
    exit 1
fi

# --- Phase 18: MControlCenter GUI (opt-in via ujust setup-msi) ---
MCC_REPO=/etc/yum.repos.d/teackot-msi.repo
if [ ! -f "$MCC_REPO" ]; then
    echo "FAIL: $MCC_REPO missing (teackot/msi COPR repofile not vendored)"
    exit 1
fi
if grep -q "^enabled=1" "$MCC_REPO"; then
    echo "FAIL: $MCC_REPO should be enabled=0 (runtime-enabled by ujust setup-msi)"
    exit 1
fi
# the GUI install is folded into setup-msi (no standalone install-mcontrolcenter)
grep -q 'rpm-ostree install -y mcontrolcenter' "$MX_JUSTFILE" || {
    echo "FAIL: setup-msi no longer layers mcontrolcenter in $MX_JUSTFILE"
    exit 1
}

# --- Phase 19: bootc install defaults (root-fs-type) ---
BOOTC_INSTALL_FILE=/usr/lib/bootc/install/01-bazzite-mx.toml
if [ ! -f "$BOOTC_INSTALL_FILE" ]; then
    echo "FAIL: $BOOTC_INSTALL_FILE missing"
    exit 1
fi
grep -qF 'root-fs-type = "btrfs"' "$BOOTC_INSTALL_FILE" || {
    echo "FAIL: $BOOTC_INSTALL_FILE does not set root-fs-type=btrfs"
    exit 1
}

# --- bazzite-63: mise bootstrap (profile.d activation + skel runtime config) ---
[ -f /etc/profile.d/99-mise.sh ] || { echo "FAIL: /etc/profile.d/99-mise.sh missing"; exit 1; }
[ -f /etc/skel/.config/mise/config.toml ] || { echo "FAIL: mise skel config.toml missing"; exit 1; }

# --- bazzite-63: GUI apps in the Flatpak default-install list ---
FLATPAK_INSTALL_LIST=/usr/share/ublue-os/bazzite/flatpak/install
for app in com.google.Chrome org.mozilla.Thunderbird me.proton.Pass \
           io.dbeaver.DBeaverCommunity org.remmina.Remmina \
           com.parsecgaming.parsec com.discordapp.Discord; do
    grep -qxF "$app" "$FLATPAK_INSTALL_LIST" || { echo "FAIL: $app not in Flatpak default-install"; exit 1; }
done

# --- bazzite-63: boot-time Flatpak installer (the list is never consumed at runtime by Bazzite) ---
[ -x /usr/libexec/bazzite63-flatpak-manager ] || {
    echo "FAIL: /usr/libexec/bazzite63-flatpak-manager missing or not executable"; exit 1; }
b63fm_state=$(systemctl is-enabled bazzite63-flatpak-manager.service 2>/dev/null || echo missing)
if [ "$b63fm_state" != "enabled" ]; then
    echo "FAIL: bazzite63-flatpak-manager.service not enabled (state=$b63fm_state)"
    exit 1
fi

# --- bazzite-63: Chrome as system-wide default browser (XDG default merged at build) ---
# Our entries are MERGED into Bazzite's own /etc/xdg/mimeapps.list by
# 68-flatpak-apps.sh (a static replacement file would clobber upstream
# entries like the Bazaar .flatpakref handler). No first-login hook: a hook
# racing the Flatpak install stamps itself before Chrome exists and never
# retries; users can still override per-user via ~/.config/mimeapps.list.
for entry in 'x-scheme-handler/http=com.google.Chrome.desktop' \
             'x-scheme-handler/https=com.google.Chrome.desktop' \
             'text/html=com.google.Chrome.desktop' \
             'application/xhtml+xml=com.google.Chrome.desktop'; do
    grep -qxF "$entry" /etc/xdg/mimeapps.list || {
        echo "FAIL: /etc/xdg/mimeapps.list missing '$entry'"; exit 1; }
done
# Canary against clobbering upstream defaults: Bazzite ships the Bazaar
# .flatpakref association in the same file — it must survive our merge.
grep -q '^application/vnd\.flatpak\.ref=' /etc/xdg/mimeapps.list || {
    echo "FAIL: upstream mimeapps entries were clobbered (flatpak.ref handler missing)"; exit 1; }
[ ! -e /usr/share/ublue-os/user-setup.hooks.d/21-bazzite-63-default-browser.sh ] || {
    echo "FAIL: stale default-browser hook shipped alongside the XDG default"; exit 1; }

# --- bazzite-63: removed integrations are gone ---
[ ! -f /etc/yum.repos.d/mozilla.repo ] || { echo "FAIL: mozilla.repo should be removed"; exit 1; }
! rpm -q firefox &> /dev/null || { echo "FAIL: firefox RPM should not be installed (Firefox stays Flatpak)"; exit 1; }

echo "bazzite-63 smoke tests OK."
echo "::endgroup::"
