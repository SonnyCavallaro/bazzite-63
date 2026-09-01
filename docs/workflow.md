# Workflow

## Phase development cadence

1. **Plan + scout**: read upstream sources (Aurora, Bazzite, Bazzite-DX, AmyOS) for the
   packages/files in scope, on their FRESH state — fetch/pull the upstream repos before
   comparing, and diff against their latest default branch, never against a stale local copy or
   recollection. Verify what the Bazzite base actually ships
   (`podman run --rm ghcr.io/ublue-os/bazzite:<TAG> rpm -q …`): base-image drift (renamed repo
   files, moved paths) is what breaks downstream guards silently. Skip what upstream handles
   well. **The same pass covers the pinned versions** — see § Keeping the pins fresh.
2. **Implement**: one numbered MX script per domain (`<NN>-<domain>.sh`) under
   `build_files/mx/`, plus any `system_files/` content.
3. **Extend smoke tests**: add `<DOMAIN>_RPMS` / `<DOMAIN>_UNITS` arrays to
   `build_files/tests/10-tests-mx.sh`. Tests are part of the build, not a separate harness.
4. **Pre-flight locally**: `podman build` for the `bazzite` flavour (no NVIDIA — the riskiest
   single shot covers ~95% of failure modes), ~5 min. Use the `/preflight` slash command if
   available; `--cold-check` adds the unified integrity check against the built image (~1 min).
5. **Iterate** on a red pre-flight. Never push a red build to CI; the pre-flight is the
   cheapest debugging surface.
6. **Commit** when green: Conventional Commits, descriptive body, no attribution trailer.
7. **Push to `develop` FIRST** (AGENTS.md convention 4, owner's standing instruction): the
   sandbox run validates the change — all three flavours + integrity check, no rechunk. The
   develop push is still a push: it takes the user's go like any other.
8. **Push to `main`** only after the sandbox is green, with its own user confirmation — even a
   green pre-flight must not auto-trigger 6 CI jobs without explicit go-ahead. The main push →
   CI matrix (3 flavours × 2 streams = 6 jobs) is a release.
9. **Monitor** via the harness's background monitor (one watcher per run, 5-minute cadence,
   terminal-state exit). Never foreground `sleep` loops or repeated manual checks.
10. **Verify** all 6 jobs `success`; otherwise debug from logs and iterate.
11. **Cleanup local images** after CI confirmation
    (`podman rmi <preflight-tag> && podman image prune -f`).

## Keeping the pins fresh

This repo runs **no dependency bot** — no Renovate, no Dependabot — by the owner's decision
(2026-09-01), even though every family repo runs one. The freshness check is the agent's job,
performed while working on the repo, from the upstream sources that are already checked out
next to it. The reasoning: what needs updating here is not a dependency tree but a handful of
pins whose right value is *what the family is running*, and that answer comes from reading the
same upstream repos the scouting step already reads — not from a bot that only knows the
registry's latest tag and cannot see the pairing rules (a cosign 3.x bump needs its
`--new-bundle-format` / `--use-signing-config` flags in the same commit, divergence #23).

**When**: as part of step 1's scouting pass, on any round that touches `.github/`, and at least
once per round otherwise.

**What to compare**, in this order:

1. **GitHub Action pins** — every `uses: <owner>/<action>@<sha> # <version>` in
   `.github/workflows/`. Compare against the family's pin for the same action (`bazzite`,
   `bazzite-dx`, `aurora`, `akmods`, `image-template`) and against the action's own tag refs
   (`gh api repos/<owner>/<action>/git/refs/tags`), which is what resolves a `# vN` comment to
   the SHA it should carry.
2. **The cosign version string** — `cosign-release:` in `reusable-build.yml` and
   `sign-image.yml`, against `gh api repos/sigstore/cosign/releases`. Never bump it alone: the
   flag pairing of divergence #23 lands in the same commit.
3. **Runner labels** — `runs-on:` values against what the family builds on; a retired
   `ubuntu-<NN>.04` image is a scheduled breakage, not a surprise.
4. **Base tag and akmods coordinates** — the latest upstream tags per stream
   (`gh release view/list --repo ublue-os/bazzite`) and, for each base flavour, the akmods
   carrier coordinates `resolve-kernel-coords.sh` would derive (`ostree.linux` label via
   `skopeo inspect`); a flavour moved onto the LTS kernel branch is visible here before it
   aborts a build.
