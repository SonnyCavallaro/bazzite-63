# Gotchas

Surprises found on this project, or on bazzite-mx in the scripts this repository inherits from
it, that a reader would otherwise rediscover the hard way. Each one says what happens, how and
when it was measured, and what the repository does about it. The rules themselves live in
[`conventions.md`](conventions.md).

Contents, in the order of the entries: torn writeback on 6.17-azure · grep -v on an empty set ·
command | grep -q · podman build labels · stub-resolv.conf left in the image ·
remove-unwanted-software v9 · skopeo and containers-storage · workflow off the default branch ·
setup-oras versions · cosign verify and referrers · rollback onto a pruned tag ·
ghcr-cleanup-action patterns · pre-flight without the changed script · SBOM media type · FAIL
branch before its verdict · 2> /dev/null on a failed redirection · cosign 3.1.3 bundle flag ·
arithmetic error escapes set -e · scriptlet rewrote a .pyc · anonymous GHCR 403.

## Torn writeback on a 6.17-azure runner kernel

A build that modifies a base-image file in place ships that file with a NUL tail. The cases are
`>>`, `cat tmp > file` and an sqlite write, all of which copy the file up into the overlay's
upper layer. Every read made during the build, served from the page cache, sees the right
bytes.

Measured 2026-09-02 on the `ubuntu-24.04` runner image 20260823.283.1 (kernel
6.17.0-1022-azure) with probe images read cold after `drop_caches` and from the chunked
artefact: the in-place copies were torn, the temp-and-rename copies of the same files intact.
On the `ubuntu-26.04` image 20260824.116.1 (kernel 7.0.0-1012-azure) the same probes were clean
in 4 of 4 arms.

CI builds on `ubuntu-26.04` for this reason, and the image carries neither a cold NUL sweep nor
a fresh-inode helper. A runner whose kernel is a 6.17-azure brings the defect back.

## `grep -v` on an empty set kills a `pipefail` script silently

`... | grep -v '^$' | ...` exits 1 when no line survives the filter, and under
`set -euo pipefail` the script dies without a message (measured 2026-09-02 in `00-prep.sh`).
`sed '/^$/d'` exits 0 on an empty set and is what `recipe_set` uses in `lib/just.sh`.

## `command | grep -q` under `pipefail` fails on a match

`grep -q` exits at the first match and closes the pipe; a writer still producing output dies of
SIGPIPE, the pipeline's status is 141 and `pipefail` reports a failure. Capture the output in a
variable, then grep the variable. On 2026-09-07 a release run went red on
`rpm -q gpg-pubkey | grep -qi` in bazzite-mx's `tests/30-ide.sh`, five lines of output, on a
base the main run had passed minutes earlier: in the base's container the pipe failed 16 times
in 1000 runs. Every `| grep -q` of the repo captures first and `check-form.sh` refuses the
shape.

## `podman build` keeps the base's labels

Without `--label`, the new image carries every label of its `FROM`: a pre-flight image called
itself `Bazzite`, vendor `Universal Blue`, revision the base's commit (measured 2026-09-02).
`image-labels.sh` restates every label on every build, and the same file is passed again to
`build-chunked-oci`, which inherits no config either.

## A networked RUN leaves `/run/systemd/resolve/stub-resolv.conf` in the image

buildah gives a RUN the host's resolver by binding a file at
`/run/systemd/resolve/stub-resolv.conf`, the target of the base's `/etc/resolv.conf` symlink.
The directories and the placeholder file then stay in the layer: 3 entries under `/run` after
one networked RUN on the base, none when the RUN mounts a tmpfs on `/run` (measured
2026-09-02). Every `RUN` of the image stage therefore mounts a tmpfs on `/run`; the build and
the tests mount one on `/tmp` too. `bootc container lint` cannot see them from inside a
container, where podman fills `/run` itself, so `check-image.sh` reads both directories on the
mounted image instead.

