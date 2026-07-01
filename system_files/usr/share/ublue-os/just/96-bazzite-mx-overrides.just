# vim: set ft=make :
#
# 96-bazzite-mx-overrides.just — bazzite-63 OVERRIDE delle recipe ujust
# upstream. Ogni recipe qui rimpiazza una recipe omonima di Bazzite, che
# `build_files/mx/55-justfile-reconcile.sh` espunge chirurgicamente dai file
# upstream al build (manifest recipe→file). Le recipe net-new (non-override)
# stanno invece in 95-bazzite-mx.just.

# setup-virtualization — bazzite-63 OVERRIDE of Bazzite's upstream
# virtualization recipe.
#
# Bazzite's own `setup-virtualization` is flatpak-only (commit 8f1c46b4):
# `virt-on` installs the org.virt_manager.virt-manager flatpak (+ QEMU
# extension) whenever `flatpak info` misses it — on bazzite-63 that branch
# would always fire, duplicating the build-time RPM and fighting the
# flatpak blocklist. The full recipe (VFIO / kvmfr / usbhp / group) lives
# on in bazzite-dx's 84-bazzite-virt.just override, which this file tracks.
# Relative to that bazzite-dx recipe, this one drops:
#   - the `! rpm -q virt-manager` gate and the `flatpak install
#     org.virt_manager.virt-manager` line (RPM is the source of truth;
#     the flatpak is blocklisted in 21-virt-manager-flatpak-exclude.sh);
#   - the kvm.ignore_msrs / kvm.report_ignored_msrs kargs (shipped as
#     module options in /usr/lib/modprobe.d/bazzite-63-kvm.conf);
#   - the `bazzite-libvirtd-setup.service` enable (libvirtd.service is
#     enabled at build time in 20-virtualization.sh);
#   - the virt-off `flatpak uninstall` path;
#   - the `kvm.report_ignored_msrs` karg sentinel gating vfio-on (that
#     "virt setup ran" marker: the KVM tuning here is modprobe.d options,
#     so no such karg exists and vfio-on proceeds unconditionally).
# The VFIO / kvmfr / usbhp / group blocks are kept verbatim from
# bazzite-dx, including its `/usr/libexec/bazzite-dx-kvmfr-setup` helper,
# vendored byte-identical in system_files/usr/libexec/.

