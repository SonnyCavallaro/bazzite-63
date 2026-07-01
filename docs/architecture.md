# Architecture

How the image is built, what each stage may touch, and where the state of a build lives. How a
build reaches a host is [`workflow.md`](workflow.md); why each feature exists is
[`divergences.md`](divergences.md).

Contents: build flow · `.github/scripts/` · `build_files/` · `system_files/` · state of a build ·
gates, in order.

## Build flow

```
Containerfile
  ctx           FROM scratch, COPY build_files, system_files, cosign.pub   bound at /ctx, never in the image
  image         FROM ${BASE_IMAGE}, bazzite-mx's :stable by digest, its signature verified before the build
    RUN /ctx/build_files/build.sh                  mounts: /var/cache and /var/log (cache), /run and /tmp (tmpfs)
    RUN /ctx/build_files/tests/run.sh              offline; tmpfs on /run, /tmp, /var/log, /var/cache
    RUN rpm -V --nomtime python3-setuptools && bootc container lint …    offline; tmpfs on /run
```

Why `/run` is a tmpfs is on the `RUN` itself in the `Containerfile`.

`BASE_IMAGE` is `ghcr.io/matrixdj96/bazzite-mx@sha256:…` and `IMAGE_NAME` is `bazzite-63`, both
written by `resolve-base.sh bazzite-mx`, the one flavour; `VERSION` is the version the image
calls itself: the release tag, or `<base version>.dev` for a sandbox or pre-flight build. CI
and `/preflight` resolve the base to a digest with `.github/scripts/resolve-base.sh`, which also
reads the base's kernel from its `ostree.linux` label, and refuse it unless `verify-base.sh`
finds bazzite-mx's signature on that digest. They take `VERSION` and every `--label` from
`.github/scripts/image-labels.sh`; `10-image-info.sh` repeats the `.dev` rule for a
`podman build` by hand with no `VERSION`.

## .github/scripts/

Each script owns one artefact and ships a `--self-test`.

