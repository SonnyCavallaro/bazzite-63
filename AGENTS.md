# AGENTS.md — bazzite-63 project guide

Canonical, tool-agnostic instructions for any coding agent working on this repo.

## Project overview

`bazzite-63` is a personal **bootc atomic** workstation image built on top of
Bazzite. **Single-flavour by design**: one non-NVIDIA image, no `-nvidia`
variants (the build matrix keeps a single entry, so re-adding a flavour is a
one-line change). One GHCR image:

| Image | BASE_IMAGE | Use case |
|---|---|---|
| `bazzite-63` | `bazzite` | non-NVIDIA hardware |

**Repo**: `SonnyCavallaro/bazzite-63` on GitHub (public), branch `main`.
**Owner**: Sonny Cavallaro.
**Upstream**: forked from `MatrixDJ96/bazzite-mx` (Apache-2.0); kept as the
`upstream` git remote for syncing build-machinery improvements.

### Lean principle

Bake as little as possible. A baked-in RPM only updates on image rebuild +
reboot; a Flatpak / `mise` / `brew` tool updates per-user with no reboot. So:

- **Runtimes** (Node, Python, Java, .NET) → `mise` (per-user, `~/.config/mise/`).
- **CLI tools** (PowerShell, sqlcmd, …) → `brew` (per-user).
- **GUI apps** → Flatpak default set (`build_files/mx/68-flatpak-apps.sh`), installed on demand via `ujust bazzite-63-setup` / `install-default-flatpaks`.
- The image carries Bazzite + the inherited bazzite-mx developer baseline only.

`ujust bazzite-63-setup` provisions everything in one command (default Flatpak
set + dev toolchain + opt-in apps + health check); each piece is also a
standalone recipe (`install-default-flatpaks`, `setup-dev`, …) and
`ujust b63-status` reports OK/KO on the whole setup. Nothing installs at boot.

## Where to look

| If you need to… | Read |
|---|---|
| Understand the build flow / layout / repository structure | [`docs/architecture.md`](docs/architecture.md) |
| Write new bash, edit a script, add a third-party repo, extend smoke tests | [`docs/conventions.md`](docs/conventions.md) |
| Plan work, decide when to push, do a review round, handle CI | [`docs/workflow.md`](docs/workflow.md) |
| Diagnose a familiar-looking error | [`docs/gotchas.md`](docs/gotchas.md) |

## Critical conventions (the absolute minimum to not break things)

1. **`dnf5 config-manager setopt <id>.enabled=0` is a SILENT NO-OP** on `.repo`
   files added via `addrepo --from-repofile=URL` or `--repofrompath`. Use
   `sed -i 's/^enabled=1/enabled=0/g' /etc/yum.repos.d/<file>.repo`.

2. **Every third-party `.repo` file ships `enabled=0`**. Vendor it in
   `system_files/etc/yum.repos.d/`, register the basename in `OTHER_REPOS` in
   `validate-repos.sh`, install via `dnf5 -y install --enablerepo=<section>
   <pkg>`. The validator hard-fails the build if a registered repo is left
   enabled. (The lean image vendors no extra repos beyond the bazzite-mx baseline
   — docker-ce, vscode, 1password, teackot-msi — prefer Flatpak / `brew` / `mise`
   for new tools before reaching for a baked RPM.)

3. **The build runs in CI, not locally.** A full Bazzite image build is heavy and
   impractical on a non-Linux dev box. Validate by pushing a branch and opening
   a PR to `main`: the branch policy builds it **without** publishing or signing.

4. **The publish step is the cutover.** Merging to `main` builds, signs (cosign),
   and pushes the public image. Treat it as a gated, explicit action.

5. **Conventional Commits**. Never `--force`, `--no-verify`, `--amend` without an
   explicit ask. No AI-attribution trailers.

6. **Provenance citations** when proposing a package or pattern: cite the source
   (upstream Bazzite, bazzite-mx, Aurora-DX, …).

7. **Prefer per-user over baked.** Before adding a baked RPM, ask whether a
   Flatpak, a `brew` formula, or a `mise` runtime serves the need without a
   rebuild/reboot.

