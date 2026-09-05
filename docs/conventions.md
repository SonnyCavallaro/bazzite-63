# Conventions

## Bash scripts (everything under `build_files/`)

- **Shebang**: `#!/usr/bin/bash` (Bazzite ships bash at that path); host-side scripts
  (`.claude/hooks/`, `.github/scripts/`) use `#!/usr/bin/env bash` (portable across dev
  hosts and CI runners).
- **Strict mode**: `set -euxo pipefail` for orchestration scripts and the
  numbered `build_files/mx/*.sh` install scripts. The `-x` is intentional —
  we want every command echoed in CI logs so a failure can be located
  precisely.
  - **Exception**: `validate-repos.sh` uses `set -eou pipefail` (no `-x`)
    because its own `echo` output is the report and `-x` would garble it.
    This deviation is Aurora upstream's choice; we kept it for parity.
  - **Exception**: sourced helper libraries (`copr-helpers.sh`,
    `writeback-helpers.sh`) use `set -euo pipefail` (no `-x`): the caller's
    own `-x` already echoes every command the helpers run.
  - **A presence test never pipes into `grep -q` under `pipefail`**: `grep -q`
    exits at the first match, the producer takes SIGPIPE on its next write and
    the pipeline reports 141 — the guard fails exactly when the thing IS there,
    and only once the producer's output outgrows one write, so a small list
    passes for weeks (gotchas #30, #49). Read the source directly (a file
    argument, a here-string, a bash loop over the parsed array) or capture the
    output first and test the captured value.
- **Log grouping**: wrap script body with
  `echo "::group:: ===$(basename "$0")==="` and `echo "::endgroup::"` so
  GitHub Actions UI nests the output collapsibly.
- **Don't hide errors**: never `|| true` to silence failures unless the
  failure is genuinely benign (e.g., masking a non-existent service file is
  acceptable; an `install` failing is not).
- **Loops over arrays**: prefer `for item in "${ARRAY[@]}"; do ...; done` to
  repeated commands. Easy to extend, easy to test.
- **Script enumeration**: when iterating files matching a pattern, use
  `mapfile -t list < <(find DIR -maxdepth 1 -type f -name 'PATTERN' | sort -V)`
  rather than `for f in $(ls ...)`. The latter splits on whitespace and
  silently fails on empty matches under `set -e`. The `sort -V` (version
  sort) ensures `10-foo.sh` comes before `20-foo.sh` before `30-foo.sh`
  before `100-foo.sh`, unlike alphabetic sort.

## Writing base-image files

