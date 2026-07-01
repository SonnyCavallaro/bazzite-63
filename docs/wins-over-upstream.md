# Wins over `bazzite-dx` upstream

bazzite-mx is a personal fork that aims to be **strictly better** than `ublue-os/bazzite-dx`
upstream by adopting Aurora-DX's build patterns and fixing concrete issues. **18 wins** are
documented below; they accumulate as each domain commit lands.

## Design philosophy

The product values that drive every win below:

- **Beat upstream, don't just track it.** Each domain aims to be strictly better than
  `bazzite-dx`; the aspiration is ≥1 real advantage per phase.
- **No opinionated defaults.** Stylistic choices (font, theme, formatter) are left to the
  user. AmyOS imposes choices — not our model; Bazzite-DX strips opinions — that *is* our
  model.
- **Skip when upstream does it better.** If Bazzite / Aurora-DX / AmyOS handle a domain
  better than we could, skipping is a win, not a forfeit (Phase 5 Cockpit is the canonical
  example — see [`workflow.md`](workflow.md)).

## 1. Strict repo isolation via `validate-repos.sh`

**Upstream**: no equivalent — bazzite-dx trusts that the install order leaves no third-party
repo enabled.

**Us**: `build_files/shared/validate-repos.sh` runs at the end of every build and hard-fails
if any file in the explicit `OTHER_REPOS` list (or any `_copr:*` / `_copr_*` /
`rpmfusion-*`) has `^enabled=1`, plus an informational catch-all sweep listing every other
`.repo` file so an unregistered third-party repo is visible in PR review.

**Why it matters**: a deployed `bootc upgrade` re-reads `/etc/yum.repos.d/`; a leftover
`enabled=1` on `docker-ce.repo` would silently pull docker package updates from docker.com
on every upgrade, breaking the reproducibility we promise.

## 2. `docker-ce.repo` vendored in git

**Upstream**: `dnf5 config-manager addrepo --from-repofile=https://download.docker.com/...`
fetched at build time, every time — no auditable diff in git if Docker changes the .repo
format / baseurl / gpgkey.

**Us**: `system_files/etc/yum.repos.d/docker-ce.repo` committed — single `[docker-ce]`
section with `enabled=0`, `gpgcheck=1`,
`gpgkey=https://download.docker.com/linux/fedora/gpg`. Any upstream change requires a
deliberate edit of the vendored file in a PR.

**Why it matters**: supply-chain auditability — a PR reviewer sees the exact trust anchor
for Docker installs without diffing against external state.

## 3. `swtpm` always installed

**Upstream**: bazzite-dx installs the virt block with `dnf5 --setopt=install_weak_deps=False`,
which skips `swtpm` because it is only recommended (not required) by libvirt.

**Us**: explicit `swtpm swtpm-tools` in `build_files/mx/20-virtualization.sh`.

**Why it matters**: Windows 11 VMs require a TPM 2.0 to install; without swtpm the user hits
a confusing "this PC doesn't meet the requirements" wall in virt-manager. Bazzite-DX users
have to layer it post-install.

## 4. Working virt stack out-of-the-box (vs. silently broken upstream recipe)

**Upstream**: Bazzite's `setup-virtualization` ujust recipe is gated on
`if ! rpm -q virt-manager | grep -P "^virt-manager-"`. On stock Bazzite (no RPM) it runs the
full `flatpak install …virt-manager` + `rpm-ostree kargs` + swtpm dir + libvirtd-enable
path; on Bazzite-DX the gate is also FALSE (the user layers the RPM themselves), so the
flatpak path runs and duplicates the eventual RPM install. Neither image enables
`libvirtd.service` at build — a fresh boot has the full virt stack, disabled.

**Us**: three-layer fix delivered together:

1. **Build-time enable** (`build_files/mx/20-virtualization.sh`): `systemctl enable
   libvirtd.service` at image build, so the service is `enabled` on first boot — pattern
   lifted from AmyOS, the only reference distro that gets this right out-of-the-box.
2. **Build-time kargs** (`system_files/usr/lib/bootc/kargs.d/01-bazzite-mx-virt.toml`):
   ships `kvm.ignore_msrs=1` + `kvm.report_ignored_msrs=0` so Windows 11 guests don't panic
   on unimplemented-MSR reads. Bootc applies these at deploy time.