8. **CI naming conventions**: Workflow `name:` = Title Case (`Build Stable`).
   Job/step `name:` = sentence case, imperative + object. Env vars =
   `SCREAMING_SNAKE_CASE`. Input/output keys = `snake_case`, consistent
   cross-workflow (`release_tag` everywhere). Concurrency `group:` = literal
   `bazzite-63-<phase>[-<key>]` kebab-case (NEVER `${{ github.workflow }}` — in a
   `workflow_call` callee it resolves to the caller's name and collides,
   triggering "deadlock detected → canceling"). Shell binaries (`just`, `gh`,
   `podman`) lowercase; acronyms (`GHCR`, `OCI`, `BTRFS`) uppercase.

9. **`validate-just` is a gating job inside `build-{stable,testing}.yml`** (not a
   standalone workflow). It runs `just --list` on each `.just` file via
   preinstalled Linuxbrew `just`. The `build` job depends on it, so a broken
   `.just` aborts before any GHCR push or release.

For the full set of conventions (bash style, smoke-test idiom, vendoring rule,
COPR pattern, comment policy), see [`docs/conventions.md`](docs/conventions.md).

## Repository layout (one-line summary)

```
AGENTS.md                   # canonical project guide (this file)
CLAUDE.md                   # Claude Code bridge → @AGENTS.md
Containerfile               # 3 RUN steps: build.sh → 10-tests-mx.sh → bootc lint
build_files/{shared,mx,tests,kmods}/
system_files/{etc,usr}/
docs/                       # deep knowledge: architecture, conventions, gotchas, workflow
.github/workflows/          # build-stable, build-testing, clean, generate-release, reusable-build, watch-upstream
.claude/                    # Claude Code config: settings.json + commands/preflight.md
cosign.{key,pub}            # .key gitignored; private key lives only in the SIGNING_SECRET GitHub secret
```

## CI flow at a glance

```
push to main / dispatch / watch-upstream (workflow_call) ─►
  build-{stable,testing}.yml:
     resolve  (collision .N on gh release list + GHCR tags)
       └─► build    (reusable-build, single-image, push :stable + :<release_tag> immutable)
            └─► release  (generate-release.yml, stable=latest / testing=prerelease)

watch-upstream     (cron hourly)     ─► triggers build-{stable,testing}.yml if upstream changed
clean              (cron Sun 00:15)  ─► prunes the bazzite-63 GHCR package (>90d, keep 7+7)
generate-release   (workflow_call / dispatch) ─► takes stream_name + upstream_tag + release_tag
```

### Branch policy

| Branch | Build | Rechunk | Push GHCR | Sign | Release |
|---|---|---|---|---|---|
| `main` | ✓ | ✓ | ✓ | ✓ | ✓ (push + watch-upstream + dispatch) |
| `develop` | ✓ | ✗ | ✗ | ✗ | ✗ — fast CI sandbox |
| PR to `main` | ✓ | ✗ | ✗ | ✗ | ✗ |

A PR to `main` is the safe integration test: it builds without publishing.

## Quick command cheatsheet

```bash
# Validate via CI (a full local build is impractical): push a branch and open a PR
git push -u origin <branch>
gh pr create --repo SonnyCavallaro/bazzite-63 --base main --head <branch>
gh run list --repo SonnyCavallaro/bazzite-63 --limit 4 \
  --json databaseId,workflowName,status,conclusion,headSha,createdAt \
  | jq -r '.[] | "\(.createdAt) | \(.workflowName) | run \(.databaseId) | \(.status)/\(.conclusion // "-") | \(.headSha[0:7])"'

# Trigger a release manually (stream defaults to stable, upstream auto-resolves latest)
gh workflow run "Generate Release" --repo SonnyCavallaro/bazzite-63 -f stream_name=stable

# List published releases
gh release list --repo SonnyCavallaro/bazzite-63

# Preview what the weekly GHCR cleanup would prune (no destructive action)
gh workflow run "Cleanup GHCR" --repo SonnyCavallaro/bazzite-63 -f dry_run=true
```
