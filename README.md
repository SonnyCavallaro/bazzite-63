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
- **GUI apps** → Flatpak (auto-installed at first boot, auto-updating).
- The image itself carries only Bazzite plus the inherited bazzite-mx developer
  baseline (Docker, Podman, the libvirt/QEMU virtualization stack, VSCode,
  GitKraken, observability CLIs, …).

## What you get

### GUI apps (Flatpak, installed automatically at first boot)

Google Chrome (default browser), Thunderbird, Proton Pass, DBeaver Community,
Remmina, Parsec, Discord.

### Dev environment (one command)

```bash
ujust setup-dev
```

Installs `mise` and CLI tools via `brew`, then provisions the runtimes pinned in
`~/.config/mise/config.toml` (Node LTS, Python 3.14, Temurin 21, .NET 10). Edit
that file, or drop a per-project `mise.toml`, to change versions.

### Opt-in apps (`ujust`)

| Recipe | What it does |
|---|---|
| `ujust install-winboat` | WinBoat AppImage (run Windows apps in a container; beta) |
| `ujust install-rider` | JetBrains Rider (Flatpak) |
| `ujust install-sap-gui <jar>` | SAP GUI for Java, from an installer you provide |
| `ujust install-ibm-acs <zip>` | IBM i Access Client Solutions, from an archive you provide |
| `ujust setup-m365-pwa` | Microsoft 365 web-app launcher (Chrome PWA) |

## Install

On a machine already running Bazzite:

```bash
sudo bootc switch ghcr.io/sonnycavallaro/bazzite-63:stable
systemctl reboot
```

Updates arrive with `bootc upgrade` (the published image is rebuilt whenever
upstream Bazzite changes). Roll back a bad update with `bootc rollback`.

## Build & CI

GitHub Actions builds a single `bazzite-63` image, signs it with cosign, and
publishes it to GHCR. `watch-upstream` rebuilds hourly when upstream Bazzite
changes. See [`AGENTS.md`](AGENTS.md) and [`docs/`](docs/) for the build flow,
conventions, and gotchas.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