5. **Base drift that breaks our guards** — the checks no version bot can see, derived from the
   repo's own guard sources (never a hardcoded list) against the published base images:
   - `.repo` files renamed or gone: `build_files/shared/third-party-repos.list` vs the base's
     `/etc/yum.repos.d/` (authoritative in both directions — a rename must land in the list, an
     unlisted `enabled=1` newcomer must be registered);
   - upstream just recipes renamed: the `OVERRIDES` manifest in
     `build_files/mx/55-justfile-reconcile.sh` vs the base's `.just` files;
   - new options in the base's `yafti.yml`: vs the `YAFTI_KNOWN` coverage map in
     `build_files/tests/10-tests-mx.sh`;
   - packages entering/leaving bazzite's `build_files/global-remove` (and paths our
     `build_files/` scripts touch in the base) — grep our scripts for what they assume.

**How to report**: drift is a menu item with its changelog and provenance, never a silent bump
— the version number alone does not say whether an update matters. The pass is **two-phase**:
full analysis of every class first, then the user selects per item; a selected bump lands as
its own commit with the changelog summarised in the body, and reaches `main` through the
develop-first flow like any other change.

**Measured precedent** (2026-09-01): `actions/checkout` sat on v7.0.0 while the whole family
had moved to v7.0.1, and `softprops/action-gh-release` on v3.0.1 against bazzite's v3.0.3 —
both invisible, because a SHA pin never announces its own age.

## When to do a code review round

A formal review (via `feature-dev:code-reviewer` agent or fresh-eyes self-review) is justified
after a phase introducing **multiple new patterns** (Phase 2: container runtime + COPR
pattern + repo isolation; Phase 3: virt + groups service + new `system_files/` shipping
pattern), whenever we suspect "this might have bugs we're not seeing yet", and before each
significant phase — it forces explicit verification of patterns carried forward. After a
review, **fix immediately** — do not let issues stack.

What review historically caught (as of 2026-05-02):

- Phase 1+2 review (5 issues): dnf5 setopt no-op, brittle `for s in $(ls)`, validate-repos
  catch-all design, supply-chain vendoring of docker-ce.repo, dnf vs dnf5 inconsistency.
- Phase 3 review (2 issues): missing `After=local-fs.target` on groups service, `is-enabled`
  exit-code semantics.

## When to skip a phase

If upstream Bazzite / Aurora-DX / AmyOS handles a domain better than what we'd produce,
**skip**. Phase 5 (Cockpit) is the canonical example — see [`architecture.md`](architecture.md)
§ Cockpit pattern for the full quadlet rationale. When you skip, document **why** in the commit
message and in [`divergences.md`](divergences.md) so future sessions don't
re-derive the decision.

## CI behaviour to know about

### The develop sandbox

Every change lands on `develop` first (AGENTS.md convention 4): its push runs the same six-job
matrix (3 flavours × 2 streams) plus the sandbox integrity check — no rechunk, no GHCR push, no
release — on its own concurrency group, in parallel with `main`. The jobs run in parallel, so
the sandbox answers in the wall-clock of one (~10 min on ubuntu-26.04). Both collapses were
tried and reverted for the same reason: the base images differ even though the scripts do not.
`bazzite-mx` alone was blind to NVIDIA-only regressions, and **stable alone was blind to
testing-base drift** — `testing-44.<date>` carries its own kernel and `.repo` set, and the
`fedora-multimedia` → `negativo17-fedora-multimedia` rename (2026-08-31) broke a repo guard
exactly there (owner's instruction, 2026-09-01: ~60 runner-min per develop push instead of ~30,
wall-clock unchanged). `main` receives the change once the sandbox run is green; a push to
`main` is a release. PR builds behave like `develop`.

### `paths-ignore`

`build.yml` has:
```yaml
paths-ignore:
  - "**.md"
  - "LICENSE"
  - "docs/**"
  - "site/**"
  - ".claude/**"
  - ".github/workflows/deploy-pages.yml"
```

GitHub semantics: the workflow runs if **any** changed file fails to match. A commit touching
only `*.md` files inside `docs/` or agent config under `.claude/` does NOT trigger a build; a
commit touching `.gitignore` (no match) DOES. Extending paths-ignore still triggers ONE build
for the commit doing so — workflow files never match paths-ignore — after which the ignored
classes become free.

### Concurrency

```yaml
concurrency:
  group: bazzite-mx-build-${{ github.ref_name }}
  cancel-in-progress: false
```

The group is a **literal** kebab-case string, never `${{ github.workflow }}` — the full
rationale (chained `workflow_call` deadlock) is AGENTS.md critical convention #8. Per-ref
scoping via `github.ref_name` lets `develop` runs proceed in parallel with `main` instead of
queueing behind it. `cancel-in-progress: false` — in-flight runs complete, never
auto-cancelled.