# Setup and configure virtualization and vfio
[group("system")]
setup-virtualization ACTION="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    if [[ $(id -u) -eq 0 ]]; then
      echo "Please do not run this command as root"
      exit 1
    fi
    # Check if we are running on a Steam Deck
    if /usr/libexec/hwsupport/valve-hardware; then
      echo "${red}${b}WARNING${n}: Virtualization is not properly supported on Steam Deck by Valve"
      echo "Use at your own risk and performance may not be ideal."
    fi
    if [ "$(systemctl is-enabled libvirtd.service)" == "disabled" ]; then
      echo "${b}libvirtd${n} service is ${red}disabled${n}!"
      echo "${green}enabling${n} and starting libvirtd"
      echo "If virt-manager says libvirtd.sock is not available after a big update, re-run this command."
      sudo systemctl enable --now libvirtd 2> /dev/null
      echo "Press ESC if you want to exit and do not need to do anything"
    fi
    OPTION={{ ACTION }}
    if [ "$OPTION" == "help" ]; then
      echo "Usage: ujust setup-virtualization <option>"
      echo "  <option>: Specify the quick option to skip the prompt"
      echo "  Use 'virt-on' to apply per-user virt setup (ACL + libvirt hooks)"
      echo "  Use 'group' to select Add $USER to libvirt group"
      echo "  Use 'vfio-on' to select Enable VFIO drivers"
      echo "  Use 'vfio-off' to select Disable VFIO drivers"
      echo "  Use 'kvmfr' to select Autocreate Looking-Glass shm"
      echo "  Use 'usbhp-on' to select Enable SPICE USB hot plugging"
      echo "  Use 'usbhp-off' to select Disable SPICE USB hot plugging"
      echo "  NOTE: KVM options (kvm.ignore_msrs / kvm.report_ignored_msrs) and"
      echo "        libvirtd.service are pre-applied at build time on"
      echo "        bazzite-63 — no virt-off path; uninstall the image"
      echo "        if you don't want virt support."
      exit 0
    elif [ "$OPTION" == "" ]; then
      echo "${bold}Virtualization Setup${normal}"
      echo "NOTE: virt-manager (RPM), KVM options and libvirtd are pre-applied at build time."
      echo "      This recipe applies the per-user / per-host bits that"
      echo "      cannot be baked in (ACL, libvirt hooks, group, VFIO, ...)."
      OPTION=$(Choose \
        "Apply per-user virt setup" \
        "Add $USER to libvirt group" \
        "Enable VFIO drivers" \
        "Disable VFIO drivers" \
        "Enable kvmfr module" \
        "Enable USB hot plugging" \
        "Disable USB hot plugging" \
      )
    fi
    if [[ "${OPTION,,}" =~ (^apply[[:space:]]per-user|virt-on) ]]; then
        echo "Making sure swtpm-localca dir is writable by tss"
        # `swtpm-tools` ships /var/lib/swtpm-localca with mode 0750
        # tss:root by default; defensive re-apply in case a previous
        # tweak changed it.
        if [ ! -d "/var/lib/swtpm-localca" ]; then
          sudo mkdir /var/lib/swtpm-localca
        fi
        sudo chown tss /var/lib/swtpm-localca
        sudo restorecon -rv /var/lib/libvirt
        sudo restorecon -rv /var/log/libvirt
        echo "Giving qemu access to read ISO files from $HOME"
        sudo setfacl -m u:qemu:rx $HOME
        if sudo test ! -f "/etc/libvirt/hooks/qemu"; then
          echo "Adding libvirt qemu hooks"
          sudo wget 'https://raw.githubusercontent.com/PassthroughPOST/VFIO-Tools/master/libvirt_hooks/qemu' -O /etc/libvirt/hooks/qemu
          sudo chmod +x /etc/libvirt/hooks/qemu
          sudo grep -A1 -B1 "# Add" /etc/libvirt/hooks/qemu | sed 's/^# //g'
          if sudo test ! -d "/etc/libvirt/hooks/qemu.d"; then
            sudo mkdir /etc/libvirt/hooks/qemu.d
          fi
        fi
        echo 'Per-user virt setup applied.'
    elif [[ "${OPTION,,}" =~ (^enable[[:space:]]vfio|vfio-on) ]]; then
      # Check if we are running on a Steam Deck
      if /usr/libexec/hwsupport/valve-hardware; then
        echo "IOMMU is not supported on Steam Deck"
        exit 0
      fi
      echo "Enabling VFIO..."
      CPU_VENDOR=$(grep "vendor_id" "/proc/cpuinfo" | uniq | awk -F": " '{ print $2 }')
      VENDOR_KARG="unset"
      rpm-ostree initramfs --enable
      if [[ ${CPU_VENDOR} == "AuthenticAMD" ]]; then
        VENDOR_KARG="amd_iommu=on"
      elif [[ ${CPU_VENDOR} == "GenuineIntel" ]]; then
        VENDOR_KARG="intel_iommu=on"
      fi
      if [[ ${VENDOR_KARG} == "unset" ]]; then
        echo "Failed to get CPU vendor, exiting..."
        exit 1
      else
        rpm-ostree kargs \
          --append-if-missing="${VENDOR_KARG}" \
          --append-if-missing="iommu=pt" \
          --append-if-missing="rd.driver.pre=vfio-pci" \
          --append-if-missing="vfio_pci.disable_vga=1"
        echo "VFIO will be enabled on next boot, make sure you enable IOMMU, VT-d or AMD-v in your BIOS!"
        echo "Please understand that since this is such a niche use case, support will be very limited!"
        echo 'Use the command "ls-iommu -grk" to get iommu information about your GPUs, use the "--help" flag for more options'
        echo ""
        echo "${b}Systems with multiple GPUs${n}"
        echo "Bind your unused/second GPU device ids to the vfio driver by running"
        echo 'rpm-ostree kargs --append-if-missing="vfio_pci.ids=xxxx:yyyy,xxxx:yyzz"'
        echo "You will require a $(Urllink "https://www.amazon.com/s?k=hdmi+displayport+dummy+plug" "Dummy HDMI/DisplayPort plug (Ghost Adapter)") or hook the GPU"
        echo "to a separate monitor input in order to turn the GPU on when starting the VM."
        echo "NOTE: Your second GPU should be as different as possible from your main GPU and will not be usable by the host after you bind it to the vfio driver!"
        echo ""
        echo "${b}Systems with 1 GPU${n}"
        echo "Once rebooted you can continue setting up whatever scripts and hooks you need"
        echo "to get Single GPU passthrough working, however ${u}you will be on your own${n}."
        echo "${b}Do not ask for support for setting up Single GPU Passthrough, we can not help you!${n}"
      fi
    elif [[ "${OPTION,,}" =~ (^disable[[:space:]]vfio|vfio-off) ]]; then
      # Check if we are running on a Steam Deck
      if /usr/libexec/hwsupport/valve-hardware; then
        echo "IOMMU is not supported on Steam Deck"
        exit 0
      fi
      echo ""
      echo "Make sure you have ${b}disabled autostart of all VMs using VFIO${n} before continuing!"
      CONFIRM=$(Choose Cancel Continue)
      if [ "$CONFIRM" == "Continue" ]; then
        echo "Disabling VFIO..."
        VFIO_IDS="$(rpm-ostree kargs | sed -E 's/.+(vfio_pci.ids=.+\s)/\1/' | awk '{ print $1 }' | grep vfio_pci.ids)"
        VFIO_IDS_KARG=""
        if [ -n "$VFIO_IDS" ]; then
          echo "Found VFIO ids in kargs, adding the below line to removal list"
          echo "$VFIO_IDS"
          VFIO_IDS_KARG="--delete-if-present=\"$VFIO_IDS\""
        fi
        KVMFR_VAL="$(rpm-ostree kargs | sed -E 's/.+(kvmfr.static_size_mb=.+\s)/\1/' | awk '{ print $1 }' | grep kvmfr.static_size_mb)"
        KVMFR_KARG=""
        if [ -n "$KVMFR_VAL" ]; then
          echo "Found KVMFR static_size_mb in kargs, adding the below line to removal list"
          echo "$KVMFR_VAL"
          KVMFR_KARG="--delete-if-present=\"$KVMFR_VAL\""
        fi
        echo "Removing deprecated dracut modules"
        sudo rm /etc/dracut.conf.d/vfio.conf
        sudo rm /etc/modprobe.d/kvmfr.conf
        rpm-ostree kargs \
        --delete-if-present="iommu=pt" \
        --delete-if-present="iommu=on" \
        --delete-if-present="amd_iommu=on" \
        --delete-if-present="intel_iommu=on" \
        --delete-if-present="rd.driver.pre=vfio-pci" \
        --delete-if-present="vfio_pci.disable_vga=1" \
        --delete-if-present="vfio_pci.disable_vga=0" \
        $VFIO_IDS_KARG \
        $KVMFR_KARG
      fi
    elif [[ "${OPTION,,}" =~ kvmfr ]]; then
      sudo /usr/libexec/bazzite-dx-kvmfr-setup
    elif [[ "${OPTION,,}" =~ (^enable[[:space:]]usb|usbhp-on) ]]; then
      echo "Adding udev rule for USB devices"
      sudo bash -c 'cat << USBHP_UDEV > /etc/udev/rules.d/72-usbhp.rules
    ACTION=="add" SUBSYSTEM=="usb", TAG+="uaccess"
    USBHP_UDEV'
    elif [[ "${OPTION,,}" =~ (^disable[[:space:]]usb|usbhp-off) ]]; then
      sudo bash -c 'rm /etc/udev/rules.d/72-usbhp.rules'
    elif [[ "${OPTION,,}" =~ group ]]; then
      if ! grep -q "^libvirt" /etc/group; then
        grep '^libvirt' /usr/lib/group | sudo tee -a /etc/group > /dev/null
      fi
      sudo usermod -aG libvirt $USER
    fi

