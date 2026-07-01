# Bazzite MX

A single-maintainer, **curated spin of [Bazzite](https://github.com/ublue-os/bazzite)** — a
KDE Plasma, container-first **dev & sysadmin workstation**, shipped as a signed
[bootc](https://github.com/containers/bootc) atomic image you boot into and stop thinking about.

> **It's a build recipe, not an app.** Bazzite MX takes upstream Bazzite, layers a curated set of
> fixes and tools on top, and publishes the result as signed bootc OS images on GHCR. You don't clone
> it to run it — you **rebase your machine onto the image it produces**.

Built for one person's hardware and taste, in the open so every choice is auditable. Three principles
drive all of them:

- **Adds, never imposes.** Bazzite does the heavy lifting; each addition only smooths a rough edge or
  fills a real gap — never fonts, themes, or formatters. See [what it changes over
  `bazzite-dx`](docs/wins-over-upstream.md).
- **Atomic-correct by construction.** Everything is baked and verified at build time; nothing leans on
  fragile first-boot mutations of a read-only `/usr`.
- **Built on giants.** Bazzite is the foundation — without it this wouldn't exist. The sharpest ideas
  are borrowed from [Aurora](https://getaurora.dev), [Bazzite-DX](https://github.com/ublue-os/bazzite),
  and [AmyOS](https://github.com/astrovm/amyos).

## The images

Three variants, identical except for the Bazzite base they layer on — pick the one for your GPU:

| Image | Base | For |
|---|---|---|
| `ghcr.io/matrixdj96/bazzite-mx` | `bazzite` | non-NVIDIA hardware |
| `ghcr.io/matrixdj96/bazzite-mx-nvidia` | `bazzite-nvidia` | NVIDIA proprietary driver |
| `ghcr.io/matrixdj96/bazzite-mx-nvidia-open` | `bazzite-nvidia-open` | NVIDIA open kernel modules |

Each ships on two rolling streams — `:stable` and `:testing` — plus immutable dated tags
(e.g. `:44.20260511`) for pinning; `:latest` aliases stable. A watcher rebuilds within an hour of any
upstream Bazzite release, so the image never drifts far from its base.

## Trying it

Bazzite MX targets its maintainer's machine, but it's a standard signed bootc image — rebase at your
own risk, picking the variant for your GPU:

```bash
sudo bootc switch ghcr.io/matrixdj96/bazzite-mx:stable
systemctl reboot
```

## What you get on top of Bazzite

**A genuine dual-runtime dev box.** Docker CE and its full plugin set run alongside Bazzite's Podman —
both sockets enabled — and a complete `libvirt` / `qemu` / `virt-manager` stack works on first boot,
with `swtpm` for TPM 2.0 and KVM kargs tuned so Windows 11 guests just boot. No `ujust
setup-virtualization` dance.

**Workstation tools, done the atomic way.** VSCode with its self-updater disabled so it stops fighting
a read-only `/usr`; GitKraken and keyring-backed git auth; a deep tracing kit (`bcc-tools`, `bpftrace`,
`bpftop`, `sysprof`, `iotop-c`, and more); Firefox from Mozilla's own RPM instead of the
sandbox-limited Flatpak; and `gparted`, restored after Bazzite dropped the KDE partition GUI.

**Extras that stay opt-in.** Discord, 1Password, Sunshine game-streaming, and full MSI-laptop EC
control each ship as a `ujust` recipe you enable only if you want it — the base image stays lean for
everyone who doesn't. MSI is the standout: stock Bazzite ships an in-tree driver that *rejects* recent
MSI EC firmware, so fan and curve control simply don't work. Bazzite MX bakes the current
upstream `msi-ec` + `acpi_ec` modules into the image, and `ujust setup-msi enable` layers the
MControlCenter GUI to drive them — you're in business.
([the full story](docs/wins-over-upstream.md))

The itemised list, with provenance and rationale for every choice, lives in
[docs/wins-over-upstream.md](docs/wins-over-upstream.md).

## How it's built and shipped

The pipeline is deliberately boring and reproducible: an hourly watcher notices a new upstream Bazzite
release → a gate validates the `ujust` recipes → a matrix builds all three variants → each image is
signed by digest with cosign → a GitHub Release is cut. Push to `main` runs the same path; the
`develop` branch builds without pushing, as a fast CI sandbox.

Build a single variant locally before pushing (the maintainer's pre-flight, ~5 min):

```bash
BASE_TAG=$(skopeo inspect --no-tags docker://ghcr.io/ublue-os/bazzite:stable \
    | jq -r '.Labels["org.opencontainers.image.version"]')
KERNEL_VERSION=$(skopeo inspect --no-tags docker://ghcr.io/ublue-os/bazzite:${BASE_TAG} \
    | jq -r '.Labels["ostree.linux"]')
podman build --file Containerfile \
  --build-arg BASE_IMAGE=bazzite \
  --build-arg BASE_TAG=${BASE_TAG} \
  --build-arg KERNEL_VERSION=${KERNEL_VERSION} \
  --build-arg IMAGE_NAME=bazzite-mx \
  --tag localhost/bazzite-mx:preflight .
```

## Verifying a signed image

Every published image is signed by digest with cosign. Verify one against the public key:

```bash
cosign verify --key cosign.pub ghcr.io/matrixdj96/bazzite-mx:latest
```

The private `cosign.key` is gitignored — it lives only on the maintainer's machine and as a GitHub repo
secret.

## Under the hood

The build flow, conventions, and hard-won gotchas are documented for humans and coding agents alike:
[`AGENTS.md`](AGENTS.md) is the canonical guide, with deep dives in [`docs/`](docs/) (architecture,
conventions, workflow, gotchas).

## Credits

Built entirely on the shoulders of [Universal Blue](https://universal-blue.org) and
[Bazzite](https://bazzite.gg), with ideas borrowed from [Aurora](https://getaurora.dev),
[Bazzite-DX](https://github.com/ublue-os/bazzite), and [AmyOS](https://github.com/astrovm/amyos) —
Bazzite MX only curates a layer on top of their work.

## License

See [LICENSE](LICENSE).
