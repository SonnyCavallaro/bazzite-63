# Architecture

## What `bazzite-mx` is

A personal **bootc atomic distribution** built on top of upstream Bazzite, adopting the
Aurora-DX build style (numbered scripts per domain, isolated repos, blocking smoke tests,
targeted cleanup).

## Single-flavour design

bazzite-mx is single-flavour **by definition**: no `IMAGE_TIER` toggle, no `-dx` suffix
variant, no separate "lite" image — every build step in `build_files/mx/` runs
unconditionally on every image. The three GHCR images differ **only** in `BASE_IMAGE`:

| Image | BASE_IMAGE | Use case |
|---|---|---|
| `bazzite-mx` | `bazzite` | non-NVIDIA hardware |
| `bazzite-mx-nvidia` | `bazzite-nvidia` | NVIDIA proprietary driver |
| `bazzite-mx-nvidia-open` | `bazzite-nvidia-open` | NVIDIA open kernel modules |

## Containerfile flow

The Containerfile has four stages — `ctx`, `akmods-rpms`, `kmod-builder` (its own `RUN`
compiles the out-of-tree kernel modules, see below) and the final image. The final stage has
3 `RUN` steps:

1. **`/ctx/build_files/shared/build.sh`** — orchestrator that (a) rsyncs `system_files/`
   into `/`, (b) calls `build-mx.sh`, (c) runs `clean-stage.sh`, (d) runs
   `validate-repos.sh`. Mounts a build-context bind, plus `/var/cache` and `/var/log` as
   caches and `/tmp` as tmpfs.
2. **`/ctx/build_files/tests/10-tests-mx.sh`** — smoke test (rpm-q + systemctl is-enabled +
   file-existence assertions). The `/ctx` bind-mount is preserved so the test can read the
   build context if needed.
3. **`bootc container lint`** — strict (no `|| true`). The image cannot ship with hard lint
   failures.

## Build orchestration order

Inside `build.sh`:

```
rsync system_files/ → /
build-mx.sh
  ├─ writes /etc/sysctl.d/90-bazzite-mx-forwarding.conf
  ├─ writes /etc/modules-load.d/90-bazzite-mx.conf
  └─ enumerate build_files/mx/[0-9]*-*.sh in version order
       (mapfile -t < <(find … | sort -V))
       │
       └─ 18 numbered domain scripts (00-image-info.sh … 71-acpi-ec.sh)
clean-stage.sh
  ├─ dnf5 config-manager setopt keepcache=0
  ├─ dnf5 versionlock clear
  ├─ mask + remove flatpak-add-fedora-repos.service
  ├─ rm /.gitkeep
  ├─ find /var/* -maxdepth 0 -type d ! -name cache -exec rm -fr {} \;
  └─ mkdir /var/tmp
validate-repos.sh
  └─ hard-fails if any of the 13 OTHER_REPOS entries (or _copr_* / rpmfusion-*) is enabled=1
```

### Decade map (`build_files/mx/`)

Each decade owns one domain; `build-mx.sh` runs the scripts in version order:

| Decade | Domain | Scripts |
|---|---|---|
| 00 | Identity / branding | `00-image-info.sh` |
| 10 | Container runtime | `10-container-runtime.sh` |
| 20 | Virtualization | `20-virtualization.sh`, `21-virt-manager-flatpak-exclude.sh` |
| 30 | IDE + git tools | `30-ide.sh`, `35-git-tools.sh` |
| 40 | Dev CLI (rpms + pinned binaries) | `40-dev-cli-rpms.sh`, `41-dev-cli-pinned.sh` |
| 50 | Bazzite extras + justfile glue | `50-bazzite-extras.sh`, `55-justfile-import.sh` |
| 60 | Desktop apps + repo/key provisioning for opt-in layering | `60-desktop-apps.sh`, `61-firefox-rpm.sh`, `62-firefox-flatpak-exclude.sh`, `63-rpmfusion-release.sh`, `64-1password-key.sh`, `65-sunshine.sh` |
| 70 | Out-of-tree kmods install | `70-msi-ec.sh`, `71-acpi-ec.sh` |

### `build_files/kmods/` — out-of-tree kernel modules