One workflow now covers both streams, so one group covers both: a `Watch Upstream` trigger
queues behind an in-flight push run on the same ref instead of racing it (they used to sit on
`bazzite-mx-stable-…` and `bazzite-mx-testing-…`). `reusable-build.yml` is called once per run
and holds one literal group (`bazzite-mx-reusable-{ref}`); only the release callee keeps a
per-stream group (`bazzite-mx-release-{stream}-{tag}`). The two streams of one run live in the
same call, so they cannot collide with each other by construction.

### Watch Upstream

A separate workflow runs hourly via `cron`, detects new Bazzite stable / testing releases, and
re-triggers `build.yml` against the same commit to refresh the image with the new base — the
published image lags upstream by ≤ 1 hour per stream. GitKraken (URL-fetched RPM) therefore
auto-updates within 1 hour of a release, since every triggered build re-fetches the URL.

### Cosign signing

Each successful build job signs the pushed image **by digest** with cosign, using the secret
`SIGNING_SECRET` (private key counterpart of `cosign.pub` in this repo). Verify a deployed
image:

```bash
cosign verify --key cosign.pub ghcr.io/matrixdj96/bazzite-mx:latest
```

The local `cosign.key` is gitignored — only on the maintainer's machine and in GitHub secrets.

An image that ended up published **unsigned** — a build whose sign step failed, or a tag
re-pointed by hand with `skopeo copy` — is repaired with the `Sign Image` workflow
(`sign-image.yml`, dispatch-only), which takes the full `ghcr.io/<owner>/<image>:<tag>`,
refuses anything outside this owner's namespace, signs the resolved **digest** and then
verifies the signature against `cosign.pub` before reporting success:

```bash
gh workflow run "Sign Image" --repo MatrixDJ96/bazzite-mx \
  -f image=ghcr.io/matrixdj96/bazzite-mx:44.20260901
```

## Communication during a session

### When the user asks a "where did this come from?" question

Always answer with **file:line** evidence, never "I think it's standard". Three commands cover
most provenance checks:

```bash
# Was this in Aurora upstream's DX install? (against a local clone)
grep -n '<token>' <aurora-clone>/build_files/dx/00-dx.sh

# Was it in Bazzite-DX?
grep -n '<token>' <bazzite-dx-clone>/build_files/20-install-apps.sh

# Is it already in Bazzite base?
podman run --rm ghcr.io/ublue-os/bazzite:<TAG> bash -c 'rpm -q <pkg>'
```

If the answer is "proposed from training data", say so — cite the reasoning, never pretend it's
from upstream. Hallucinated provenance erodes trust.

### When proposing additions

Format: a small table comparing **cost** / **value** / **provenance**, with an explicit
recommendation, so the user picks from clearly-attributed options rather than approving an
opaque list. Example:

| Item | Origin | Cost | Value | Recommendation |
|---|---|---|---|---|
| `flatpak-builder` | Aurora-DX + Bazzite-DX | 5 min, ~80 MB | medium | include |
| `git-credential-libsecret` | my proposal (validated in Aurora base) | 2 min, ~50 KB | medium-high | include |

### When the user pushes back

Re-verify the claim from the source — the user is often right, especially about taxonomy ("does
GitKraken belong in `30-ide.sh`?"), provenance ("did you take this from Aurora-DX or just
guess?"), or scope ("do we really need this?"). Apologize briefly if the verification proves
you wrong, then fix.

## Fix-forward policy

When a hardening issue is discovered post-ship (review round, user question, CI failure):

- **Fix in a separate refactor commit**, never via `git commit --amend` or `git push --force` —
  clearer history, safer reverts.
- The fix commit's body references the discovering source ("from a code review of Phase 3",
  "from a user question after Phase 4 ship").
- Multiple small fixes landing together are grouped by theme in one commit (e.g. a single
  `refactor(<domain>)` bundling several review findings).

## Session etiquette

- The user explicitly says "vai" / "procedi" before destructive ops (commit, push, rmi). Don't
  act preemptively.
- The user appreciates concise verdicts ("PROCEED" / "FIX FIRST") over long debates: pick a
  side, give the reasoning in 2 sentences.
- Sessions can run very long when productive; don't pre-emptively suggest stopping without a
  clear natural break. The user signals stop time explicitly ("ti devo chiedere di chiudere",
  "stanotte basta").
