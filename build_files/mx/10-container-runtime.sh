#!/usr/bin/bash
# MX block 10: Container runtime.
# Adds Docker CE (vendored repo, enabled=0 + --enablerepo= scope),
# Podman extras (Fedora), and podman-bootc (COPR isolated).

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

# shellcheck disable=SC1091
source /ctx/build_files/shared/copr-helpers.sh

### Section 1: Podman extras (Fedora) ###
dnf5 install -y \
    podman-compose \
    podman-machine \
    podman-tui

### Section 2: Docker CE (vendored repo, scoped --enablerepo) ###
# The repo file (system_files/etc/yum.repos.d/docker-ce.repo, enabled=0)
# lands on disk via the rsync in build.sh; --enablerepo=docker-ce is the
# runtime-only override during install.
dnf5 -y --enablerepo=docker-ce install \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker-model-plugin

### Section 3: podman-bootc (COPR isolated) ###
copr_install_isolated gmaglione/podman-bootc podman-bootc

### Section 4: Services ###
systemctl enable docker.socket
systemctl enable podman.socket

echo "::endgroup::"
