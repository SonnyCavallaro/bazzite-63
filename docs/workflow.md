# Workflow

## Phase development cadence

1. **Plan + scout**: read upstream sources (Aurora, Bazzite, Bazzite-DX, AmyOS) for the
   packages/files in scope; verify what the Bazzite base already ships
   (`podman run --rm ghcr.io/ublue-os/bazzite:<TAG> rpm -q …`). Skip what upstream handles
   well.
2. **Implement**: one numbered MX script per domain (`<NN>-<domain>.sh`) under
   `build_files/mx/`, plus any `system_files/` content.
3. **Extend smoke tests**: add `<DOMAIN>_RPMS` / `<DOMAIN>_UNITS` arrays to
   `build_files/tests/10-tests-mx.sh`. Tests are part of the build, not a separate harness.
4. **Pre-flight locally**: `podman build` for the `bazzite` flavour (no NVIDIA — the
   riskiest single shot covers ~95% of failure modes), ~5 min. Use the `/preflight` slash
   command if available.
5. **Iterate** on a red pre-flight. Never push a red build to CI; the pre-flight is the
   cheapest debugging surface.
6. **Commit** when green: Conventional Commits, descriptive body, no attribution trailer.
7. **Pause for user confirmation** before pushing — even a green pre-flight must not
   auto-trigger 6 CI jobs without explicit go-ahead.
8. **Push** → CI matrix (3 flavours × 2 streams = 6 jobs).
9. **Monitor** via a polling background bash script (`gh run view --json` loop with
   `sleep 60`). The harness notifies on completion; do not manually check repeatedly.
10. **Verify** all 6 jobs `success`; otherwise debug from logs and iterate.
11. **Cleanup local images** after CI confirmation
    (`podman rmi <preflight-tag> && podman image prune -f`).

## When to do a code review round

A formal review (via `feature-dev:code-reviewer` agent or fresh-eyes self-review) is
justified after a phase introducing **multiple new patterns** (Phase 2: container runtime +
COPR pattern + repo isolation; Phase 3: virt + groups service + new `system_files/` shipping
pattern), whenever we suspect "this might have bugs we're not seeing yet", and before each
significant phase — it forces explicit verification of patterns carried forward. After a
review, **fix immediately** — do not let issues stack.

What review historically caught (as of 2026-05-02):

- Phase 1+2 review (5 issues): dnf5 setopt no-op, brittle `for s in $(ls)`, validate-repos
  catch-all design, supply-chain vendoring of docker-ce.repo, dnf vs dnf5 inconsistency.
- Phase 3 review (2 issues): missing `After=local-fs.target` on groups service,
  `is-enabled` exit-code semantics.

## When to skip a phase

If upstream Bazzite / Aurora-DX / AmyOS handles a domain better than what we'd produce,
**skip**. Phase 5 (Cockpit) is the canonical example — see
[`architecture.md`](architecture.md) § Cockpit pattern for the full quadlet rationale. When
you skip, document **why** in the commit message and in
[`wins-over-upstream.md`](wins-over-upstream.md) so future sessions don't re-derive the
decision.

## CI behaviour to know about

### `paths-ignore`

Both `build-stable.yml` and `build-testing.yml` have:
```yaml
paths-ignore:
  - "**.md"
  - "LICENSE"
  - "docs/**"
  - "site/**"
  - ".github/workflows/deploy-pages.yml"
```

GitHub semantics: the workflow runs if **any** changed file fails to match. A commit
touching only `*.md` files inside `docs/` does NOT trigger a build; a commit touching
`.gitignore` or `.claude/settings.json` (neither matches) DOES. Extending paths-ignore
(e.g. adding `.claude/**`, `.gitignore`) still triggers ONE build for the commit doing so —
workflow files never match paths-ignore — after which docs-only commits become free.

### Concurrency

```yaml
concurrency:
  group: bazzite-mx-stable-${{ github.ref_name }}   # build-testing.yml: bazzite-mx-testing-…
  cancel-in-progress: false
```

The group is a **literal** kebab-case string, never `${{ github.workflow }}` — the full
rationale (chained `workflow_call` deadlock) is AGENTS.md critical convention #8. Per-ref
scoping via `github.ref_name` lets `develop` runs proceed in parallel with `main` instead of
queueing behind it. `cancel-in-progress: false` — in-flight runs complete, never
auto-cancelled.

### Watch Upstream

A separate workflow runs hourly via `cron`, detects new Bazzite stable / testing releases,
and re-triggers `build-*.yml` against the same commit to refresh the image with the new
base — the published image lags upstream by ≤ 1 hour per stream. GitKraken (URL-fetched RPM)
therefore auto-updates within 1 hour of a release, since every triggered build re-fetches
the URL.

### Cosign signing

Each successful build job signs the pushed image **by digest** with cosign, using the secret
`SIGNING_SECRET` (private key counterpart of `cosign.pub` in this repo). Verify a deployed
image:

```bash
cosign verify --key cosign.pub ghcr.io/matrixdj96/bazzite-mx:latest
```

The local `cosign.key` is gitignored — only on the maintainer's machine and in GitHub
secrets.

## Communication during a session

### When the user asks a "where did this come from?" question

Always answer with **file:line** evidence, never "I think it's standard". Three commands
cover most provenance checks:

```bash
# Was this in Aurora upstream's DX install? (against a local clone)
grep -n '<token>' <aurora-clone>/build_files/dx/00-dx.sh

# Was it in Bazzite-DX?
grep -n '<token>' <bazzite-dx-clone>/build_files/20-install-apps.sh

# Is it already in Bazzite base?
podman run --rm ghcr.io/ublue-os/bazzite:<TAG> bash -c 'rpm -q <pkg>'
```

If the answer is "proposed from training data", say so — cite the reasoning, never pretend
it's from upstream. Hallucinated provenance erodes trust.

### When proposing additions

Format: a small table comparing **cost** / **value** / **provenance**, with an explicit
recommendation, so the user picks from clearly-attributed options rather than approving an
opaque list. Example:

| Item | Origin | Cost | Value | Recommendation |
|---|---|---|---|---|
| `flatpak-builder` | Aurora-DX + Bazzite-DX | 5 min, ~80 MB | medium | include |
| `git-credential-libsecret` | my proposal (validated in Aurora base) | 2 min, ~50 KB | medium-high | include |

### When the user pushes back

Re-verify the claim from the source — the user is often right, especially about taxonomy
("does GitKraken belong in `30-ide.sh`?"), provenance ("did you take this from Aurora-DX or
just guess?"), or scope ("do we really need this?"). Apologize briefly if the verification
proves you wrong, then fix.

## Fix-forward policy

When a hardening issue is discovered post-ship (review round, user question, CI failure):

- **Fix in a separate refactor commit**, never via `git commit --amend` or
  `git push --force` — clearer history, safer reverts.
- The fix commit's body references the discovering source ("from a code review of Phase 3",
  "from a user question after Phase 4 ship").
- Multiple small fixes landing together are grouped by theme in one commit (e.g. a single
  `refactor(<domain>)` bundling several review findings).

## Session etiquette

- The user explicitly says "vai" / "procedi" before destructive ops (commit, push, rmi).
  Don't act preemptively.
- The user appreciates concise verdicts ("PROCEED" / "FIX FIRST") over long debates: pick a
  side, give the reasoning in 2 sentences.
- Sessions can run very long when productive; don't pre-emptively suggest stopping without a
  clear natural break. The user signals stop time explicitly ("ti devo chiedere di
  chiudere", "stanotte basta").
