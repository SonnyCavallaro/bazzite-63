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
- **Exception — Google Chrome is baked** (system RPM, `build_files/mx/61-chrome-rpm.sh`,
  vendored `google-chrome.repo`): present for every user at the OS level, default
  browser via build-time XDG merge; updates ride image rebuilds.
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
   `system_files/etc/yum.repos.d/`, register the basename in
   `build_files/shared/third-party-repos.list`, install via
   `dnf5 -y install --enablerepo=<section> <pkg>`. The validator hard-fails the
   build if a **registered** repo is left enabled OR is listed but absent from
   the image (a base rename must be mirrored in the list; `?` prefix = optional
   entry, enforced only when present) — registration is the load-bearing step,
   because its catch-all sweep over the remaining `.repo` files only lists
   them, so an unregistered repo left `enabled=1` ships silently. (Vendored
   repos: the bazzite-mx baseline — docker-ce, vscode, 1password, teackot-msi —
   plus our google-chrome; `mozilla.repo` left with the Firefox RPM; prefer
   Flatpak / `brew` / `mise` for new tools before reaching for a baked RPM.)

3. **The build runs in CI, not locally.** A full Bazzite image build is heavy and
   impractical on a non-Linux dev box. Validate by pushing a branch and
   dispatching `Build Bazzite-63` on it (or opening a PR to `main`): the branch
   policy builds **both streams in parallel without** publishing or signing, and
   runs the sandbox integrity check on each — the whole answer lands in the
   wall-clock of one job (~10-15 min on `ubuntu-26.04`).

4. **The publish step is the cutover.** Merging to `main` builds, signs (cosign),
   and pushes the public image. Treat it as a gated, explicit action.

5. **Conventional Commits**. Never `--force`, `--no-verify`, `--amend` without an
   explicit ask. No AI-attribution trailers.

6. **Provenance citations** when proposing a package or pattern: cite the source
   (upstream Bazzite, bazzite-mx, Aurora-DX, …).

7. **Prefer per-user over baked.** Before adding a baked RPM, ask whether a
   Flatpak, a `brew` formula, or a `mise` runtime serves the need without a
   rebuild/reboot.

8. **CI naming conventions**: Workflow `name:` = Title Case (`Build Bazzite-63`).
   Job/step `name:` = sentence case, imperative + object. Env vars =
   `SCREAMING_SNAKE_CASE`. Input/output keys = `snake_case`, consistent
   cross-workflow (`release_tag` everywhere). Concurrency `group:` = literal
   `bazzite-63-<phase>[-<key>]` kebab-case (NEVER `${{ github.workflow }}` — in a
   `workflow_call` callee it resolves to the caller's name and collides,
   triggering "deadlock detected → canceling"). Shell binaries (`just`, `gh`,
   `podman`) lowercase; acronyms (`GHCR`, `OCI`, `BTRFS`) uppercase.

