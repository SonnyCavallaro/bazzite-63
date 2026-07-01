# Divergences from bazzite-mx

What this image changes over `ghcr.io/matrixdj96/bazzite-mx:stable`, one entry per feature, each
with its source. What bazzite-mx itself changes over Bazzite, and why, is its own
[`docs/divergences.md`](https://github.com/MatrixDJ96/bazzite-mx/blob/main/docs/divergences.md):
every entry there holds here too unless an entry below says otherwise.

Contents: layered on bazzite-mx's signed image · identity and signing · the host helpers ·
Firefox as a Flatpak.

## Layered on bazzite-mx's signed image

One image, built `FROM ghcr.io/matrixdj96/bazzite-mx:stable`. bazzite-mx publishes its plain
flavour, for AMD and Intel graphics, and this image follows that one; its two NVIDIA flavours
are not bases here. The base's `:stable` is resolved to a digest by `resolve-base.sh` and
verified by `verify-base.sh`: `cosign verify --key base-cosign.pub` on the digest, where
`base-cosign.pub` is bazzite-mx's `cosign.pub`. A tag is refused, since the signature is on the
digest and a tag could move between the check and the build.

bazzite-mx publishes `:stable` only, so the image has one stream. The weekly trigger runs four
hours after bazzite-mx's own (Sunday 07:20 UTC against 03:20), so a weekly release of this
image normally sits on that week's base; the upstream watcher catches a base that moved at any
other time ([`workflow.md`](workflow.md) § The weekly trigger and the upstream watcher).

The build scripts, the libraries and the CI scripts are bazzite-mx's, cut to what an image on
top of it needs: the kernel modules, the hook framework and the packages bazzite-mx installs
are in the base and are not rebuilt here.

## Identity and signing

`10-image-info.sh` names the image `bazzite-63`, vendor `sonnycavallaro`, in `image-info.json`,
`os-release` and the KDE About page; `base-version` is the version bazzite-mx's own
`image-info.json` gives, its release tag. The logo label points at bazzite-mx's
`site/logo.svg`: the image has no site of its own.

`11-image-signing.sh` adds the scope `ghcr.io/sonnycavallaro` to `/etc/containers/policy.json`
as `sigstoreSigned` with this repository's `cosign.pub`, next to the base's
`ghcr.io/matrixdj96` scope, which stays: the host verifies its own updates against this key, and
anything it pulls from bazzite-mx against bazzite-mx's. `registries.d/sonnycavallaro.yaml` turns
on the sigstore attachments for the new scope (`containers-registries.d(5)`).

## The host helpers

bazzite-mx ships `ujust migrate`, `ujust verify-host` and the library they share,
`/usr/lib/bazzite-mx/host.sh`, all naming `ghcr.io/matrixdj96`. On this image they would send
a host to bazzite-mx's registry and check bazzite-mx's scope. `12-host-helpers.sh` renames the
scope and its `registries.d` file to this image's in the three files, fixtures included, after
checking that each line it relies on is there exactly once; everything else in the helpers is
bazzite-mx's, apart from the browser items of § Firefox as a Flatpak. What they check and do is
bazzite-mx's
[`docs/migration.md`](https://github.com/MatrixDJ96/bazzite-mx/blob/main/docs/migration.md);
what differs on this image is [`migration.md`](migration.md).

## Firefox as a Flatpak

bazzite-mx installs Fedora's Firefox RPM, copies Bazzite's Firefox defaults into it and denies
the Firefox Flatpak in the base's Flatpak filter: its `40-desktop-apps.sh`, and the section
Desktop applications of its
[`docs/divergences.md`](https://github.com/MatrixDJ96/bazzite-mx/blob/main/docs/divergences.md).
This image goes back to Bazzite's choice, the Flatpak `org.mozilla.firefox`, the first entry of
Bazzite's default list `/usr/share/ublue-os/bazzite/flatpak/install`.

`40-firefox-flatpak.sh` removes `firefox` and `firefox-langpacks` and the directory the copied
defaults leave behind, `/usr/lib64/firefox`, and drops the line `deny org.mozilla.firefox/*`
from `/usr/share/ublue-os/flatpak-blocklist`, the filter `bazzite-flatpak-manager` sets on
Flathub. It also rewrites the two places bazzite-mx's helpers treat the RPM as the browser:
`verify-host`'s `check_flatpaks`, which reported a Firefox Flatpak beside the RPM as a leftover,
now reports the Flatpak as the browser and its absence as an `INFO:` line; `migrate`'s step 8
no longer prints the copy of a Flatpak profile into the RPM's. Each edit first requires its
anchor exactly once.