3. **Recipe override** (`system_files/usr/share/ublue-os/just/84-bazzite-virt.just`):
   replaces Bazzite's `setup-virtualization`, dropping the `! rpm -q virt-manager` gate
   (always-broken on bazzite-mx since we ship the RPM), the `flatpak install …virt-manager`
   line (would duplicate the RPM), and the redundant kargs/libvirtd bits (done at build
   time). VFIO / kvmfr / USB-hot-plug / libvirt-group blocks kept verbatim for
   hardware-passthrough scenarios orthogonal to the basic stack.

Defense-in-depth: `build_files/mx/21-virt-manager-flatpak-exclude.sh` adds
`deny org.virt_manager.virt-manager/*` to `/usr/share/ublue-os/flatpak-blocklist` so
Discover/Bazaar hide the flatpak, and two cleanup hooks
(`16-bazzite-mx-virt-manager-flatpak-cleanup.sh` under both `system-setup.hooks.d/` and
`user-setup.hooks.d/`) `flatpak uninstall` any pre-existing namespace via `libsetup.sh
version-script`.

**Why it matters**: an installed-but-disabled virt stack is a surprise failure on first VM
creation. AmyOS enables libvirtd; Aurora-DX adds the flatpak; Bazzite has the most complete
recipe; **none** ship a working-on-first-boot stack plus a working VFIO recipe. Our single
image gives both: opening virt-manager from the launcher post-install just works.

## 5. VSCode `gpgcheck=1`

**Upstream**: bazzite-dx sets `gpgcheck=0` on the vscode repo with a
`FIXME: gpgcheck broken on newer rpm policies` comment.

**Us**: `system_files/etc/yum.repos.d/vscode.repo` ships `gpgcheck=1` — verified empirically
on Bazzite 44 / dnf5 5.x that the Microsoft .asc key (0xBE1229CF, fingerprint
BC528686B50D79E339D3721CEB3E94ADBE1229CF) imports cleanly during the first transaction
touching the repo.

**Why it matters**: actual signature verification of the `code` package on every install.
The bazzite-dx FIXME describes an earlier dnf/rpm version and has aged out; we catch the fix.

## 6. `git-credential-libsecret` shipped (Aurora-only otherwise)

**Upstream**: Aurora base ships `git-credential-libsecret`; Bazzite base does NOT, and
Bazzite-DX inherits the gap.

**Us**: `build_files/mx/35-git-tools.sh` installs `git-credential-libsecret` so git
authentication via the system keyring works out-of-the-box.

**Why it matters**: GUI password prompts via the keyring instead of typing/pasting HTTPS
tokens on each push — standard modern git auth on Linux desktops, a day-1 UX upgrade.

## 7. VSCode `update.mode=none` atomic-correct default

**Upstream**: bazzite-dx ships the same setting plus opinionated font (Cascadia Code) +
theme defaults; AmyOS goes further with formatOnSave + Hack Nerd Font + zsh terminal default
and many style choices.

**Us**: `system_files/etc/skel/.config/Code/User/settings.json` is just
`{ "update.mode": "none" }` — the atomic-correctness fix only, no font/theme/formatter
opinion.

**Why it matters**: the fix is mandatory (VSCode's self-updater fights a read-only `/usr`);
the rest is the user's choice. Distros should not impose stylistic preferences — minimalism
is a feature.

## 8. `bcc-tools` shipped alongside `bcc`

**Upstream**: Aurora-DX (`build_files/dx/00-dx.sh:20`) and bazzite-dx
(`build_files/20-install-apps.sh:6`) install only `bcc` — the BPF Compiler Collection
**library** + Python bindings. The command-line tracing utilities (`execsnoop`, `opensnoop`,
`tcpconnect`, `biotop`, `runqlat`, etc.) live in `bcc-tools`, a separate ~2 MiB package that
neither distro installs.

**Us**: `build_files/mx/40-dev-cli-rpms.sh` installs both `bcc` and `bcc-tools`; the tools
land under `/usr/share/bcc/tools/<name>`.

**Why it matters**: "where's `execsnoop`?" is answered out of the box; on Aurora-DX or
bazzite-dx the user has to layer `bcc-tools` post-install. The 2 MiB cost is negligible.

## 9. `gh` pinned from the official release, checksum-verified

**Upstream**: bazzite-dx does not install gh at all; Fedora's package trails the upstream
release by several minor versions.

**Us**: `build_files/mx/41-dev-cli-pinned.sh` installs `gh` from GitHub's official release
tarball, pinned (`GH_VERSION=2.94.0`) and verified against the release's `sha256` checksums
file before `install -m 0755` into `/usr/bin/gh`. Same pattern covers `glab`, `shellcheck`,
and `shfmt`.

**Why it matters**: a pinned, checksum-verified binary is a reproducible version with no
third-party repo to isolate — nothing for the enabled-state invariant to police. Bumping is
a one-line auditable diff, and `gh` evolves quickly (new commands, GitHub API features);
lagging by 5+ versions on a "DX" distro is a poor signal.

## 10. Firefox from Mozilla's official RPM (vs. Flatpak)

**Upstream**: Bazzite installs Firefox as a Flathub flatpak (`org.mozilla.firefox`) via its
default-install list.

**Us**: Firefox via Mozilla's RPM repo (`build_files/mx/61-firefox-rpm.sh`, `mozilla.repo`
vendored `enabled=0`), plus the flatpak excluded from default install and blocklisted from
Discover/Bazaar (`build_files/mx/62-firefox-flatpak-exclude.sh`), plus cleanup hooks
(`15-bazzite-mx-firefox-flatpak-cleanup.sh` under both `system-setup.hooks.d/` and
`user-setup.hooks.d/`) that uninstall any pre-existing per-system/per-user flatpak Firefox
on next boot/login.

