# bazzite-63: one image layered on bazzite-mx, whose stable release is the
# base, resolved to a digest and verified against base-cosign.pub by
# .github/scripts/resolve-base.sh and verify-base.sh (docs/architecture.md §
# Build flow).

ARG BASE_IMAGE=ghcr.io/matrixdj96/bazzite-mx:stable
ARG IMAGE_NAME=bazzite-63
ARG IMAGE_VENDOR=sonnycavallaro

# The version the image calls itself: the release tag, or "<base version>.dev"
# for a sandbox or pre-flight build, both from image-labels.sh.
ARG VERSION=

# --- ctx: the tree the other stages mount -------------------------------------

FROM scratch AS ctx
COPY build_files /build_files
COPY system_files /system_files
COPY cosign.pub /cosign.pub

# --- image: build, test, lint -------------------------------------------------

FROM ${BASE_IMAGE} AS image
ARG IMAGE_NAME
ARG IMAGE_VENDOR
ARG VERSION

# /run is a tmpfs because buildah binds the host's resolv.conf under it and
# the path would otherwise stay in the image (docs/gotchas.md § A networked
# RUN leaves `/run/systemd/resolve/stub-resolv.conf` in the image).
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/run \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/build.sh

# Tests read the image and must not write to it: dnf5 alone would leave
# /var/log/dnf5.log behind and trip bootc lint's var-log check, so /var/log
# and /var/cache are tmpfs here too.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/run \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/var/log \
    --mount=type=tmpfs,dst=/var/cache \
    --network=none \
    /ctx/build_files/tests/run.sh

# The last gate, offline (docs/architecture.md § Gates, in order).
RUN --mount=type=tmpfs,target=/run \
    --network=none \
    rpm -V --nomtime python3-setuptools \
    && bootc container lint --fatal-warnings --no-truncate
