#!/usr/bin/env bash
# Segoe UI Variable, the Windows 11 interface font, as Plasma's general, menu,
# toolbar and window-title font. Only the configuration is baked: Microsoft's
# licence lets a user download the font from https://aka.ms/SegoeUIVariable
# but not redistribute it, so bazzite-63-segoe-ui-variable fetches it into
# each home at the first login (its autostart entry ships in system_files/).
# The keys land in the system level of the KConfig cascade, so a font a user
# picks in System Settings still wins.
#
# Usage: run by build.sh; no arguments.
# Writes: the five font keys in /etc/xdg/kdeglobals, the file on a fresh inode.
# Exit status: 0 done; the build stops on a `FAIL: …` line.

# shellcheck source=lib/env.sh
source "$(dirname "$(realpath "$0")")/lib/env.sh"

KDEGLOBALS=/etc/xdg/kdeglobals
# QFont strings for the variable font's Regular instance, weight 400.
FONT_10='Segoe UI Variable,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1'
FONT_8='Segoe UI Variable,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1'

# <group> <key> <value>, on a copy renamed over the base's file at the end.
write_key() {
    kwriteconfig6 --file "$KDEGLOBALS.new" --group "$1" --key "$2" "$3"
}

cp "$KDEGLOBALS" "$KDEGLOBALS.new"
write_key General font "$FONT_10"
write_key General menuFont "$FONT_10"
write_key General toolBarFont "$FONT_10"
write_key General smallestReadableFont "$FONT_8"
write_key WM activeFont "$FONT_10"

mv -f "$KDEGLOBALS.new" "$KDEGLOBALS"

log "segoe-font: Segoe UI Variable is Plasma's interface font in $KDEGLOBALS"
