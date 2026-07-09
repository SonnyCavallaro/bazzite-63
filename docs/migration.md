# Bringing a host onto this image

A host reaches the signed origin of `ghcr.io/sonnycavallaro/bazzite-63` through `ujust migrate`
and is re-checked with `ujust verify-host`. Both are bazzite-mx's recipes, pointed at this
image's registry ([`divergences.md`](divergences.md) § The host helpers): their steps, their
checks and the meaning of each `FAIL:` line are bazzite-mx's
[`docs/migration.md`](https://github.com/MatrixDJ96/bazzite-mx/blob/main/docs/migration.md),
read with `ghcr.io/sonnycavallaro/bazzite-63` wherever it names `ghcr.io/matrixdj96/<image>`.
This page holds what differs.

Contents: the first rebase · what differs from bazzite-mx's procedure.

## The first rebase

A signed pull is checked against the policy of the deployment that runs it, and no image but
this one carries the `ghcr.io/sonnycavallaro` scope: a stock Bazzite host and a bazzite-mx host
alike reach the image once through the unsigned transport. Secure Boot has to be off first
(`bootctl status`), the base's modules being unsigned.

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/sonnycavallaro/bazzite-63:stable
systemctl reboot
ujust migrate                 # plan: read-only, prints what apply would do
ujust migrate apply           # every change but step 2 asks first; TAG defaults to stable
systemctl reboot
ujust verify-host
```

A bazzite-mx host has already been through bazzite-mx's own migration, so `migrate apply` on it
mostly rebases onto the signed transport: no layered package, `fstab` row or residue is left to
clean. A Bazzite host gets every step, and the `fstab` and local-RPM cautions of bazzite-mx's
§ The first rebase goes through the unsigned transport apply before the rebase above.

## What differs from bazzite-mx's procedure

- The image is one, for AMD and Intel graphics. On a machine with an NVIDIA GPU on the bus,
  `verify-host` prints `NVIDIA GPU present but the image is bazzite-63` and names a bazzite-mx
  NVIDIA flavour: no image of this repository fixes that line.
- The origin `verify-host` requires is
  `ostree-image-signed:docker://ghcr.io/sonnycavallaro/bazzite-63:stable`, and the scope it
  reads in `policy.json` is `ghcr.io/sonnycavallaro`, with
  `/etc/containers/registries.d/sonnycavallaro.yaml`.
- Chrome is the browser and Firefox leaves the image ([`divergences.md`](divergences.md) §
  Google Chrome, the default browser). `verify-host` prints
  `OK: no Chrome Flatpak (the RPM is the image's browser)`, or an `INFO:` line with the profile
  copy while a Chrome Flatpak is installed beside the RPM, and `migrate`'s step 8 prints the
  same copy. On a host coming from bazzite-mx the Firefox RPM's profile stays in `~/.mozilla`
  or `~/.config/mozilla`; to keep Firefox, install its Flatpak
  (`flatpak install flathub org.mozilla.firefox`) and copy the profile over before its first
  start:

  ```bash
  app=~/.var/app/org.mozilla.firefox
  [ -e "$app/.mozilla" ] || [ ! -d ~/.mozilla ] || { mkdir -p "$app" && cp -a ~/.mozilla "$app/"; }
  [ -e "$app/config/mozilla" ] || [ ! -d ~/.config/mozilla ] \
      || { mkdir -p "$app/config" && cp -a ~/.config/mozilla "$app/config/"; }
  ```

- A dated tag is one of this repository's releases, kept by its own retention
  ([`workflow.md`](workflow.md) § GHCR retention).