A build step that modifies a file the base image already ships writes into an
overlayfs **copied-up** inode, and the 6.17-azure kernel on runner image
`ubuntu-24.04 20260816+` loses page writeback of exactly those writes. In-build
reads answer from warm page cache, so the build stays green while the committed
layer carries a NUL tail — the shape that shipped a `ujust`-killing master
justfile in release `44.20260826.1` (gotcha #40).

A file the build **creates** lives natively in the upper layer and is
unaffected. Among the tools that touch an existing file, only the ones writing
a temporary and renaming it land on a fresh inode — measured by upstream
bazzite-mx on 2026-08-28 with `stat -c %i` on the host and inside an overlay
container:

| Idiom | Inode | Class |
|---|---|---|
| `sed -i`, `install`, `mv` (same-fs and cross-fs), `rsync`, `depmod`, `cp --remove-destination` | replaced | safe |
| `>>`, `cat tmp > file`, `cp src dst`, `tee`, `curl -o`, `truncate`, sqlite writes | kept | **exposed** |

**The rule**: a script whose last write to a base-image file uses an exposed
idiom calls `rewrite_fresh_inode` on that file before it exits.

```bash
# shellcheck disable=SC1091
source /ctx/build_files/shared/writeback-helpers.sh
...
grep -qxF "$line" "$FILE" || echo "$line" >> "$FILE"
rewrite_fresh_inode "$FILE"
```

`rewrite_fresh_inode` copies with `--preserve=mode,ownership,timestamps`,
fsyncs, and renames — so a stripped justfile keeps the `0644` `ujust` needs.
Every writer of a file rewrites what it wrote, so the guard survives a
reordering of the numbered scripts: `55-justfile-reconcile.sh` rewrites the
master justfile and `56-justfile-import-63.sh`, the last writer, rewrites it
again after its own append; `68-flatpak-apps.sh` rewrites the Flatpak install
list it extends.

A tool's side effect counts as a write: `dnf5 copr disable` flips `enabled=`
in place, so `copr_install_isolated` rewrites the COPR's `.repo` file — the one
for `ublue-os/packages` lands on a path the base image already ships, and
`validate-repos.sh` enforces the very value it carries. `61-chrome-rpm.sh`
(`/etc/xdg/mimeapps.list`) and `62-plasma-fonts.sh` (`/etc/xdg/kdeglobals`,
written through `kwriteconfig6`) close with the same rewrite, so their
guard never rests on a tool's write idiom.

For a database the tool owns, use its own atomic rewrite instead: `build.sh`
step 4 runs `VACUUM INTO` + `os.replace` over the rpmdb, then drops the `-wal`
/ `-shm` sidecars the vacuum folded in; step 5 hardlinks the rewritten rpmdb
into `/usr/lib/sysimage/rpm-ostree-base-db/`, so `rpm-ostree status` on a host
describes this image and not plain Bazzite. The other route is not to ship the
database at all: `clean-stage.sh` empties `/usr/lib/sysimage/libdnf5/`, which
took libdnf5's transaction history off this surface (and keeps the libdnf5
chunk identical between builds).

Detection is the other half, and it lives in
[`.github/scripts/check-image-integrity.sh`](../.github/scripts/check-image-integrity.sh)
— see § Smoke tests below.

## Comments in code

- **WHY, not WHAT**. Well-named identifiers and `set -euxo pipefail` already
  tell you what each line does.
- Cite **provenance** in non-obvious patterns: "ported from Aurora upstream",
  "lifted 1:1 from bazzite-dx", "verified empirically 2026-05-02 against
  dnf5 5.x".
- Cite **discovered gotchas**: e.g., the `sed` pattern in
  `10-container-runtime.sh` has a 4-line comment explaining why setopt is a
  no-op on addrepo files. This is load-bearing — without it, the next person
  refactoring will revert to setopt and silently break repo isolation.
- Avoid "added for issue #X" comments. They rot. The PR / commit body is the
  right place.

## Git

### Commit messages

- **Conventional Commits**: `<type>(<scope>): <subject>`.
  - `feat(mx): …` — new functionality (a phase landing)
  - `refactor(mx): …` — restructuring without behaviour change (hardening,
    splits, vendoring)
  - `fix(mx): …` — bug fix in the build pipeline / smoke test / ujust recipe
  - `docs(plan): …` / `docs(repo): …` — documentation only
  - `ci(...)`, `chore(...)`
