#!/bin/sh
# M.I.B. -> Advanced Settings -> Run Custom Script: native Audi VC arrows ON (opt-in).
#
# Creates /mnt/app/carplay_native_arrows.on. CarPlay / Android Auto route guidance then
# shows the Virtual Cockpit's own Audi maneuver arrows (with the roundabout exit number)
# instead of the custom 3D arrow; "follow road" is shown until the next turn is close.
# Not every VC draws them (Audi Q7 MU1329: empty KDK box, issue #9).
# Applies from the next phone connection; run native_arrows_off for the 3D arrow.
#
# QNX 6.5 /bin/sh is ksh; stays inside its portable subset.
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin
export PATH
unset LD_PRELOAD

case $0 in */*) D=${0%/*} ;; *) D=. ;; esac
D=$(cd "$D" && pwd) || exit 1

if [ ! -d /mnt/app/eso/hmi/lsd ] && [ -d /net/mmx/mnt/app/eso/hmi/lsd ]; then
    exec on -f mmx /bin/sh "$D/custom.sh" "$@"
fi

M=/mnt/app/carplay_native_arrows.on
echo "custom.sh: native VC arrows ON"
mount -uw /mnt/app 2>/dev/null || echo "custom.sh: mount -uw /mnt/app failed"
rm -f /mnt/app/carplay_native_arrows.off /tmp/carplay_native_arrows.off   # opt-out marker of older builds
: > "$M" || { echo "FAILED: cannot create $M (is /mnt/app read-only?)"; exit 1; }
[ -e "$M" ] || { echo "FAILED: $M was not created"; exit 1; }
sync
echo "DONE. Native VC arrows ON ($M)."
echo "Reconnect the phone to apply (no reboot needed)."
echo "If the VC shows an empty box instead of an arrow, run native_arrows_off."
