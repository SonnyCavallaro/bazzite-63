# vim: set ft=make :
# The image's own recipes, imported after bazzite-mx's by 70-justfile.sh,
# which refuses a name defined twice.

# Install or update the default Flatpak set: Bazzite's list and this image's apps.
[group("apps")]
install-default-flatpaks ACTION="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    OPTION="{{ ACTION }}"
    HELPER=/usr/libexec/bazzite-63-flatpak-manager

    if [ "$OPTION" == "help" ]; then
      echo "Usage: ujust install-default-flatpaks"
      echo "Installs from Flathub, or updates, every Flatpak of Bazzite's default list,"
      echo "Bazzite's apps first, with this image's after them, one ref at a time. Nothing"
      echo "installs at boot; run it again to retry a ref that failed. Remove what you do"
      echo "not want afterwards."
      exit 0
    fi

    if [[ $(id -u) -eq 0 ]]; then
      echo "Please do not run this command as root"
      exit 1
    fi

    if [ "$OPTION" != "" ]; then
      echo "Unknown option: $OPTION (ujust install-default-flatpaks help)"
      exit 1
    fi

    sudo "$HELPER" install