9. **A base-image file modified in place needs a fresh-inode rewrite**. The
   runner kernel loses writeback of writes into copied-up overlay files, so
   `>>`, `cat tmp > file`, `cp src dst`, `tee`, `curl -o` and sqlite writes ship
   a NUL tail while the build stays green (gotcha #40). Close such a script
   with `rewrite_fresh_inode` from `build_files/shared/writeback-helpers.sh`
   (`56-justfile-import-63.sh`, `61-chrome-rpm.sh`, `62-plasma-fonts.sh` and
   `68-flatpak-apps.sh` are the fork's own callers); `sed -i`, `install`,
   `mv`, `rsync` and `depmod` already rename
   onto a fresh inode. The cold post-rechunk counterpart is
   `.github/scripts/check-image-integrity.sh`, and every probe added to it is
   proven on a known-bad input first.

10. **`validate-just` is a gating job inside `build.yml`** (not a standalone
    workflow). It runs `just --list` on each `.just` file via preinstalled
    Linuxbrew `just`. The `build` job depends on it, so a broken `.just` aborts
    before any GHCR push or release.

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
.github/workflows/          # build, clean, generate-release, reusable-build, sign-image, watch-upstream
.github/scripts/            # changelog.sh (release notes) + list-flavours.sh (the flavour set, one owner: the single bazzite-63 line) + resolve-upstream-tag.sh (latest upstream tag, one owner) + resolve-release-tag.sh + resolve-kernel-coords.sh (akmods carrier flavour) + check-image-integrity.sh (cold post-rechunk + --self-test) + promote-release-tags.sh / verify-published-signatures.sh (per-stream gate + signature proof)
.claude/                    # Claude Code config: settings.json + commands/preflight.md + hooks/shellcheck-edit.sh
cosign.{key,pub}            # .key gitignored; private key lives only in the SIGNING_SECRET GitHub secret
```

## CI flow at a glance

```
push to main / dispatch / watch-upstream (workflow_call) ─►
  build.yml  (ONE run, both streams):
     plan     (stream set → matrix_include JSON: the flavour set of list-flavours.sh — one bazzite-63 line — × selected streams)
     validate-just
       └─► resolve-{stable,testing}  (collision .N on gh release list + GHCR tags)
             └─► build  (reusable-build called ONCE: one 2-job matrix in parallel, rechunk + cold integrity check, staging push + sign per stream)
                  └─► promote-{stable,testing}  (per-stream gate: manifest count vs matrix_include; :stable + :<release_tag> immutable, digest-copied)
                       └─► verify-{stable,testing} ─► gate  (emits stable_ok / testing_ok)
                            └─► release-{stable,testing}  (generate-release.yml, gated on <stream>_ok — one broken stream never sinks the other; stable=latest / testing=prerelease)

watch-upstream     (cron every 6h)   ─► triggers build.yml (streams=both|stable|testing) if upstream changed
clean              (cron Sun 00:15)  ─► prunes the bazzite-63 GHCR package (>90d, keep 7+7)
generate-release   (workflow_call / dispatch) ─► takes stream_name + upstream_tag + release_tag
sign-image         (dispatch)        ─► signs an already-published image by digest, then verifies it
```

The build job runs on `ubuntu-26.04` (healthy IO: a full main job is ~25-40 min, MEASURED
upstream 2026-09-01, against the 2 h+ the degraded `ubuntu-24.04` runners took), restores the
DNF metadata cache between runs (`actions/cache`, keyed on the upstream tag, written by the
stable job only) and stamps the OCI labels inside the rechunk compose instead of a separate
buildah commit cycle.

### Branch policy

| Branch | Build | Rechunk | Push GHCR | Sign | Release |
|---|---|---|---|---|---|
| `main` | ✓ | ✓ | ✓ | ✓ | ✓ (push + watch-upstream + dispatch) |
| any other branch (`gh workflow run --ref <branch>`) | ✓ 2 jobs (1 image × 2 streams) + sandbox integrity check | ✗ | ✗ | ✗ | ✗ — CI sandbox |
| PR to `main` | ✓ 2 jobs (1 image × 2 streams) + sandbox integrity check | ✗ | ✗ | ✗ | ✗ |

A build outside `main` is the safe integration test: it builds both streams
without publishing and runs `check-image-integrity.sh` against each raw image
(`PUSH_ENABLED` false skips the rechunk, so the cold post-rechunk run happens on
`main` only). The testing stream is built there too because its base differs
(kernel, `.repo` set): a stable-only sandbox is blind to testing-base drift.

## Quick command cheatsheet

```bash
# Validate via CI (a full local build is impractical): push a branch and open a PR,
# or dispatch a build-only run on the branch (the only path when the branch was
# rebased onto a rewritten upstream history — such a PR never runs checks)
git push -u origin <branch>
gh pr create --repo SonnyCavallaro/bazzite-63 --base main --head <branch>
gh workflow run build.yml --repo SonnyCavallaro/bazzite-63 --ref <branch> -f streams=both
gh run list --repo SonnyCavallaro/bazzite-63 --limit 4 \
  --json databaseId,workflowName,status,conclusion,headSha,createdAt \
  | jq -r '.[] | "\(.createdAt) | \(.workflowName) | run \(.databaseId) | \(.status)/\(.conclusion // "-") | \(.headSha[0:7])"'

# Publish from main by hand (a force-push of unrelated history fires no push event):
# one run builds, promotes, verifies and releases both streams
gh workflow run build.yml --repo SonnyCavallaro/bazzite-63 --ref main -f streams=both

# Trigger a release manually (stream defaults to stable, upstream auto-resolves latest)
gh workflow run "Generate Release" --repo SonnyCavallaro/bazzite-63 -f stream_name=stable

# Repair an image that ended up published unsigned (signs the resolved digest, then verifies)
gh workflow run "Sign Image" --repo SonnyCavallaro/bazzite-63 \
  -f image=ghcr.io/sonnycavallaro/bazzite-63:<tag>

# List published releases
gh release list --repo SonnyCavallaro/bazzite-63

# Preview what the weekly GHCR cleanup would prune (no destructive action)
gh workflow run "Cleanup GHCR" --repo SonnyCavallaro/bazzite-63 -f dry_run=true
```
