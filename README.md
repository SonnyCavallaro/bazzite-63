# bazzite-63

A personal **bootc atomic** workstation image built on top of
[Bazzite](https://bazzite.gg). It is a lean, single-flavour derivative: the base
OS stays minimal and stable, while development runtimes and apps are layered
per-user (via [`mise`](https://mise.jdx.dev), [Homebrew](https://brew.sh), and
Flatpak) so they update without an image rebuild or reboot.

Image: `ghcr.io/sonnycavallaro/bazzite-63`

Derived from [`MatrixDJ96/bazzite-mx`](https://github.com/MatrixDJ96/bazzite-mx)
(Apache-2.0), itself built on `ublue-os/bazzite`. This fork keeps that build
machinery — including the upstream MSI-laptop and 1Password integrations, so
bazzite-mx changes merge at near-zero cost — trims it to a single non-NVIDIA
flavour, returns Firefox to the base Bazzite Flatpak, and replaces baked-in dev
tooling with per-user tooling.

## Design principle: lean image, per-user tools

On an atomic distro a baked-in RPM only updates when the image is rebuilt **and**
the machine reboots. A Flatpak, or a tool managed by `mise`/`brew`, updates in
place, per-user, with no reboot. So bazzite-63 bakes as little as possible:

- **Runtimes** (Node, Python, Java, .NET) → `mise`, per-project, in `$HOME`.
- **CLI tools** (PowerShell, sqlcmd, …) → `brew`, in `$HOME`.
- **GUI apps** → Flatpak (installed on demand by `ujust bazzite-63-setup`, then auto-updating).
- The image itself carries only Bazzite plus the inherited bazzite-mx developer
  baseline (Docker, Podman, the libvirt/QEMU virtualization stack, VSCode,
  GitKraken, observability CLIs, …).

## Install

On a machine already running Bazzite:

```bash
sudo bootc switch ghcr.io/sonnycavallaro/bazzite-63:stable
systemctl reboot
```

Then, after the first login:

```bash
ujust bazzite-63-setup   # one-shot setup (or the single recipes below)
ujust b63-status         # expect: all OK
```

`bazzite-63-setup` installs everything that needs no user-provided files — the
default GUI Flatpak set, the dev environment, WinBoat, JetBrains Rider, the
Microsoft 365 launcher — then runs the health check. Idempotent: re-run it
anytime, uninstall what you don't need afterwards. **Nothing installs silently
at boot**: the image ships the machinery, you decide when to run it.

## Updates

The OS image arrives with `bootc upgrade` (the published image is rebuilt
whenever upstream Bazzite changes; reboot when `bootc status` shows a *Staged*
deployment) and Bazzite's automatic updater covers image + Flatpaks + brew. The
`mise` runtimes are pinned on purpose — bump them in
`~/.config/mise/config.toml` when *you* decide. Roll back a bad update with
`bootc rollback`.

## What you get

### The recipes

Every piece of the one-shot setup is also available as its own recipe:

| Recipe | What it does |
|---|---|
| `ujust install-default-flatpaks` | Default GUI Flatpak set: Google Chrome (default browser), Thunderbird (ESR), Proton Pass, DBeaver Community, Remmina, Parsec, Discord — auto-updating once installed |
| `ujust setup-dev` | `mise` + CLI tools via `brew` (PowerShell, sqlcmd), then the runtimes pinned in `~/.config/mise/config.toml`: Node LTS, Python 3.14, Temurin 21, .NET 10 |
| `ujust install-winboat` | WinBoat AppImage (run Windows apps in a container; beta) |
| `ujust install-rider` | JetBrains Rider (Flatpak) |
| `ujust install-sap-gui <jar>` | SAP GUI for Java, from an installer you provide |
| `ujust install-ibm-acs <zip>` | IBM i Access Client Solutions, from an archive you provide |
| `ujust setup-m365-pwa` | Microsoft 365 web-app launcher (Chrome PWA) |
| `ujust b63-status` | One-glance OK/KO health check of the whole setup, with a fix hint per KO |

### Baked-in niceties

- **Chrome as the system-wide default browser** (merged into the XDG defaults at
  build time; per-user override always wins).
- **Konsole defaults to a PowerShell profile** — via skel for new accounts and
  a first-login hook for accounts that predate the image, with a bash fallback
  until `setup-dev` has installed `pwsh`, so every install has a working
  terminal. An explicit per-user profile choice is never overridden.
- **Tray clock shows seconds** — applied once per user at login through the
  plasmashell scripting API; change it afterwards and your choice sticks.

## Build & CI

GitHub Actions builds a single `bazzite-63` image, signs it with cosign, and
publishes it to GHCR. `watch-upstream` rebuilds hourly when upstream Bazzite
changes. See [`AGENTS.md`](AGENTS.md) and [`docs/`](docs/) for the build flow,
conventions, and gotchas.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
