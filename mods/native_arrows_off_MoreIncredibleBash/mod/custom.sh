#!/bin/sh
# M.I.B. -> Advanced Settings -> Run Custom Script: native Audi VC arrows OFF (default).
#
# Removes /mnt/app/carplay_native_arrows.on, so route guidance shows the custom 3D
# maneuver arrow (maneuver_render) in the Virtual Cockpit instead of the Audi arrows.
# Applies from the next phone connection; run native_arrows_on to try the Audi arrows.
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
echo "custom.sh: native VC arrows OFF"
mount -uw /mnt/app 2>/dev/null || echo "custom.sh: mount -uw /mnt/app failed"
rm -f "$M" /tmp/carplay_native_arrows.on \
      /mnt/app/carplay_native_arrows.off /tmp/carplay_native_arrows.off   # opt-out marker of older builds
if [ -e "$M" ]; then
    echo "FAILED: $M still present (is /mnt/app read-only?)"
    exit 1
fi
sync
echo "DONE. Native VC arrows OFF, custom 3D arrow."
echo "Reconnect the phone to apply (no reboot needed)."