# setup-sunshine — bazzite-63 OVERRIDE of Bazzite's upstream Sunshine recipe.
#
# bazzite-63 ships Sunshine as a system RPM (build_files/mx/65-sunshine.sh,
# community pvermeer/sunshine COPR) with the user unit
# `app-dev.lizardbyte.app.Sunshine.service` (alias `sunshine.service`).
# Upstream's recipe (flatpak-flavored since commit e05b27f8, brew kept for
# the Deck-oriented `enable-beta` path) manages the
# dev.lizardbyte.app.Sunshine flatpak: on bazzite-63 its `enable`
# would install a flatpak duplicating the RPM. This recipe drops the
# flatpak/brew/Cellar handling, `enable-beta`, `update`, and `uninstall`
# (Sunshine is part of the base image; removal is `rpm-ostree override
# remove sunshine`, noted in `help`), keeping `status`, `enable`,
# `disable`, `portal`, `help`.

# Setup and configure Sunshine Game Streaming host. Options: status | enable | disable | portal | help
[group("gaming")]
setup-sunshine ACTION="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    OPTION={{ ACTION }}
    SUNSHINE_UNIT="app-dev.lizardbyte.app.Sunshine.service"

    get_status_token() {
      local service_state
      service_state="$(systemctl is-enabled --user $SUNSHINE_UNIT 2>/dev/null || true)"
      if [[ "$service_state" == "enabled" ]]; then
        echo "enable"
      else
        echo "disable"
      fi
    }

    if [ "$OPTION" == "help" ]; then
      echo "Usage: ujust setup-sunshine <option>"
      echo "  <option>: Specify the quick option to skip the prompt"
      echo "  Use 'status' to print the current service state"
      echo "  Use 'enable' to enable+start the Sunshine user service"
      echo "  Use 'disable' to stop+disable the Sunshine user service"
      echo "  Use 'portal' to open the Sunshine management portal in a browser"
      echo "  Use 'exit' to exit without making changes"
      echo ""
      echo "${b}Notes${n}:"
      echo "  - Sunshine is shipped at build time as a system RPM (community pvermeer/sunshine COPR)."
      echo "    Updates flow automatically with ${b}bootc upgrade${n} / ${b}ujust update${n}."
      echo "  - To remove Sunshine entirely: ${b}rpm-ostree override remove sunshine${n}, then reboot."
      echo "  - Default service state on a fresh image: ${b}disabled${n} (Aurora pattern)."
      echo "  - Port forwarding for streaming over the internet: 47984 (HTTPS), 47989 (HTTP),"
      echo "    47998-48000/UDP (video/audio/control), 48010 (RTSP)."
      exit 0
    elif [ "$OPTION" == "status" ]; then
      echo "$(get_status_token)"
      exit 0
    elif [ "$OPTION" == "" ]; then
      case "$(get_status_token)" in
        "enable")
          SERVICE_STATE="${green}${b}Enabled${n}"
          ;;
        *)
          SERVICE_STATE="${yellow}${b}Disabled${n}"
          ;;
      esac
      echo "Sunshine user service is $SERVICE_STATE"
      OPTION=$(Choose "Enable" "Disable" "Open Portal" "Exit")
    fi

    if [[ "${OPTION,,}" =~ ^enable ]]; then
      echo "Enabling Sunshine user service ($SUNSHINE_UNIT)..."
      systemctl --user enable --now "$SUNSHINE_UNIT"
      echo ""
      echo "Sunshine is now ${green}${b}running${n}."
      echo "Open the management portal: ${b}ujust setup-sunshine portal${n} (or https://localhost:47990)"
      echo "First-time setup will ask you to create a credential pair to pair Moonlight clients."
    elif [[ "${OPTION,,}" =~ ^disable ]]; then
      echo "Disabling Sunshine user service ($SUNSHINE_UNIT)..."
      systemctl --user disable --now "$SUNSHINE_UNIT" || true
      echo "Sunshine is now ${yellow}${b}stopped${n}."
    elif [[ "${OPTION,,}" =~ ^(portal|open) ]]; then
      echo "Opening Sunshine management portal..."
      xdg-open https://localhost:47990
    elif [[ "${OPTION,,}" =~ ^exit ]]; then
      echo "Exiting without making changes."
      exit 0
    fi