## `ublue-os/remove-unwanted-software` v9 fails on `ubuntu-26.04`

Its apt step runs `apt-get remove -y powershell --fix-missing` and the 26.04 runner image has
no such package: `E: Unable to locate package powershell`, exit 100, the job dead before the
build (measured 2026-09-02). The `df` the action prints first showed 92 GB free of 145 GB on
that runner, so the image build, the compose archive and the chunked pull fit without freeing
anything. The action is not used.

## `skopeo` cannot read `containers-storage:` in a runner job

`skopeo inspect containers-storage:<image>` in a rootless job on `ubuntu-26.04` dies with
`Error during unshare(...): Operation not permitted` (measured 2026-09-02): skopeo needs a user
namespace of its own to open podman's rootless storage and the runner denies it to that binary,
while podman itself works. What a step needs from a local image is read with
`podman image inspect`; skopeo is used on `docker://` references only.

## A workflow that is not on the default branch has no runs endpoint

`gh run list --workflow release.yml` and the API path
`GET /repos/{owner}/{repo}/actions/workflows/release.yml/runs` answer
`HTTP 404: workflow release.yml not found on the default branch` while the file exists only on
a branch (measured 2026-09-02). `gh workflow run release.yml --ref <branch>` resolves the file
the same way. Runs of such a workflow are read from the repository-wide endpoint filtered on
`.path` (`watch-upstream.sh`), and a workflow is dispatched on a branch only once its file is
on the default branch too.

## `setup-oras` installs only the ORAS versions embedded in its own release

`oras-project/setup-oras` v2.0.1 resolves `version` against a list shipped in the action,
`src/lib/data/releases.json`, which runs from 1.0.0 to 1.3.3 (re-read 2026-09-06 at v2.0.1).
Any other version fails with "official ORAS CLI releases does not contain version 1.3.4"
(measured 2026-09-03, after the push and the signature of `:staging`). v2.0.2 added 1.3.4 on
2026-09-29, 33 days after ORAS released it (read 2026-10-01). `install-oras.sh` installs from
the ORAS release directly, the tarball refused unless its sha256 matches the release's
checksums file.

## `cosign verify --key` reads a certificate-signed referrer before the `.sig`

`ghcr.io/ublue-os/bazzite:stable` carries its legacy `.sig` tag, an SPDX SBOM and a SLSA
provenance bundle, the last two attached as OCI referrers. cosign v3.1.3
`verify --key cosign.pub` on it fails with "no matching attestations: expected key signature,
not certificate" and never reaches the `.sig`: the provenance bundle is signed with a
certificate and a key was requested. An image of ours, checked with a throwaway key, fails
instead with "no matching signatures: error verifying bundle: comparing public key PEMs".
Measured 2026-09-03 locally with cosign v3.1.3, the gate's release then. `cosign_rejected` in
`gate-release.sh` classifies both shapes as rejections of the signing material and leaves the
transport errors inconclusive.

## A rollback deployment whose origin tag was pruned from GHCR boots but never updates

`ujust migrate apply <tag>` and a `bootc switch` onto a dated tag write that tag into the
deployment's origin. Once `clean.yml` or a cleanup by id has removed the tag from the package,
the deployment still boots, its commit being local, and `bootc upgrade` on it finds nothing to
pull: the host reports the rollback as healthy and stale at the same time. Measured 2026-09-04
on a laptop whose rollback carried `44.20260904.2` after that tag was deleted; the deployment
went away with the next upgrade of the booted one, which is the only thing a dated origin
needs. `verify-host` reads the booted deployment only: a rollback on a dated tag shows in
`rpm-ostree status` and nowhere else.

## `ghcr-cleanup-action` matches `packages` by pattern only with `expand-packages`

