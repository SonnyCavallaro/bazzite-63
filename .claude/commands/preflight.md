---
description: Local podman pre-flight build of the bazzite-63 image before any push.
allowed-tools: Bash(./.github/scripts/preflight-build.sh:*), Bash(podman:*), Bash(xargs:*),
  Bash(rm:*), Bash(id:*), Bash(df:*), Bash(grep:*), Bash(tail:*)
argument-hint: "[--no-cache]"
---

Build the image locally with the same recipe CI runs, on bazzite-mx's `:stable` verified
against `base-cosign.pub`, and judge it on the exit status. After a change under `build_files/`
or `system_files/` add `--no-cache`: buildah keys a `RUN` on its command string and parent
layer, never on the content of a bind mount, so a cached run exits 0 in minutes without running
the changed script (`docs/gotchas.md` § A local pre-flight can exit 0 without running a changed
build script).

1. Free the space the build needs first: the previous image and the new one are both on disk
   otherwise. The verdict of the previous run is already in its log, so nothing is lost.
   ```bash
   podman rmi localhost/bazzite-63:preflight 2> /dev/null
   podman images --filter dangling=true -q | xargs -r podman rmi
   rm -rf "${TMPDIR:-/var/tmp}/buildah-cache-$(id -u)"
   df -h /var | tail -1
   ```
   The second line does what `podman image prune -f` does: every dangling image of the storage
   goes, the user's too. Never `podman image prune -a`, which also removes the user's tagged
   images no container uses, or `podman system prune`, which removes their stopped containers.
2. Run the script, in the background.
   ```bash
   ./.github/scripts/preflight-build.sh $ARGUMENTS
   ```
   It resolves and verifies the base and writes the labels the way CI does, builds
   `localhost/bazzite-63:preflight` with the log in `/var/tmp/bazzite-63-preflight.log`
   (`/tmp` is a tmpfs on a bootc host), refuses a log without the build scripts' own output
   (`build.sh: N scripts ran`, `tests: N passed`) or with a `FAIL:` line, probes the image with
   `check-image.sh` and ends with one `preflight ok:` line.
3. On a failure, read the log before the verdict.
   ```bash
   grep -E 'BUILD_EXIT|^FAIL:|Using cache' /var/tmp/bazzite-63-preflight.log
   tail -20 /var/tmp/bazzite-63-preflight.log
   ```
4. Give the verdict in one line: ready for `develop`, or the fix needed with `file:line` when
   the log names it.

The image is left in place for the tests that follow; the next run removes it in step 1.
