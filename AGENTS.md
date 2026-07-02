# AGENTS.md — bazzite-mx project guide

Canonical, tool-agnostic instructions for any coding agent working on this repo.

## Project overview

`bazzite-mx` is a personal **bootc atomic distribution** built on top of Bazzite.
**Single-flavour by design**: no `IMAGE_TIER` toggle, no `-dx` suffix variants. The build
pipeline is unconditional and applied always. Three GHCR images differ only in `BASE_IMAGE`:

| Image | BASE_IMAGE | Use case |
|---|---|---|
| `bazzite-mx` | `bazzite` | non-NVIDIA hardware |
| `bazzite-mx-nvidia` | `bazzite-nvidia` | NVIDIA proprietary driver |
| `bazzite-mx-nvidia-open` | `bazzite-nvidia-open` | NVIDIA open kernel modules |

**Repo**: `MatrixDJ96/bazzite-mx` on GitHub, branch `main`.
**Owner**: Mattia Rombi (mattyro96@gmail.com).

## Where to look

| If you need to… | Read |
|---|---|
| Understand the build flow / layout / repository structure | [`docs/architecture.md`](docs/architecture.md) |
| Write new bash, edit a script, add a third-party repo, extend smoke tests | [`docs/conventions.md`](docs/conventions.md) |
| Plan a phase, decide when to push, do a review round, handle CI | [`docs/workflow.md`](docs/workflow.md) |
| Diagnose a familiar-looking error | [`docs/gotchas.md`](docs/gotchas.md) |
| Understand what bazzite-mx intentionally changes over upstream (+ design philosophy) | [`docs/upstream-divergences.md`](docs/upstream-divergences.md) |

Pre-flighting a build locally is covered by the *Quick command cheatsheet* below.

## Critical conventions (the absolute minimum to not break things)

1. **`dnf5 config-manager setopt <id>.enabled=0` is a SILENT NO-OP** on
   .repo files added via `addrepo --from-repofile=URL` or `--repofrompath`.
   Use `sed -i 's/^enabled=1/enabled=0/g' /etc/yum.repos.d/<file>.repo`.

2. **Every third-party `.repo` file ships `enabled=0`**. Vendor it in
   `system_files/etc/yum.repos.d/`, register the basename in
   `OTHER_REPOS` in `validate-repos.sh`, install via
   `dnf5 -y install --enablerepo=<section> <pkg>`. The validator hard-fails
   the build if a registered repo is left enabled.

3. **Pre-flight locally** with `podman build --build-arg BASE_IMAGE=bazzite …`
   **before** pushing. ~5 min vs ~15 min for a 6-job CI matrix. Always
   capture the build's exit code properly: `BUILD_EXIT=$?; exit $BUILD_EXIT`.

4. **Pause for user confirmation before push**, even on a green pre-flight.
   Push triggers 6 CI jobs and is visible to the world.

5. **Conventional Commits**. Never `--force`, `--no-verify`,
   `--amend` without explicit ask.

6. **Provenance citations always**: when proposing a package or pattern,
   cite the source ("from Aurora-DX line X", "lifted from bazzite-dx",
   "my proposal validated by Y").

7. **Skip a phase when upstream handles it well**. Document why in the
   commit message and in `docs/upstream-divergences.md`; don't re-derive
   the decision next session.

8. **CI naming conventions**: Workflow `name:` = Title Case (`Build Stable`).
   Job/step `name:` = sentence case, imperative + object (`Resolve release
   tag`, `Check just syntax`). Env vars = `SCREAMING_SNAKE_CASE` (no 2-3
   letter sigle: `DIGEST_NVIDIA_OPEN`, not `D_NVO`). Input/output keys =
   `snake_case`, no synonyms cross-workflow (`release_tag` everywhere, not
   `stream_version` in one file and `release_tag` in another). Concurrency
   `group:` = literal `bazzite-mx-<phase>[-<flavour>][-<key>]` kebab-case
   (NEVER `${{ github.workflow }}` — in any callee invoked via
   `workflow_call` it resolves to the caller's name, colliding with the
   caller's own group and triggering "deadlock detected → canceling" on
   every chained call. Empirically validated 2026-05-14). Shell binary
   names (`just`, `gh`, `podman`) lowercase, acronyms (`GHCR`, `OCI`,
   `BTRFS`, `SBOM`) uppercase.

