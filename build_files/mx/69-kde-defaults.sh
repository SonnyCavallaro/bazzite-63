#!/usr/bin/bash
# MX block 69: KDE Plasma desktop defaults.
#
# Tray clock shows seconds by default: patch the digital-clock plasmoid
# default in place (showSeconds enum: 0=Never, 1=ToolTip, 2=Always).
# Patching the base image's own file keeps every per-user applet setting
# authoritative (docs/gotchas.md #23: never ship a replacing copy of a
# file the base image owns).

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

CLOCK_XML=/usr/share/plasma/plasmoids/org.kde.plasma.digitalclock/contents/config/main.xml
[ -f "$CLOCK_XML" ] || { echo "FAIL: $CLOCK_XML not found (Plasma layout changed?)"; exit 1; }

sed -i '/<entry name="showSeconds"/,/<\/entry>/ s|<default>[^<]*</default>|<default>2</default>|' "$CLOCK_XML"

# Loud guard: if upstream renames the entry or restructures the block, the
# sed above silently no-ops — fail the build instead.
sed -n '/<entry name="showSeconds"/,/<\/entry>/p' "$CLOCK_XML" | grep -q '<default>2</default>' || {
    echo "FAIL: showSeconds default not patched to Always (2) in $CLOCK_XML"
    exit 1
}

echo "::endgroup::"