`use-regex: true` reaches `delete-tags` and `exclude-tags`; `packages` stays a comma-separated
list of literal names unless `expand-packages: true`, which a wildcard character in the value
switches on by itself, and which lists the owner's packages through the Packages API and
requires a classic PAT (`src/main.ts` and `src/config.ts` at v1.2.2, read 2026-09-02 and again
2026-09-06; `GITHUB_TOKEN` is refused there). With `expand-packages` and `use-regex`, the whole
`packages` string is one regular expression, not a list of them. `clean.yml` names its
one package in full.

## A local pre-flight can exit 0 without running a changed build script

buildah keys a `RUN` layer on its command string and its parent layer; the content behind a
`--mount=type=bind,from=ctx` is not hashed into it. After a change under `build_files/` or
`system_files/`, a pre-flight whose base layers are cached reports `Using cache` on the build
steps and exits 0 in about three minutes with an image built from the old scripts. Measured
2026-09-04 on bazzite-mx: its closed flavour's pre-flight after a new feature printed ten
`Using cache` lines and no `kmod ntfsplus:` line, while `--no-cache` produced the real build.
CI is not affected, a fresh runner having no layer cache. `preflight-build.sh` judges the exit
status first, then refuses a log without the scripts' own output (`build.sh: N scripts ran`,
`tests: N passed`) as a cached build. The image id is no proof either way: the `LABEL` layer
carries a fresh `created` stamp, so the id changes on every run, cached or not (measured
2026-09-05: a fully cached run committed a new id).

## The SBOM referrer is syft JSON under the SPDX media type

`reusable-build.yml` writes the SBOM with `syft -o syft-json` and attaches it with
`--artifact-type application/vnd.spdx+json`, the shape of `ublue-os/bazzite`'s build.yml
(`Generate SBOM` and `Upload SBOM` steps), and `changelog.sh` selects the referrer by that
type. The document is syft's own format (`{"artifacts": […]}`, no `spdxVersion`; syft calls its
media type `vnd.syft+json`), so an SPDX parser does not open the file a reader pulls by
following the type. Measured 2026-09-12 on `:stable` with `oras discover` and `oras pull`. Kept
as upstream's shape on purpose: the diff `changelog.sh` prints reads `.artifacts[]`.

## A FAIL branch died before its verdict

Six smoke tests, at eight sites, built their `FAIL:` line as
`lines=$(grep … "$file" | tr '\n' ' ')`: with the file empty, grep matched nothing and exited
1, `pipefail` failed the assignment, `set -e` ended the test before its `echo`, and the runner
saw a test that stopped early instead of the line naming the file (measured 2026-09-08 with an
empty `vscode.repo` mounted over bazzite-mx's image: 2 lines of output instead of 11, no
`FAIL:`). The sibling shapes turned up one file at a time: `$(cmd || echo x)` under a command
that prints its answer and exits non-zero (`grep -c` printed `0`, then `echo` printed another),
a `head -n1` on a tool that prints several lines, `$(cmd)` inside an `echo` whose status nobody
reads, an empty variable printed as a value, a fixture file read as empty when missing, a state
change inside `if …; then` without an `else`. The two shapes a regex can see are rules 8 and 9
of `check-form.sh`; the rest is read by hand at review, listed here for that reading. One more
shape has no pipe for rule 9 to see: a bare `var=$(jq …)`, `var=$(rpm -q …)`, `var=$(tail …)` or
`var=$(a_function)` whose command exits non-zero on the state the test is there to catch
(measured 2026-09-08: a master justfile that does not parse left bazzite-mx's `tests/70` at 3
lines of 80, an unreadable `image-info.json` left its `tests/10` at none). A probe assigned in a
test carries `|| true` and its `FAIL:` line prints the fallback.

## A trailing `2> /dev/null` does not silence a failed redirection

