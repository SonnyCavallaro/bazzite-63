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
   bind-mount (inherited verbatim from bazzite-mx). The three coordinates of the
   carrier tag (`akmods:<flavour>-<fedora>-<kver>`) come from
   `.github/scripts/resolve-kernel-coords.sh`, which reads the base image's
   `ostree.linux` label and asks the registry which akmods flavours carry that
   exact kernel NVRA — upstream moves a flavour whose driver lags a mainline
   kernel bump onto the LTS branch (`ogc-lts`) while its siblings ride `ogc`
   (gotcha #38). CI and `/preflight` call that one resolver.
3. **`kmod-builder`** — compiles the out-of-tree modules (msi-ec, acpi_ec,
   ntfsplus) against the matched kernel-devel via
   `build_files/kmods/build-kmods.sh`, emitting staged `.ko.xz` under `/out`
   (inherited verbatim from bazzite-mx). Each module is one directory holding a
   `source.env` sourced by the builder loop: `URL`, a pinned `COMMIT`,
   `KO_NAME`, `KO_DEST`, plus the optional `KO_BUILD_PATH` (built object in a
   subdirectory: acpi_ec) and `KO_BUILD_ARGS` (extra `make` variables for a
   kbuild fragment gated on a kernel config symbol: ntfsplus).
4. **Final stage** — `FROM ghcr.io/ublue-os/bazzite:${BASE_TAG}`, with three RUN
   steps executed in order:

   a. **`/ctx/build_files/shared/build.sh`** — orchestrator that (a) rsyncs
      `system_files/` into `/`, (b) calls `build-mx.sh`, (c) runs
      `clean-stage.sh`, (d) runs `validate-repos.sh`, (e) rewrites the rpmdb the
      build wrote onto a fresh inode and relinks the rpm-ostree base-db to it
      (build.sh steps 4 and 5). Mounts a build context bind,
      plus `/var/cache` and `/var/log` as caches and `/tmp` as tmpfs.
   b. **`/ctx/build_files/tests/10-tests-mx.sh`** — smoke test (rpm-q +
      systemctl is-enabled + file-existence assertions). Bind-mount of `/ctx`
      preserved so the test can read the build context if needed.
   c. **`bootc container lint --fatal-warnings --no-truncate`** — strict (no
      `|| true`): a new warning (runtime-dir residue, `/boot` content) fails the
      build instead of scrolling by.

## Build orchestration order

Inside `build.sh`:

```
rsync system_files/ → /
build-mx.sh
  ├─ writes /etc/sysctl.d/90-bazzite-63-forwarding.conf
  ├─ writes /etc/modules-load.d/90-bazzite-63-nat.conf
  └─ enumerate build_files/mx/[0-9]*-*.sh in version order
       (mapfile -t < <(find … | sort -V))
clean-stage.sh
  ├─ restore /etc/dnf/dnf.conf from /tmp/dnf.conf.orig (if staged)
  ├─ rm -rf /usr/lib/sysimage/libdnf5/*   (versionlock pins are KEPT: the base pins its kernel + mesa)
  ├─ mask + remove flatpak-add-fedora-repos.service
  ├─ sed enabled=1→0 on terra-mesa.repo (the one base repo shipped file-level enabled)
  ├─ find /var/* -maxdepth 0 -type d ! -name cache ! -name log -exec rm -fr {} \;
  ├─ rm -rf /tmp/* + mkdir -p /var/tmp + chmod 1777
  └─ sweep /run (keeps the container plumbing) + find /boot -mindepth 1 -delete (bootc lint runs --fatal-warnings)
validate-repos.sh
  └─ hard-fails if any third-party-repos.list entry (or _copr_* / rpmfusion-*) is enabled=1,
     or listed but absent from the image (`?` prefix = optional)
step 4: fresh-inode rewrite (VACUUM INTO + os.replace, sidecars dropped)
  └─ /usr/share/rpm/rpmdb.sqlite
step 5: relink /usr/lib/sysimage/rpm-ostree-base-db/rpmdb.sqlite (hardlink, sidecars dropped)
```

Step 4 runs last because every dnf5 transaction of the stage must already have
written its pages. It is the sqlite half of the torn-writeback guard; the text
half is `rewrite_fresh_inode`
from `shared/writeback-helpers.sh`, called by every script that writes a
base-image file in place (`55-justfile-reconcile.sh`, `56-justfile-import-63.sh`,
`21-virt-manager-flatpak-exclude.sh`, `61-chrome-rpm.sh`, `62-plasma-fonts.sh`,
`68-flatpak-apps.sh`, `copr-helpers.sh`).
See [`conventions.md`](conventions.md) § Writing base-image files.

## Repository layout

```
bazzite-63/
├── Containerfile                # 4 stages: ctx + akmods-rpms + kmod-builder + final
├── build_files/
│   ├── shared/                  # Orchestrator + helpers (build.sh,
│   │                              build-mx.sh, copr-helpers.sh,
│   │                              writeback-helpers.sh, clean-stage.sh,
│   │                              validate-repos.sh, third-party-repos.list)
│   ├── mx/                      # Numbered domain scripts
│   ├── kmods/                   # Out-of-tree kmod sources + builder (msi-ec, acpi_ec, ntfsplus)
│   └── tests/                   # 10-tests-mx.sh (smoke)
├── system_files/                # Rsync'd into / by build.sh
├── .github/workflows/
│   ├── build.yml
│   ├── reusable-build.yml
│   ├── watch-upstream.yml
│   ├── clean.yml
│   ├── generate-release.yml
│   └── sign-image.yml
├── .github/scripts/             # Host-side helpers called by the workflows
│   ├── changelog.sh             # Release-notes generator, digests via IMAGE_DIGESTS (generate-release.yml)
│   ├── check-image-integrity.sh # Cold post-rechunk check + --self-test (reusable-build.yml)
│   ├── list-flavours.sh         # ONE owner of the flavour set — a single bazzite-63 line (matrix plan, watcher, release, cleanup, resolver, changelog)
│   ├── promote-release-tags.sh  # Per-stream gate + digest-copy onto the release tags (reusable-build.yml)
│   ├── resolve-kernel-coords.sh # akmods carrier flavour/version (reusable-build.yml)
│   ├── resolve-release-tag.sh   # Downstream tag schema (build.yml)
│   ├── resolve-upstream-tag.sh  # ONE owner of "latest upstream tag for a stream" + the 404-gated .N strip
│   └── verify-published-signatures.sh # cosign proof with negative control (reusable-build.yml)
├── cosign.{key,pub}             # .key gitignored
├── AGENTS.md                    # Canonical project guide (every agent)
├── CLAUDE.md                    # Claude Code bridge → @AGENTS.md
├── docs/                        # Deep knowledge (this folder)
└── .claude/                     # Claude Code config
    ├── settings.json
    └── commands/preflight.md
```

## CI matrix

`.github/workflows/build.yml` is the single entry point for both streams, the
shape upstream `Build Bazzite` uses. Its `plan` job decides the stream set — the
`streams` input on a dispatch or a `Watch Upstream` call, `both` by default —
and emits `matrix_include`, a JSON array of flavour × stream entries.
`reusable-build.yml` is called **once**, with that matrix: `stream_name` is a
matrix dimension, not a workflow input, so the run shows ONE `Build matrix`
node. The per-stream tags travel as four inputs
(`upstream_tag_{stable,testing}`, `release_tag_{stable,testing}`) and each
matrix job picks its pair in the `Select stream inputs` step.

The matrix has **1 flavour** (`bazzite-63` / `bazzite` base) × 2 streams =
**2 build jobs**, running in parallel, in every context — a branch dispatch
(`gh workflow run build.yml --ref <branch>`) and a PR included: the base image
differs per stream (kernel, `.repo` set), so a stable-only sandbox would be
blind to testing-base drift. Outside `main` each job runs the sandbox
integrity check against its `raw-img` — no rechunk, no push. The single
flavour has one consequence for the promote jobs: `download-artifact` with a
pattern matching ONE artifact extracts flat, so both promote jobs pin the flat
layout with `merge-multiple: true` and `promote-release-tags.sh` globs
`promote/promote.env` (upstream's nested `promote/promote-*-<stream>/` glob
would count zero manifests here).

Downstream of the matrix, the gate is **per stream**: `promote-{stable,testing}`
each count their own `promote-*-<stream>` manifests against `matrix_include`
(never a literal) and abort loudly on a shortfall; `verify-{stable,testing}`
mirror them. The always-running `gate` job turns those results into the
callee outputs `stable_ok`/`testing_ok`, which the caller's `release-*` jobs
gate on instead of the callee's aggregate result — a broken testing base
(upstream's doing) must not sink the stable release, and vice versa.

`concurrency.cancel-in-progress: false` (with a literal kebab-case
`group: bazzite-63-build-${{ github.ref_name }}`) means in-flight runs are
not auto-cancelled: each push's build completes, and branch runs proceed in
parallel with `main`. The callee keeps its own literal group
(`bazzite-63-reusable-<ref>`). See AGENTS.md critical convention #8 for why
the group must never be `${{ github.workflow }}`.

## Repo isolation invariant

Every third-party repository file ships to the image with `enabled=0`.
`validate-repos.sh` enforces this for the filenames listed in
`build_files/shared/third-party-repos.list` plus the globs `_copr:*` and
`rpmfusion-*`, and `check-image-integrity.sh` re-proves the same list on the
chunked image's cold bytes. The lean image vendors `google-chrome.repo` beyond
the inherited baseline — prefer Flatpak / `brew` / `mise` for new tools before
reaching for a baked RPM.

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
