#!/usr/bin/bash
# MX block 62: Segoe UI Variable (the Windows 11 system font) as the Plasma
# default interface font — general, menu, toolbar, window titles. The
# monospace font stays stock.
#
# Only the CONFIGURATION is baked. The Microsoft EULA allows downloading the
# font from the official https://aka.ms/SegoeUIVariable link but forbids
# redistributing it, so no TTF ships in the repo or in the published image:
# each user downloads it at first login via
# /usr/libexec/bazzite63-segoe-ui-variable (autostart one-shot). The smoke
# test enforces the no-baked-TTF invariant.
#
# Written into /etc/xdg/kdeglobals (system level of the KConfig cascade) with
# kwriteconfig6 — a merge, never a static system_files copy that would
# clobber base-image entries (gotcha #23). A per-user ~/.config/kdeglobals
# always wins, so an explicit user font choice is never overridden.

echo "::group:: ===$(basename "$0")==="

set -euxo pipefail

# QFont 16-field strings validated live on the target machine (source kit
# font-segoe-ui-variable): fontconfig family "Segoe UI Variable", default
# instance Regular (weight 400).
FONT_10='Segoe UI Variable,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1'
FONT_8='Segoe UI Variable,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1'

KDEGLOBALS=/etc/xdg/kdeglobals

kwriteconfig6 --file "$KDEGLOBALS" --group General --key font "$FONT_10"
kwriteconfig6 --file "$KDEGLOBALS" --group General --key menuFont "$FONT_10"
kwriteconfig6 --file "$KDEGLOBALS" --group General --key toolBarFont "$FONT_10"
kwriteconfig6 --file "$KDEGLOBALS" --group General --key smallestReadableFont "$FONT_8"
kwriteconfig6 --file "$KDEGLOBALS" --group WM --key activeFont "$FONT_10"

# Canary: the merge really landed (kwriteconfig6 can exit 0 without writing).
grep -q '^font=Segoe UI Variable,' "$KDEGLOBALS"
grep -q '^activeFont=Segoe UI Variable,' "$KDEGLOBALS"

echo "::endgroup::"