| Script                                            | Role                                                                                                                                                                                                                                                 |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib.sh`                                          | coordinates, `exit_with_error`/`print_error`, `require_option_value`, `emit`, `read_env`, `image_of`, `absent_error`, `TAG_SHAPE`, `fail_self_test`; sourced by all but `check-form.sh` and `check-commits.sh`                                       |
| `resolve-base.sh <flavour> \| --digests`          | the base's digest, version and kernel, and the image name; the base digest keyed by flavour                                                                                                                                                          |
| `verify-base.sh <base image>`                     | bazzite-mx's signature on the resolved digest, checked against `base-cosign.pub`; a tag refused                                                                                                                                                      |
| `image-labels.sh <coords> <tag> <rev>`            | the labels file; the coordinates as `resolve-base.sh` wrote them                                                                                                                                                                                     |
| `check-image.sh <image> <labels>`                 | the probe of a built image: labels, `/run` and `/tmp`, lint, packages, the base's modules, the route of the type `ntfs`, `image-info.json`                                                                                                           |
| `release-tag.sh <coords> \| --tag <tag> <coords>` | the release tag, `.N` one past the day's highest taken suffix, never a gap; a forced tag, refused when malformed, on another Fedora or taken                                                                                                         |
| `gate-release.sh release\|promote`                | verify by digest, write `:<tag>`, promote `:stable`                                                                                                                                                                                                  |
| `changelog.sh release`                            | the release notes and the release title                                                                                                                                                                                                              |
| `install-oras.sh <version> <dir>`                 | the ORAS CLI, tarball refused on a checksum mismatch                                                                                                                                                                                                 |
| `refresh-pins.sh`                                 | the pin table (`--check`) and the rewrite (`--apply`)                                                                                                                                                                                                |
| `check-commits.sh [<rev>]`                        | the commit-message rules (§ Commits of `conventions.md`) over every commit reachable from `<rev>`                                                                                                                                                    |
| `check-form.sh <file>...`                         | the form rules (§ Bash → Form of `conventions.md`): line width, the banned control-flow shapes and the four failure shapes (`\| grep -q`, `\|\| echo` fallback, a pipeline assigned without `\|\| true`, a `$( )` inside `$(( ))`), on logical lines |
| `preflight-build.sh [<flavour>] [--no-cache]`     | the local pre-flight: base resolved and verified, labels, build, log judged on the scripts' own output, probe                                                                                                                                        |
| `watch-upstream.sh check\|decide\|weekly`         | the base-digest verdict, and whether the watcher or the weekly trigger dispatches                                                                                                                                                                    |

## build_files/

| Path                    | Role                                                                                                                                         |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `build.sh`              | runs `NN-<feature>.sh` in version order, one group each, stops at the first failure                                                          |
| `lib/env.sh`            | sourced first: `CTX`, `BUILD_FILES`, `BUILD_TMP`, `BUILD_STATE`, `PYTHONDONTWRITEBYTECODE`, then every library                               |
| `lib/log.sh`            | `group`, `endgroup`, `log`, `fail_build`                                                                                                     |
| `lib/repos.sh`          | `install_from_repo`, `enabled_repos`                                                                                                         |
| `lib/just.sh`           | `recipe_set`; output captured before any grep                                                                                                 |
| `lib/gpg.sh`            | the `KEY_FPR` table of this image's vendor keys, `key_fingerprint` and `assert_key_fingerprint`                                              |
| `00-prep.sh`            | dnf keeps its cache and waits 60 s against COPR and mirror flakes; the base's repositories are recorded                                      |
| `01-system-files.sh`    | `rsync` of `system_files/` over the tree, every file on a fresh inode                                                                        |
| `10-image-info.sh`      | identity: `image-info.json`, os-release, the KDE About page                                                                                  |
| `11-image-signing.sh`   | the public key and the `policy.json` scope for `ghcr.io/sonnycavallaro`, next to the base's                                                  |
| `12-host-helpers.sh`    | the base's `migrate`, `verify-host` and `host.sh` renamed onto `ghcr.io/sonnycavallaro`, each anchor checked first                           |
| `40-firefox-flatpak.sh` | bazzite-mx's Firefox RPM removed, its Flatpak deny line dropped, the helpers' Firefox check and step 8 item replaced, each anchor checked    |
| `90-validate-repos.sh`  | the repository gate, run after the last install                                                                                              |
| `95-clean-stage.sh`     | the tree bootc lint and the rechunk expect                                                                                                   |
| `tests/run.sh`          | the test runner and the pairing guard                                                                                                        |
| `tests/lib.sh`          | the checks the tests share, one `OK:`/`FAIL:` line each                                                                                      |
| `tests/NN-<feature>.sh` | one smoke test per build script, same stem                                                                                                   |

Numbering: `00-09` preparation, `10-19` identity, trust and the base's
helpers, `40-49` packages and desktop defaults, `70-79` justfile, `90-99` gates and cleanup.
The file name is the only statement of the order.

## system_files/

One tree, copied over `/` by `01-system-files.sh`.

| Path                                              | Content                                |
| ------------------------------------------------- | -------------------------------------- |
| `etc/containers/registries.d/sonnycavallaro.yaml` | sigstore attachments for our own scope |

## State of a build

| Where                                              | Lifetime                       | Content                                         |
| -------------------------------------------------- | ------------------------------ | ----------------------------------------------- |
| `/tmp/bazzite-63-build/` (`BUILD_TMP`)             | the build `RUN` (tmpfs)        | backups a later script restores                 |
| `/usr/lib/bazzite-63/build-state/` (`BUILD_STATE`) | shipped in the image           | the base's repository snapshots                 |
| `/var/cache`, `/var/log`                           | cache mounts, not in the image | the dnf cache and logs                          |

`BUILD_STATE` is a directory of its own: bazzite-mx's `/usr/lib/bazzite-mx/build-state`, which
its `verify-host` reads on every host, keeps naming Bazzite's repositories.

## Gates, in order

1. `verify-base.sh`, before the build: the base digest carries bazzite-mx's signature.
2. `90-validate-repos.sh` after the last install: the image ships no enabled third-party
   repository, the enabled set read from `dnf5 repolist` itself, and no modified base
   repository.
3. `tests/run.sh`: every feature's smoke test on the cleaned tree, offline.
4. `rpm -V --nomtime python3-setuptools`, then `bootc container lint --fatal-warnings`: the
   last word, offline; `rpm -V` sees a packaged `.pyc` the build or the test RUN rewrote
   ([`gotchas.md`](gotchas.md) § A scriptlet rewrote a packaged `.pyc`).

Every gate is proven on a known-bad input before it counts ([`conventions.md`](conventions.md)
§ Positive control).
