# Divergences from bazzite-mx

What this image changes over `ghcr.io/matrixdj96/bazzite-mx:stable`, one entry per feature, each
with its source. What bazzite-mx itself changes over Bazzite, and why, is its own
[`docs/divergences.md`](https://github.com/MatrixDJ96/bazzite-mx/blob/main/docs/divergences.md):
every entry there holds here too unless an entry below says otherwise.

Contents: layered on bazzite-mx's signed image · identity and signing · the host helpers ·
Firefox out of the image · Google Chrome, the default browser · the
default Flatpak set, on demand · Konsole opens PowerShell.

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
bazzite-mx's, apart from the browser items of § Google Chrome, the default browser. What they
check and do is bazzite-mx's
[`docs/migration.md`](https://github.com/MatrixDJ96/bazzite-mx/blob/main/docs/migration.md);
what differs on this image is [`migration.md`](migration.md).

## Firefox out of the image

bazzite-mx installs Fedora's Firefox RPM, copies Bazzite's Firefox defaults into it and denies
the Firefox Flatpak in the base's Flatpak filter: its `40-desktop-apps.sh`, and the section
Desktop applications of its
[`docs/divergences.md`](https://github.com/MatrixDJ96/bazzite-mx/blob/main/docs/divergences.md).
This image drops Firefox: Chrome is its browser (§ Google Chrome, the default browser), and
Firefox stays one `flatpak install` away, as Bazzite's Flatpak `org.mozilla.firefox`.

`40-firefox-flatpak.sh` removes `firefox` and `firefox-langpacks` and the directory the copied
defaults leave behind, `/usr/lib64/firefox`, and drops the line `deny org.mozilla.firefox/*`
from `/usr/share/ublue-os/flatpak-blocklist`, the filter `bazzite-flatpak-manager` sets on
Flathub. Each edit first requires its anchor exactly once.

## Google Chrome, the default browser

Chrome is a system RPM, `google-chrome-stable` from Google's own repository, present for every
user and set as the default web browser. The repository is vendored as
`system_files/etc/yum.repos.d/google-chrome.repo`, the stanza the RPM's `%post` writes
(https://www.google.com/linuxrepositories/) with `enabled=0` and the key read from
`/etc/pki/rpm-gpg/RPM-GPG-KEY-google-chrome`, whose fingerprint `lib/gpg.sh` pins as read from
`dl.google.com/linux/linux_signing_key.pub`.

The RPM keeps itself updated on a mutable system: its `%post` adds the repository and its daily
cron re-enables it. On an image dnf never updates the package, so `41-chrome.sh` writes
`/etc/default/google-chrome` with `repo_add_once=false` and `repo_reenable_on_distupgrade=false`
before the install, the two knobs the `%post` and the cron read, removes
`/etc/cron.daily/google-chrome` and puts the vendored repository file back after the `%post`.
Chrome moves with the image's releases.

The payload unpacks under `/opt/google`, which a host's `/var` holds: the script moves it to
`/usr/lib/opt/google` and `/usr/lib/tmpfiles.d/bazzite-63-opt.conf` links `/var/opt/google`
back at boot, so the paths baked into the wrapper resolve. `/etc/xdg/mimeapps.list` names
`google-chrome.desktop` for `http`, `https`, `text/html` and `application/xhtml+xml` in the
base's `[Default Applications]` group, whose other entries stay; a user's own
`~/.config/mimeapps.list` still wins (XDG MIME Applications Associations specification).

Chrome's Flatpak, `com.google.Chrome`, is denied in the base's Flatpak filter, the way
bazzite-mx denies Firefox's beside its RPM: `bazzite-flatpak-manager` points Flathub's filter
at `/usr/share/ublue-os/flatpak-blocklist` with `flatpak remote-modify --filter` when its
version or the image name changes, as the rebase onto this image does
(flatpak-remote-modify(1)); a host that already has the Flatpak keeps it. `41-chrome.sh` also
turns bazzite-mx's helpers from Firefox to Chrome: `verify-host`'s `check_flatpaks` reports a
Chrome Flatpak beside the RPM as an `INFO:` line with the profile copy, and `migrate`'s step 8
prints that copy, from `~/.var/app/com.google.Chrome/config/google-chrome` to
`~/.config/google-chrome`, while the Flatpak is installed; `verify-host`'s help in
`95-bazzite-mx.just` names the Chrome Flatpak. Each edit first requires its anchor exactly
once.

## The default Flatpak set, on demand

The image's other GUI apps are Flatpaks, which update in place without a rebuild or a reboot:
Thunderbird, Proton Pass, DBeaver, Remmina, Parsec and Discord (`org.mozilla.thunderbird`,
`me.proton.Pass`, `io.dbeaver.DBeaverCommunity`, `org.remmina.Remmina`,
`com.parsecgaming.parsec`, `com.discordapp.Discord`). `42-flatpak-apps.sh` appends each to
Bazzite's default list, `/usr/share/ublue-os/bazzite/flatpak/install`, after Bazzite's own
entries and once, and drops from the list Firefox (§ Firefox out of the image) and the
VulkanLayer runtimes, which Bazzite pins there to 23.08, against 25.08 in its ISO's
`installer/kde_flatpaks/flatpaks`: neither is this image's choice. The app ids go alone into
`/usr/share/bazzite-63/flatpak-apps` too.

Nothing in Bazzite reads that list any more: its ISO installs `installer/kde_flatpaks/flatpaks`
(`installer/build.sh`), and `bazzite-flatpak-manager` stopped reading it in bazzite commit
6c24e91c, so a host that rebased onto the image never gets it. `ujust install-default-flatpaks`
runs `bazzite-63-flatpak-manager install` through sudo: one
`flatpak install --system --or-update flathub <ref>` per entry, in the list's order, so a ref
Flathub renamed or dropped prints a `WARN:` line and the others still install; the run exits 1
when one failed, and a second run retries it. Nothing installs at boot: the set is the user's to
take, and what they do not want they remove afterwards.

`70-justfile.sh` imports this image's recipe file, `96-bazzite-63.just`, after bazzite-mx's
recipes, and refuses a name defined twice ([`conventions.md`](conventions.md) § ujust recipes).

## Konsole opens PowerShell

Konsole's default profile is `Powershell.profile` (`/etc/skel/.local/share/konsole/`), named by
the skel `konsolerc`. Its command runs `/home/linuxbrew/.linuxbrew/bin/pwsh` when it exists and
`bash -l` otherwise: pwsh is the host's, installed into Homebrew by `brew install powershell`,
so a host without it still opens a working terminal. profile.ps1 drops the `DOTNET_ROOT`
Homebrew's pwsh launcher exports for its own dotnet before it activates mise, so `dotnet` and
`mise install` in pwsh keep mise's root.

pwsh reads its own profile and never `/etc/profile.d`
(PowerShell's `about_Profiles`),
so the skel
`.config/powershell/profile.ps1`, which replaces bazzite-mx's in a new home, wires what bash
gets from there: Homebrew's `bin` and `sbin` last on `PATH`, where `/etc/profile.d/brew.sh` puts
them, and `mise activate pwsh`, the role of
bazzite-mx's `/etc/profile.d/mise.sh` for bash. It keeps the Windows-style Ctrl+C and Ctrl+V of
PSReadLine on `wl-copy` and `wl-paste`, which the base ships. Each block does nothing until its
tool exists.

`/etc/skel` reaches only a new home ([`gotchas.md`](gotchas.md) § A skel file reaches no account
that already exists). bazzite-mx's login hook `12-bazzite-mx-copy-paste.sh` seeds `profile.ps1`
into an older home that has none, and `45-konsole-profile.sh` fails the build on a base whose
hook no longer does. This image's hook `13-bazzite-63-konsole-profile.sh` copies the Konsole
profile when the home has none and writes `DefaultProfile` with `kwriteconfig6` only when
`konsolerc` names no profile, so a profile the user chose stays.