9. **`validate-just` is a gating job inside `build-{stable,testing}.yml`**
   (not a standalone workflow). It runs `just --list` on each `.just`
   file via preinstalled brew (NOT `setup-just` or `ublue-os/just-action`;
   GitHub-hosted runners ship `just` via Linuxbrew, +30s install vs +1
   third-party action dependency — pattern aurora-conforming). The `build`
   job depends on `validate-just`, so a broken `.just` aborts the matrix
   before any GHCR push or release. Don't "modernize" this — decision
   validated by 4-lens audit + empirical gate refactor.

For the full set of conventions (bash style, smoke test idiom, vendoring
rule, COPR pattern, comment policy), see
[`docs/conventions.md`](docs/conventions.md).

## Repository layout (one-line summary)

```
AGENTS.md                   # canonical project guide (this file)
CLAUDE.md                   # Claude Code bridge → @AGENTS.md
Containerfile               # 3 RUN steps: build.sh → 10-tests-mx.sh → bootc lint
build_files/{shared,mx,tests,kmods}/
system_files/{etc,usr}/
site/                       # GitHub Pages landing page (index.html + assets)
docs/                       # deep knowledge: architecture, conventions, gotchas, workflow, divergences
.github/workflows/          # build-stable, build-testing, clean, deploy-pages, generate-release, reusable-build, watch-upstream
.github/scripts/changelog.sh  # release-notes generator used by generate-release
.claude/                    # Claude Code config: settings.json + commands/preflight.md + hooks/{repo-enabled-guard,shellcheck-edit}.sh (+ gitignored local state: settings.local.json, audits/, sessions/)
cosign.{key,pub}            # .key gitignored
```

## CI flow at a glance

```
push to main / dispatch / watch-upstream (workflow_call) ─►
  build-{stable,testing}.yml:
     resolve  (collision .N on gh release list + GHCR tags)
       └─► build    (reusable-build, 3-image matrix, push :stable + :<release_tag> immutable)
            └─► release  (generate-release.yml, stable=latest / testing=prerelease)

watch-upstream     (cron hourly)     ─► triggers build-{stable,testing}.yml if upstream changed
clean              (cron Sun 00:15)  ─► prunes the 3 GHCR packages (>90d, keep 7+7)
generate-release   (workflow_call / dispatch) ─► takes stream_name + upstream_tag + release_tag
```

### Branch policy

| Branch | Build | Rechunk | Push GHCR | Sign | Release |
|---|---|---|---|---|---|
| `main` | ✓ | ✓ | ✓ | ✓ | ✓ (push + watch-upstream + dispatch) |
| `develop` | ✓ | ✗ | ✗ | ✗ | ✗ — fast CI sandbox |
| PR to `main` | ✓ | ✗ | ✗ | ✗ | ✗ |

Release tags carry the **build date**, not the upstream tag's date: `44.<build date>` for
stable, `testing-44.<build date>` for testing, with `.1`, `.2`, … appended on same-day
rebuilds — so upstream's own `.N` rebuild suffixes never leak into our nomenclature. Each
tag exists both as GitHub Release and as immutable GHCR image tag (`:stable` is mutable and
always points to the latest build); the upstream tag a release was built off is recorded in
the release title (`44.20260706: Stable (Bazzite 44.20260629)`).

## Quick command cheatsheet

```bash
# Pre-flight one flavour locally (~5 min): run /preflight (.claude/commands/preflight.md);
# the full manual podman recipe lives in README.md § "How it's built and shipped".

# Push and watch CI
git push origin main
gh run list --repo MatrixDJ96/bazzite-mx --limit 4 \
  --json databaseId,workflowName,status,conclusion,headSha,createdAt \
  | jq -r '.[] | "\(.createdAt) | \(.workflowName) | run \(.databaseId) | \(.status)/\(.conclusion // "-") | \(.headSha[0:7])"'

# Cleanup local
podman rmi localhost/bazzite-mx:preflight && podman image prune -f
```

```bash
# Iterate WIP on the develop branch (CI runs build only — no push, no release)
git checkout -b develop
git push -u origin develop
# Then: gh run list --workflow "Build Stable" --branch develop

# Trigger a release manually (stream defaults to stable, upstream auto-resolves latest)
gh workflow run "Generate Release" --repo MatrixDJ96/bazzite-mx \
  -f stream_name=stable
# Force a testing pre-release for the latest upstream testing tag:
gh workflow run "Generate Release" --repo MatrixDJ96/bazzite-mx \
  -f stream_name=testing

# List published releases on the repo
gh release list --repo MatrixDJ96/bazzite-mx

# Preview what the weekly GHCR cleanup would prune (no destructive action)
gh workflow run "Cleanup GHCR" --repo MatrixDJ96/bazzite-mx -f dry_run=true
```