`build_files/kmods/` is built in a dedicated `kmod-builder` Containerfile stage, NOT by
`build-mx.sh` (whose `[0-9]*-*.sh` glob only runs `build_files/mx/`). It compiles
out-of-tree kernel modules (`msi-ec`, `acpi_ec`) against `kernel-devel` from the
`akmods:ogc-<fedora>-<kver>` carrier and stages the `.ko` files for the final stage, which
installs them into `updates/` and runs `depmod`.

## Repository layout

```
bazzite-mx/
├── Containerfile                # 4-stage: ctx + akmods-rpms + kmod-builder + final
├── build_files/
│   ├── shared/                  # Orchestrator + helpers (build.sh,
│   │                              build-mx.sh, copr-helpers.sh,
│   │                              clean-stage.sh, validate-repos.sh)
│   ├── mx/                      # 18 numbered domain scripts (<NN>-<domain>.sh)
│   ├── kmods/                   # Out-of-tree kernel module builder (see note above)
│   └── tests/                   # 10-tests-mx.sh (smoke)
├── system_files/                # Rsync'd into / by build.sh (yum.repos.d, skel,
│                                  ujust recipes, setup hooks, sysusers.d,
│                                  bootc install/ + kargs.d)
├── site/                        # GitHub Pages landing page (index.html + assets)
├── .github/workflows/
│   ├── build-stable.yml
│   ├── build-testing.yml
│   ├── clean.yml
│   ├── deploy-pages.yml
│   ├── generate-release.yml
│   ├── reusable-build.yml
│   └── watch-upstream.yml
├── .github/scripts/changelog.sh # Release-notes generator (generate-release.yml)
├── cosign.{key,pub}             # .key gitignored
├── AGENTS.md                    # Canonical project guide (every agent)
├── CLAUDE.md                    # Claude Code bridge → @AGENTS.md
├── docs/                        # Deep knowledge (this folder)
├── .gemini/settings.json        # Points Gemini CLI at AGENTS.md
└── .claude/                     # Claude Code config
    ├── settings.json
    ├── commands/preflight.md
    └── hooks/                   # repo-enabled-guard.sh + shellcheck-edit.sh
```

## CI matrix

`.github/workflows/reusable-build.yml` is called by both `build-stable.yml` and
`build-testing.yml`. Each parent workflow passes a different `stream_name` ("stable" or
"testing"), and reusable-build resolves the upstream tag accordingly.

The matrix is 3 jobs: `bazzite`, `bazzite-nvidia`, `bazzite-nvidia-open`. A push to `main`
triggers **6 jobs total** (3 × 2 streams); a push to `develop` runs only Build Stable
(3 jobs — `build-testing.yml` triggers on `main` alone).

`concurrency.cancel-in-progress: false` (with a literal kebab-case
`group: bazzite-mx-{stream}-${{ github.ref_name }}`) means in-flight runs are not
auto-cancelled, and `develop` runs proceed in parallel with `main`. AGENTS.md critical
convention #8 owns the full naming rationale (why the group must never be
`${{ github.workflow }}`).

## Repo isolation invariant

Every third-party repository file ships to the image with `enabled=0`. `validate-repos.sh`
enforces this for an explicit list of tracked filenames + globs (`_copr:*`, `rpmfusion-*`).

## Cockpit pattern (intentionally NOT overridden)

Bazzite ships Cockpit as a **podman quadlet** at
`/usr/share/containers/systemd/cockpit-container.container`:

```
[Container]
Image=quay.io/cockpit/ws:latest
Volume=/:/host
PodmanArgs=--privileged --pid=host --cgroups=split
```

systemd's `podman-systemd-generator` reads this at boot and creates
`cockpit-container.service` dynamically in `/run/systemd/system/`. The `cockpit.service`
stub at `/usr/lib/systemd/system/cockpit.service` (custom-injected by Bazzite, owned by no
RPM) `Requires=cockpit-container.service`.

`ujust cockpit enable` toggles the stub → starts the container → a full Cockpit UI at
https://localhost:9090 with all standard modules bundled in `quay.io/cockpit/ws:latest`,
auto-updated via `Label=io.containers.autoupdate=registry`.

bazzite-mx **deliberately does NOT add host-side `cockpit-machines` or `cockpit-ostree`
RPMs** — the container already serves all standard modules; layering would duplicate. This
is a canonical example of "skip when upstream handles it well" — see
[`workflow.md`](workflow.md) § When to skip a phase.