**Why it matters**:

- Native messaging, system fonts, system policies, and system keyring integration work
  out-of-the-box — flatpak Firefox needs socket workarounds (xdg-desktop-portal-gtk,
  file-system access permissions, etc.) for several of these.
- One source of truth for security updates (Mozilla's release cycle, no flatpak runtime
  drifting from the base image).
- No accidental "two Firefoxes installed" surprise from Discover's "Install Firefox" button.

## 11. Zero-maintenance third-party GPG keys

**Upstream**: bazzite-dx and Aurora-DX vendor GPG keys statically under
`system_files/etc/pki/rpm-gpg/`; when upstream rotates a key the vendored copy goes stale
and installs start warning (or failing in strict mode).

**Us**:

- **RPM Fusion non-free** (`build_files/mx/63-rpmfusion-release.sh`): installs
  `rpmfusion-nonfree-release`, which ships keys for F44 / F45 / F46 / rawhide in a single
  rpm — future Bazzite rebases against newer Fedora pull the matching key for free. The
  `.repo` files come with the same package (we sed `enabled=0` after install for isolation).
- **1Password** (`build_files/mx/64-1password-key.sh`):
  `curl -fsSL https://downloads.1password.com/linux/keys/1password.asc` at build time —
  every CI build re-fetches the current key, so a rotation lands on the next build (~1h via
  the upstream watcher).

**Why it matters**: zero maintenance debt for key rotation. A stale vendored key is a slow
ticking bomb; we trade it for a per-build network call to the trust anchor (documented as
part of the "third-party `.repo` is `enabled=0`" isolation invariant).

## 12. Docker group + libvirt group via system-setup hook (with sysusers.d for docker)

**Upstream**: bazzite-dx-groups bundles its setup with several other concerns; Bazzite base
has no equivalent. More critically, both Aurora-DX and Bazzite-DX inherit the `docker-ce`
scriptlet gap: `groupadd --system docker` in the rpm postinstall scriptlet is SUPPRESSED on
rpm-ostree atomic systems (scriptlets are skipped to keep the OCI layer reproducible) — the
`docker` group never exists at runtime, the user is never added to it, and every
`docker run` requires sudo. Verified: neither ships a sysusers.d for docker.

**Us**: two-piece fix:

- `system_files/usr/share/ublue-os/system-setup.hooks.d/10-bazzite-mx-groups.sh` runs at
  first boot via the `ublue-system-setup.service` framework (idempotent via `libsetup.sh
  version-script`); appends `docker` + `libvirt` groups to `/etc/group` from
  `/usr/lib/group`, then `usermod -aG` for every wheel user.
- `system_files/usr/lib/sysusers.d/bazzite-mx-docker.conf`: a single `g docker -` line read
  by systemd-sysusers at sysinit.target (early in boot, before the group-adding hook) —
  creates the docker system group on every boot, exactly compensating the suppressed rpm
  scriptlet.

**Why it matters**: without this, `docker.socket` is enabled but the user can't `docker ps`
without `sudo`, and libvirt is similarly inaccessible — a UX regression bazzite-dx upstream
fixes only partially.

## 13. Idempotent justfile import + `_pkg_layered` reusable helper

**Upstream**: Bazzite-DX (`60-clean-base.sh:5`) and AmyOS (`install-apps.sh:107`) append
their `import` directive to Bazzite's master justfile **without** an idempotency check —
duplicates accumulate if the same script runs twice (e.g. during local pre-flights).