- Subject ≤ 70 chars, imperative mood.
- Body explains the WHY, not the WHAT. Reference upstream comparisons,
  measurement results, and discoveries (e.g., "verified on Bazzite
  44.20260501 / dnf5 5.x").
- **No attribution trailer** (`Co-Authored-By`, `Generated-By`,
  `Assisted-By`, …) unless the user explicitly asks for it on a specific
  commit.

### Push behaviour

- **Always pause for user confirmation before `git push`**. Even on a clean
  pre-flight, the push triggers 2 CI jobs and is visible to the world.
- **Never** `--force`, `--no-verify`, or `--amend` without an explicit ask.

### Commit splitting

- **One concern per commit**. If a phase introduces both new functionality
  and a refactor, split into two commits with clear messages (`feat(...)`
  + `refactor(...)`).
- **Mode changes** (chmod +x) belong with the file's introducing commit
  when possible; standalone "chmod +x drive-by" lines in a refactor commit
  body are acceptable.

## dnf5 quirks (CRITICAL — keep this in working memory)

| Quirk | Consequence | Workaround |
|---|---|---|
| `dnf5 config-manager setopt <id>.enabled=0` is a **silent no-op** on .repo files added via `addrepo --from-repofile=URL` or `--repofrompath` | Repo stays enabled in the image despite the call returning 0 | `sed -i 's/^enabled=1/enabled=0/g' /etc/yum.repos.d/<file>.repo` |
| `dnf5 -y install --enablerepo=<id> …` is a **runtime-only override** | The .repo file's persistent `enabled=` value is unchanged | Pair with a vendored `enabled=0` repo file; install is one-shot, file remains correctly disabled |
| `dnf` (dnf4 binary) is a compat shim on F44+ | May not support some setopt syntaxes identically | Always invoke `dnf5` directly in build scripts |
| `dnf5 install <file.rpm>` works on a downloaded RPM | Lets us install packages with no upstream yum repo (e.g., GitKraken: fetched with curl from its "latest" URL, header and payload digests verified with `rpm -K --nosignature`, then installed from `/tmp`) | Use sparingly; when the vendor signs nothing the trust anchor is TLS to the vendor plus the RPM's own digests — never a sha256 pin on a moving URL (gotcha #48) |

## Repo isolation invariant

Every third-party repo file in `system_files/etc/yum.repos.d/` ships
`enabled=0`. The single authoritative enumeration is
`build_files/shared/third-party-repos.list`, one basename per line.
`validate-repos.sh` reads it and hard-fails the build on any listed repo left
`enabled=1` **or listed but absent from the image** — the list is authoritative
in both directions: an absent entry means a renamed upstream repo file or an
install script that stopped shipping it, and tolerating it leaves the renamed
file unenforced (base `44.20260831` renamed `fedora-multimedia.repo` to
`negativo17-fedora-multimedia.repo`; the tolerant loop said nothing). A `?`
prefix marks an optional entry — enforced `enabled=0` when present, tolerated
when absent — for repos the base has shipped before and may ship again.
`reusable-build.yml` hands the same file to `check-image-integrity.sh`, which
re-proves both rules on the chunked image's cold bytes — a torn tail that drops
an `enabled=` line makes dnf treat the section as ENABLED, so the warm check
alone is not enough. The current entries:

```
negativo17-fedora-multimedia.repo
tailscale.repo
vscode.repo
docker-ce.repo
1password.repo
teackot-msi.repo
fedora-cisco-openh264.repo
?fedora-coreos-pool.repo
terra.repo
terra-extras.repo
terra-mesa.repo
google-chrome.repo
```

The lean image vendors only a subset of these files in git
(`system_files/etc/yum.repos.d/`: docker-ce, vscode, 1password, teackot-msi,
google-chrome); the others come with the Bazzite base. `mozilla.repo` is not
listed: it left with the Firefox RPM, and a listed-but-absent entry now fails
the build. The rule applies regardless: any new third-party repo must be added
to `third-party-repos.list` and must ship `enabled=0`.

When adding a new third-party repo:

1. Vendor the .repo file in `system_files/etc/yum.repos.d/<name>.repo` with
   `enabled=0`.
2. Add `<name>.repo` to `build_files/shared/third-party-repos.list`.
3. Use `dnf5 -y install --enablerepo=<section> <pkg>` in the mx script.

Prefer Flatpak / `brew` / `mise` for new tools before reaching for a baked
RPM and a new vendor repo.

The catch-all sweep at the bottom of `validate-repos.sh` is **informational
only** — it lists every other `.repo` file's enabled state but does not
fail the build, because the core Fedora repos (`fedora.repo`,
`fedora-updates.repo`, `fedora-updates-archive.repo`) are legitimately
`enabled=1`. They are the only three left enabled in the shipped image, so a
fourth line in that sweep is a third-party repo nobody registered. A base-image
repo that must ship disabled is registered in the list like any other and
disabled by a `sed` in `clean-stage.sh` (`terra-mesa.repo`, the one the base
ships file-level `enabled=1`); upstream's own `repos.override.d` route is
invisible to both validators.

## COPR install pattern

Use `copr_install_isolated <user/copr> <package1> [package2…]` from
`build_files/shared/copr-helpers.sh`. The function does:

```
dnf5 -y copr enable <user/copr>
dnf5 -y copr disable <user/copr>
dnf5 -y install --enablerepo=copr:copr.fedorainfracloud.org:<user>:<copr> <packages>
```

The COPR is enabled briefly (so dnf can write the .repo file with
metadata), immediately disabled (so the file becomes `enabled=0`), then the
runtime-only `--enablerepo=` flag during install pulls the packages without
flipping the file back.

For `*-release` style RPMs (e.g., a hypothetical `tailscale-release` that
drops a .repo file via post-install scriptlet), use `thirdparty_repo_install`
which sed's the resulting file rather than calling setopt.

## Smoke tests (`build_files/tests/10-tests-mx.sh`)

- **One numbered file**, extended in-place per phase.
- Per-phase pattern:
  ```bash
  # --- Phase N: <domain> packages ---
  <DOMAIN>_RPMS=( pkg1 pkg2 ... )
  for p in "${<DOMAIN>_RPMS[@]}"; do
      rpm -q "$p" >/dev/null || { echo "FAIL: rpm $p missing"; exit 1; }
  done

  # --- Phase N: <domain> services ---
  <DOMAIN>_UNITS=( foo.service bar.socket )
  for u in "${<DOMAIN>_UNITS[@]}"; do
      state=$(systemctl is-enabled "$u" 2>/dev/null || echo missing)
      if [ "$state" != "enabled" ]; then
          echo "FAIL: $u not enabled (state=$state)"
          exit 1
      fi
  done
  ```
- The `state=$(... || echo missing)` pattern matters: `systemctl is-enabled`
  exits 0 also for `static`, `linked`, `indirect`, `alias` — we want
  `enabled` literally. The diagnostic `(state=$state)` in the FAIL message
  saves debugging time.
- File-existence checks: prefer `[ ! -x "$path" ]` for executables, plus a
  content check via `grep -q '<pattern>'` if the content matters.

### The cold post-rechunk check

Every assertion in `10-tests-mx.sh` is a **warm** read: it answers from the
page cache the build just filled, so it cannot see a torn tail on disk.
`.github/scripts/check-image-integrity.sh` re-proves the same artefacts on the
chunked image, whose read path surfaces the committed bytes.
`reusable-build.yml` mounts it into `localhost/chunked-img` and runs it right
after the rechunk, before any GHCR push. Builds outside `main` (a branch
dispatch, a PR) never rechunk, so the same script runs there against `raw-img`
(the sandbox step, gated on `PUSH_ENABLED` being false): a warmer read that
still catches the logical classes — script regressions, malformed artefacts,
lost lines.

It carries two nets, because they fail differently:

- a **NUL sweep** over every build-mutated text artefact — a torn tail wherever
  it lands. Each named path must exist and each glob group must match a file,
  so an upstream rename fails the check instead of emptying it;
- **per-artefact probes** for a tear that ends on a clean boundary, which the
  sweep cannot see: `PRAGMA integrity_check` on the rpmdb and on the relinked
  `rpm-ostree-base-db` (equal row counts prove the step 5 hardlink) plus their
  absent sidecars, the emptied `/usr/lib/sysimage/libdnf5/`, a real
  `just --summary` parse of the master with its import tree (the three
  downstream imports, `96-bazzite-63.just` included), a JSON parse of
  `image-info.json` and the rewritten `bazzite-63` identity, the appended
  blocklist deny line and the appended tail of the Flatpak install list, each
  out-of-tree module resolving through the binary `modules.dep.bin` index,
  every repo section — of the `third-party-repos.list` entries (present, or
  `?`-optional) and of the COPR/RPM Fusion name classes — reading as disabled
  under dnf5's own truth table (`0/false/no/off` only; a missing `enabled=`
  line or a torn-away section header reads as ENABLED), and the base's
  versionlock pins (kernel, mesa) surviving the stage. The recipes of the three
  downstream `.just` files must all survive the parse: a truncated file parses
  fine with fewer.