Redirections are applied left to right and a `>` that fails ends the command there, so bash
reports the error before a `2> /dev/null` further right has been applied. A helper
(`bazzite-mx-ntfsplus-setup`, since removed) writing
`/etc/modprobe.d/bazzite-mx-ntfsplus.conf.new` as `text > "$file.new" 2> /dev/null` leaked for
that reason: as `nobody` under `LC_ALL=it_IT.UTF-8` it printed `bash: riga 11:
/etc/modprobe.d/bazzite-mx-ntfsplus.conf.new: Permesso negato` above its own `ERROR:` line
(measured 2026-09-12 in the pre-flight image). `2> /dev/null > file` is the order that silences
it, and on the same run the `ERROR:` line stood alone. `write_modules_load_file` of
`bazzite-mx-msi-setup` reads that way.

## cosign 3.1.3 deprecates the flag the signature layout needs

`cosign sign -y --new-bundle-format=false --use-signing-config=false <ref>` opens with "Flag
--new-bundle-format has been deprecated, this will be the only supported format in future
versions" (measured 2026-09-12 with cosign v3.1.3). The flag still works and
`reusable-build.yml` and `sign-image.yml` need it off: the new bundle format is not the layout
`policy.json`'s `sigstoreSigned` reads on a host (containers/container-libs#388,
coreos/rpm-ostree#5509). The release that removes it signs images a host cannot verify, and
`refresh-pins.sh --apply` would carry the pin past it with an `OK` row, reading the tag alone.

## An arithmetic syntax error escapes `set -e`

Under `set -euo pipefail`, `x=$((5 - $(printf '')))` prints `syntax error: operand expected`
and bash drops the rest of the top-level command it is running: inside a function, the
function's remaining lines and both branches of the caller's `if … else … fi` never ran; inside
a `for` body, the loop stopped at its first pass. The script went on with its next line and
ended with the status of the last command it ran, 0 after an `echo`; only a dropped command
that is the script's last, as `main "$@"` is, ends it with 1 (measured 2026-09-23 with bash
5.3.9). `(( n += $(printf '') ))` is an ordinary failure with status 1, which `set -e` stops
on. Rule 10 of `check-form.sh` refuses a `$( )` inside `$(( ))`.

## A scriptlet rewrote a packaged `.pyc`

The `%post` of `libvirt-daemon-driver-network`, installed by bazzite-mx's
`22-virtualization.sh`, runs `firewall-cmd --reload --quiet`, a `#!/usr/bin/python3 -sP`
script. At start Python imports
`_distutils_hack` through `distutils-precedence.pth`, and the base's `__init__.cpython-314.pyc`
records a source mtime of `0x69af5f00` where the source has 0, so the interpreter compiles it
again and writes it over the packaged file. Measured 2026-09-23 on the 44.20260921 base:
`rpm -V --nomtime python3-setuptools` printed
`S.5...... /usr/lib/python3.14/site-packages/_distutils_hack/__pycache__/__init__.cpython-314.pyc`
in bazzite-mx's three pre-flight images and nothing in their three bases; in the base,
`firewall-cmd --reload --quiet` alone (status 36) sufficed for `rpm -V --nomtime` to print the
same line, and with `PYTHONDONTWRITEBYTECODE=1` in front it exited 0. `lib/env.sh` exports the
variable to every build script and `tests/run.sh` to every test. The last gate of the
`Containerfile` requires `rpm -V --nomtime python3-setuptools` clean on the final image, which
holds what the build RUN and the test RUN wrote.

## An anonymous probe of a GHCR package never published answers 403

`skopeo list-tags --no-creds docker://ghcr.io/matrixdj96/<package>` lists the tags of
bazzite-mx's published packages, and for a package never published fails with
`Requesting bearer token: received unexpected HTTP status: 403 Forbidden`; logged in, the same
probe fails with `fetching tags list: name unknown` (measured 2026-10-01 with skopeo on
bazzite-mx's packages and a never-published name). `release-tag.sh` reads `name unknown` as a
package with no tag taken and any other failure as a failed probe, so the version job of
`release.yml` logs in to GHCR before it resolves the tag: anonymously, a package not yet
published would stop the run.