**Us**: `build_files/mx/55-justfile-import.sh` uses
`grep -qxF "$IMPORT_LINE" "$MASTER" || echo "$IMPORT_LINE" >> "$MASTER"` — appended only if
absent, side-effect-free re-runs. `95-bazzite-mx.just` ships a `_pkg_layered` helper recipe
that checks rpm-ostree overlay layer membership (not `rpm -q`, which sees base-image
packages too) and returns `yes`/`no` on stdout rather than via exit code — `just` always
emits `error: Recipe X failed on line N with exit code 1` when a sub-recipe exits non-zero,
even inside the caller's `if`; the stdout-as-boolean pattern keeps `install-*` output clean.

**Why it matters**: clean recipe UX, no spurious "error" lines on re-run, and a reusable
layering-check helper for any future `install-*` recipe.

## 14. VSCode extensions hardened against libsetup.sh state-before-body race

**Upstream**: Bazzite-DX has the same race in their vscode-extensions hook, unnoticed
because their hook has no failure mode as sensitive as ours; Aurora-DX dodges it by writing
state at the END of a custom libexec (no libsetup.sh).

**Race**: `libsetup.sh::version-script` writes the versioned state file BEFORE the hook body
runs. Under `set -euo pipefail`, a single failed command (transient marketplace timeout,
missing skel file, …) aborts the hook AFTER the state is committed → next login skips the
hook → silent permanent disable.

**Us**: in `11-bazzite-mx-vscode-extensions.sh` every `code --install-extension X` carries
`|| true` so failure is benign and the hook completes (state correctly reflects "I tried");
source paths (`/etc/skel/.config/Code/User/settings.json`) are guarded with `[ -e ... ]` so
a future skel removal doesn't trigger the trap.

**Why it matters**: a one-time login glitch (network blip fetching from the marketplace)
would otherwise silently disable the hook forever — the 3 expected extensions never
auto-install and the user never learns why.

## 15. `gparted` ships to fill the gap Bazzite leaves

**Upstream**: Bazzite **removes** `kde-partitionmanager` from their KDE base (commit
`378e524a`, Plasma 6.4 cleanup) with no replacement — the deployed image ships **no GUI
partition tool**, only CLI `parted` / `fdisk`. Bazzite's ISO installer hook installs gparted
only into the live ISO environment.

**Us**: `build_files/mx/60-desktop-apps.sh` ships `gparted` (~9 MiB) as a universal
partition manager. Provenance reinforced by AmyOS, which ships gparted in their DX-style
list.

**Why it matters**: a daily-driver workstation needs a GUI partition tool; discovering the
gap at the moment of need means dropping to terminal `parted` or rebooting from USB.

## 16. Sunshine reintegrated as system RPM (vs. Bazzite's brew migration)

**Upstream**: Bazzite shipped Sunshine as a system RPM from the `lizardbyte/beta` COPR until
commit `079fa8ad` (2026-03-26), then removed it citing "numerous ignored issues about their
stable repo not supporting Fedora 43 these last 6 months". Their replacement is a
Homebrew-based `setup-sunshine` recipe (commit `aa6ec9da`): the user installs Homebrew
first, then `brew install sunshine` downloads and *compiles* a 30+ MiB binary per machine.

**Us**: `build_files/mx/65-sunshine.sh` installs Sunshine as a system RPM via
`lizardbyte/stable` — the same COPR Aurora uses, carrying current Fedora 44 builds. Three
pieces:

1. `copr_install_isolated "lizardbyte/stable" "sunshine"` — the same isolated-COPR pattern
   used for `ublue-os-libvirt-workarounds`.
2. `setcap cap_sys_admin+p` on `/usr/bin/sunshine` for KMS-based capture — the COPR package
   ships without the cap; without it Sunshine falls back to a slower PipeWire portal path.
3. `systemctl --global disable app-dev.lizardbyte.app.Sunshine.service` — defense-in-depth
   (Aurora pattern); the user service is `disabled` by default (no preset ships), opt-in via
   `ujust setup-sunshine enable`.

Recipe override (`system_files/usr/share/ublue-os/just/82-bazzite-sunshine.just`): replaces
Bazzite's brew-flavoured recipe with an RPM-flavoured version managing
`app-dev.lizardbyte.app.Sunshine.service` (the COPR-shipped user unit) via
`systemctl --user enable --now`. Nag suppression: the build `rm`s
`/usr/share/ublue-os/announcements/sunshine-brew.msg.json` — its "Sunshine will soon be
removed" nag is permanently misleading with RPM integration.

**Why it matters**: brew-on-ostree adds ~30 minutes of first-run compile on a mid-tier
laptop, an unsupported package-manager dependency, and a slower per-user manual update path.
The RPM is already there, updates via `bootc upgrade`, needs no brew prerequisite, and works
on a fresh deployment without any user setup.

