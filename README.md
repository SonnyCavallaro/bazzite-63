# bazzite-63

A personal [bootc](https://bootc-dev.github.io/bootc/) image layered on
[bazzite-mx](https://github.com/MatrixDJ96/bazzite-mx), itself built on
[Bazzite](https://bazzite.gg) (KDE desktop, `stable` stream): one image,
`ghcr.io/sonnycavallaro/bazzite-63`, for AMD and Intel graphics.

Everything bazzite-mx ships stays, its packages, kernel modules, recipes and signing trust,
except what this image changes over it, listed with the reason in
[`docs/divergences.md`](docs/divergences.md). `:stable` is the tag a host follows, and it moves
onto a release only through the gate that verified its signature.

## What the image adds over bazzite-mx

- Signing trust for `ghcr.io/sonnycavallaro/*`, next to bazzite-mx's own: a host pulls only
  what this repository signed.
- `ujust migrate` and `ujust verify-host`, bazzite-mx's, pointed at this image's registry.
- Firefox out of the image: bazzite-mx's Fedora RPM removed, Bazzite's Flatpak allowed.
- Google Chrome as a system RPM from Google's repository, the default web browser, its Flatpak
  denied.
- Thunderbird, Proton Pass, DBeaver, Remmina, Parsec and Discord in Bazzite's default Flatpak
  list, installed with the rest of it on demand (`ujust install-default-flatpaks`).
- Konsole opens PowerShell, its profile wired to Homebrew and mise, bash until pwsh exists.

## Switch a host

The image requires Secure Boot off (`bootctl status`), as bazzite-mx does: the base's NTFSPLUS
and MSI modules are unsigned.

No stock image trusts a key for `ghcr.io/sonnycavallaro`, bazzite-mx included, so the first
rebase goes through the unsigned transport. The recipe moves the host onto the signed one
afterwards.

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/sonnycavallaro/bazzite-63:stable
systemctl reboot
ujust migrate apply
systemctl reboot
ujust verify-host
```

The steps, the checks and what an NVIDIA machine needs are in
[`docs/migration.md`](docs/migration.md).

## Verify an image

```bash
cosign verify --key https://raw.githubusercontent.com/SonnyCavallaro/bazzite-63/main/cosign.pub \
  ghcr.io/sonnycavallaro/bazzite-63:stable
gh attestation verify oci://ghcr.io/sonnycavallaro/bazzite-63:stable \
    --repo SonnyCavallaro/bazzite-63
```

`gh attestation verify` wants a GitHub login first (`gh auth login`, or `GH_TOKEN` in the
environment), public repository or not.

The key is [`cosign.pub`](cosign.pub), the one the image itself trusts.

## Build it yourself

```bash
# resolve-base.sh pins bazzite-mx's :stable to its current digest, the way CI does
eval "$(./.github/scripts/resolve-base.sh bazzite-mx)"
./.github/scripts/verify-base.sh "$base_image"   # bazzite-mx's signature, base-cosign.pub
podman build --build-arg BASE_IMAGE="$base_image" --build-arg IMAGE_NAME="$image_name" \
    --tag localhost/bazzite-63 .
```

## Documentation

- [`AGENTS.md`](AGENTS.md): the project guide for anyone working on the repo.
- [`docs/architecture.md`](docs/architecture.md): build flow, layout, build state, the gates.
- [`docs/conventions.md`](docs/conventions.md): the rules for scripts, recipes, tests and CI.
- [`docs/divergences.md`](docs/divergences.md): what changes over bazzite-mx, and why.
- [`docs/gotchas.md`](docs/gotchas.md): surprises found here, each with how it was found.
- [`docs/migration.md`](docs/migration.md): bringing a host onto the image, re-checking one.
- [`docs/workflow.md`](docs/workflow.md): branches, the release run, the base, retention.

## License

Apache-2.0, see [`LICENSE`](LICENSE).
