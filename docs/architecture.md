# Architecture

## What `bazzite-63` is

A personal **bootc atomic distribution** built on top of upstream Bazzite,
adopting the Aurora-DX build style (numbered scripts per domain, isolated
repos, blocking smoke tests, targeted cleanup). Derived from
`MatrixDJ96/bazzite-mx` (Apache-2.0); structure and CI machinery are reused,
non-essential content removed, approach made lean.

## Single-flavour design

bazzite-63 is single-flavour **by definition**. There is no `IMAGE_TIER` toggle,
no `-nvidia` suffix variant, and no separate "lite" image — every build step in
`build_files/mx/` runs unconditionally on every image. The build matrix keeps a
single entry so re-adding a variant is a one-line change. One GHCR image:

| Image | BASE_IMAGE | Use case |
|---|---|---|
| `bazzite-63` | `bazzite` | non-NVIDIA hardware |

## Containerfile stages

The Containerfile has **4 stages**:

1. **`ctx` (scratch)** — copies `build_files/` and `system_files/` into the build
   context. No RUN steps; serves only as a bind-mount source for subsequent stages.
2. **`akmods-rpms`** — FROM-scratch carrier of `/kernel-rpms` (incl. kernel-devel)
   matched to the base image's kernel; consumed only as an RPM source via
   bind-mount (inherited verbatim from bazzite-mx).
3. **`kmod-builder`** — compiles the out-of-tree modules (msi-ec, acpi_ec) against
   the matched kernel-devel via `build_files/kmods/build-kmods.sh`, emitting
   staged `.ko.xz` under `/out` (inherited verbatim from bazzite-mx).
4. **Final stage** — `FROM ghcr.io/ublue-os/bazzite:${BASE_TAG}`, with three RUN
   steps executed in order:

   a. **`/ctx/build_files/shared/build.sh`** — orchestrator that (a) rsyncs
      `system_files/` into `/`, (b) calls `build-mx.sh`, (c) runs
      `clean-stage.sh`, (d) runs `validate-repos.sh`. Mounts a build context bind,
      plus `/var/cache` and `/var/log` as caches and `/tmp` as tmpfs.
   b. **`/ctx/build_files/tests/10-tests-mx.sh`** — smoke test (rpm-q +
      systemctl is-enabled + file-existence assertions). Bind-mount of `/ctx`
      preserved so the test can read the build context if needed.
   c. **`bootc container lint`** — strict (no `|| true`). The image cannot ship
      with hard lint failures.

## Build orchestration order

Inside `build.sh`:

```
rsync system_files/ → /
build-mx.sh
  ├─ writes /etc/sysctl.d/90-bazzite-63-forwarding.conf
  ├─ writes /etc/modules-load.d/90-bazzite-63.conf
  └─ enumerate build_files/mx/[0-9]*-*.sh in version order
       (mapfile -t < <(find … | sort -V))
clean-stage.sh
  ├─ dnf5 config-manager setopt keepcache=0
  ├─ dnf5 versionlock clear
  ├─ mask + remove flatpak-add-fedora-repos.service
  ├─ rm /.gitkeep
  ├─ find /var/* -maxdepth 0 -type d ! -name cache -exec rm -fr {} \;
  └─ mkdir /var/tmp
validate-repos.sh
  └─ checks OTHER_REPOS list (all tracked .repo files must be enabled=0)
```

## Repository layout

```
bazzite-63/
├── Containerfile                # 4 stages: ctx + akmods-rpms + kmod-builder + final
├── build_files/
│   ├── shared/                  # Orchestrator + helpers (build.sh,
│   │                              build-mx.sh, copr-helpers.sh,
│   │                              clean-stage.sh, validate-repos.sh)
│   ├── mx/                      # Numbered domain scripts
│   ├── kmods/                   # Out-of-tree kmod sources + builder (msi-ec, acpi_ec)
│   └── tests/                   # 10-tests-mx.sh (smoke)
├── system_files/                # Rsync'd into / by build.sh
├── .github/workflows/
│   ├── build-stable.yml
│   ├── build-testing.yml
│   ├── reusable-build.yml
│   ├── watch-upstream.yml
│   ├── clean.yml
│   └── generate-release.yml
├── cosign.{key,pub}             # .key gitignored
├── AGENTS.md                    # Canonical project guide (every agent)
├── CLAUDE.md                    # Claude Code bridge → @AGENTS.md
├── docs/                        # Deep knowledge (this folder)
└── .claude/                     # Claude Code config
    ├── settings.json
    └── commands/preflight.md
```

## CI matrix

`.github/workflows/reusable-build.yml` is called by both `build-stable.yml` and
`build-testing.yml`. Each parent workflow passes a different `stream_name`
("stable" or "testing"), and reusable-build resolves the upstream tag accordingly.

The matrix has **1 entry** (`bazzite-63` / `bazzite` base). So a push to `main`
triggers **2 build jobs** (1 image × 2 streams); a push to `develop` triggers
only the stable stream (`build-testing.yml` runs on `main` pushes only).

`concurrency.cancel-in-progress: false` (with a literal kebab-case
`group: bazzite-63-{stream}-${{ github.ref_name }}`) means in-flight runs are
not auto-cancelled: each push's build completes, and `develop` runs proceed in
parallel with `main`. See AGENTS.md critical convention #8 for why the group
must never be `${{ github.workflow }}`.

## Repo isolation invariant

Every third-party repository file ships to the image with `enabled=0`.
`validate-repos.sh` enforces this for an explicit list of tracked filenames and
globs (`_copr:*`, `rpmfusion-*`). The lean image currently vendors no extra repos
beyond the inherited baseline — prefer Flatpak / `brew` / `mise` for new tools
before reaching for a baked RPM.

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
`cockpit-container.service` dynamically in `/run/systemd/system/`. The
`cockpit.service` stub at `/usr/lib/systemd/system/cockpit.service`
(custom-injected by Bazzite, not owned by any RPM) `Requires=cockpit-container
.service`.

`ujust cockpit enable` toggles the stub → starts the container → user gets a
full Cockpit UI at https://localhost:9090 with all standard modules bundled in
`quay.io/cockpit/ws:latest` and auto-updates via
`Label=io.containers.autoupdate=registry`.

bazzite-63 **deliberately does NOT add host-side `cockpit-machines` or
`cockpit-ostree` RPMs**. The container already serves all standard modules;
layering would duplicate. This is one of the canonical examples of "skip when
upstream handles it well" — see `workflow.md` § When to skip a phase.