## 17. Rechunker enabled by default (vs. Bazzite-DX/AmyOS template-commented-out)

**Upstream**: Bazzite-DX (`build.yml:155-181`) and AmyOS (`build.yml`, similar) ship the
rechunker step **commented out** ("uncomment if you want it") — a fresh fork publishes one
giant overlay layer per build. Aurora-DX activates by default a custom `just rechunk` recipe
wrapping the `hhd-dev/rechunk` action.

**Us**: rechunker enabled by default in `.github/workflows/reusable-build.yml` using bootc's
native `rpm-ostree compose build-chunked-oci`. Choice over `hhd-dev/rechunk`:

- No external action version pin to maintain — runs in-image, the version shipped is exactly
  what bazzite ships.
- Integrates cleanly with our cosign-by-digest signing (no re-tagging dance).
- `--bootc --max-layers 127 --format-version 2` matches Bazzite's internal pattern,
  maximising cross-image dedup with the base.

**Cost**: ~+15 min wall-clock on the 6-job matrix (~13-15 min per job, parallel).

**Why it matters**: a fresh-fork user copy-pasting the Bazzite-DX template gets a
rechunkless image silently, discovering the gap via slow / non-resumable downloads or a
faster-than-expected GHCR quota burn. We surface the choice, default it on, and document the
trade-off here.

## 18. Full MSI laptop EC control — working module + GUI (vs. obsolete in-tree)

**Upstream**: the Bazzite `-ogc` kernel ships an **in-tree `msi-ec.ko`** that is a stale
mainline snapshot; on recent MSI hardware it rejects the machine's EC firmware outright —
e.g. on a Katana 17 (`17L5EMS1.115`), `modprobe msi-ec` fails with *"Firmware version is not
supported"*. The kernel is built with `CONFIG_ACPI_EC_DEBUGFS` off, so `ec_sys` cannot load
and `/sys/kernel/debug/ec/` never appears — leaving any fan GUI without a backend. No
control application is shipped. Net result: fan modes, shift modes, cooler-boost, and fan
curves are **unavailable** on otherwise-supported MSI laptops.

**Us**: two out-of-tree modules built at image-build time by a generic kmod builder
(`build_files/kmods/build-kmods.sh`) and installed into `updates/` (highest depmod priority,
overriding the obsolete in-tree copy with no override file):

- **`msi-ec`** from BeardOverflow upstream, pinned commit `e538f85`
  (`build_files/kmods/msi-ec/source.env`, `build_files/mx/70-msi-ec.sh`) — the current
  driver that *does* whitelist recent firmware.
- **`acpi_ec`** from `saidsay-so/acpi_ec`, pinned tag `v1.0.4` / `75102ce`
  (`build_files/kmods/acpi_ec/source.env`, `build_files/mx/71-acpi-ec.sh`) — creates the
  root-only `/dev/ec` char device, the fallback backend MControlCenter uses when the
  `ec_sys` debugfs node is absent, carrying both fan-RPM reads and fan-curve writes.

The control GUI — **MControlCenter**, the app cited by msi-ec's own README — ships from the
`teackot/msi` COPR (`teackot-msi.repo` vendored `enabled=0`). Everything is wired into a
single opt-in recipe `ujust setup-msi enable|disable` (`95-bazzite-mx.just`): `enable` loads
both modules, persists autoload, and layers the GUI; `disable` reverses all three. No
autoload ships in the image.

**Why it matters**: out of the box on Bazzite, an MSI-laptop owner gets a fan controller
that silently won't load and no app to drive it. Bazzite MX makes fan modes, shift modes,
cooler-boost, the battery-charge threshold, and fan curves actually work, with a GUI —
verified on the maintainer's Katana 17. It stays **opt-in** (no autoload, no GUI layered by
default) so non-MSI hardware pays nothing, honouring the "no opinionated defaults"
principle. Commits: `4684f3c` (msi-ec), `bdaaa13` (GUI), `cc630ad` (acpi_ec).

## How to extend this list

When adding a new phase, ask: **does this give us an edge over upstream `bazzite-dx`?** If
yes, document it here with: the introducing commit hash, the upstream behaviour improved on
(`file:line` reference), our solution (`file:line` reference), and why it matters for an end
user. Avoid soft wins (formatting, naming, "I prefer X"); real wins are a bug they ship that
we fix, a clearly in-scope package they miss, a supply-chain hardening they lack, or a
maintenance reduction (e.g. zero-cost auto-update of keys).