# Install JetBrains Toolbox | https://www.jetbrains.com/toolbox-app/
#
# bazzite-63 OVERRIDE della recipe brew upstream (82-bazzite-apps.just).
# Upstream installa via Homebrew cask (ublue-os/tap → jetbrains-toolbox-linux);
# qui il metodo non-brew Aurora/Bluefin (bluefin PR #397, maturato in #2645 /
# aurora #581): risolve l'ultima build dalla JetBrains data-services API,
# scarica + verifica sha256 il tarball, installa in
# ~/.local/share/JetBrains/ToolboxApp/ e lancia (self-setup: desktop entry,
# auto-update). Nessun Homebrew, nessun Cellar. Gira come utente ($HOME) —
# niente sudo. jq è nell'immagine base.
[group("apps")]
install-jetbrains-toolbox:
    #!/usr/bin/bash
    set -eo pipefail
    pushd "$(mktemp -d)" >/dev/null
    echo "Resolving latest JetBrains Toolbox release..."
    curl -sSfL -o releases.json "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
    BUILD_VERSION=$(jq -r '.TBA[0].build' ./releases.json)
    DOWNLOAD_LINK=$(jq -r '.TBA[0].downloads.linux.link' ./releases.json)
    CHECKSUM_LINK=$(jq -r '.TBA[0].downloads.linux.checksumLink' ./releases.json)
    echo "Installing JetBrains Toolbox ${BUILD_VERSION}..."
    curl -sSfL -O "${DOWNLOAD_LINK}"
    curl -sSfL "${CHECKSUM_LINK}" | sha256sum -c
    tar zxf "jetbrains-toolbox-${BUILD_VERSION}.tar.gz"
    mkdir -p "${HOME}/.local/share/JetBrains/ToolboxApp/"
    mv "jetbrains-toolbox-${BUILD_VERSION}"/* "${HOME}/.local/share/JetBrains/ToolboxApp/"
    echo "Launching JetBrains Toolbox..."
    "${HOME}/.local/share/JetBrains/ToolboxApp/bin/jetbrains-toolbox" &> /dev/null &