Adding an artefact to the build adds it to the sweep list. A new or changed
probe is proven on a known-bad input before its first green run is trusted,
and the proof is code, not a procedure: `check-image-integrity.sh --self-test`
applies one lesion per section inside a throwaway container of the checked
image (last section first, so each lesion is the first failure the child run
meets) and requires every section to die on its own message.
`reusable-build.yml` runs it after the cold check on every sandbox build. A new
probe ships with its lesion in the self-test list; a probe with no lesion is a
probe nobody has seen fail. The lesions name the fork's artefacts (the
`org.virt_manager.virt-manager` deny line, `VARIANT_ID=bazzite-63`): a lesion
on a file the fork does not ship is never caught and fails the self-test.

## Vendoring third-party content

- **Default**: vendor the `.repo` file in git under
  `system_files/etc/yum.repos.d/`. Auditable diff in PR review.
- **Exception (URL-only RPMs)**: when the upstream vendor doesn't publish a
  yum repo — only a stable RPM URL — download it with `curl -fsSL -o`, verify
  the RPM's own header and payload digests with `rpm -K --nosignature`, log the
  version fetched, then `dnf5 install` the local file. Document in the script
  why we deviate and what the trust model is. A sha256 pin belongs only to a
  versioned, stable URL: behind a "latest" redirect it turns every vendor
  release into a failed build (gotcha #48).
  Current example: GitKraken (`35-git-tools.sh`,
  `https://release.gitkraken.com/linux/gitkraken-amd64.rpm` — an unsigned RPM
  behind a "latest" redirect; the build takes the current release and the
  trust anchor is TLS to the vendor plus the package's digests).

## When probing third-party download URLs

- Use `curl -sL --range 0-1023 <url>` (GET partial 1KB), not `curl -I`
  (HEAD). Several CDNs reject HEAD; we hit this with GitKraken (HEAD
  returned 404, GET worked). Probing with GET also lets you `file` /
  `xxd` the bytes to verify it's an RPM.

## File permissions

- Scripts under `build_files/mx/`, `build_files/shared/`, `build_files/tests/`
  → **mode 755** (`chmod +x`). systemd unit files → **mode 644**.
- Verify before commit: `git ls-files --stage | grep '^100755'`. If a script
  was created mode 644 by accident, fix with
  `chmod +x <file> && git update-index --chmod=+x <file>`.

## VSCode user defaults

In `system_files/etc/skel/.config/Code/User/settings.json`. Currently
**minimal**:

```json
{ "update.mode": "none" }
```

Only the atomic-correctness fix (VSCode's self-updater fights a read-only
/usr). No font, theme, or formatter opinions imposed at distro level —
those are user choices.

## VSCode repo

- `gpgcheck=1` is correct on Bazzite 44 — verified 2026-05-01 that the
  Microsoft .asc key (0xBE1229CF, fingerprint
  BC528686B50D79E339D3721CEB3E94ADBE1229CF) imports cleanly during the
  first dnf5 transaction. Bazzite-DX upstream sets `gpgcheck=0` due to a
  historical "FIXME: signature broken" — that comment is outdated for our
  target.
- **General rule**: verify an upstream claim by reading the code, not the
  comments — an upstream `FIXME` or workaround may already be stale (the
  `gpgcheck` case above is the canonical instance). Read the code, run a
  quick test before copying a pattern.
