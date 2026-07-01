# Activate mise if present (installed per-user via brew / `ujust setup-dev`).
# No-op when mise is not yet installed, so the file is always safe to ship.
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
fi
