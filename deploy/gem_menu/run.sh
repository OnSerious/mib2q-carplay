#!/bin/sh
# GEM (Green Engineering Menu) -> CarPlay-RGI -> <button>: dispatcher.
#
# Installed by the menu_install mod to /mnt/app/eso/hmi/engdefs/scripts/carplay/
# next to actions/<name>/custom.sh, which are verbatim copies of the M.I.B. mods
# (mods/<name>_MoreIncredibleBash/mod/custom.sh), so every button runs exactly
# the script the matching mod runs. Each GEM entry calls a one-line wrapper that
# runs this file with the action name.
#
# Only these actions need the SD card, and they find it themselves:
#   install      - the release (libcarplay_hook.so ...) in <card>/mod/carplay/
#                  or <card>/carplay/, i.e. a staged install_MoreIncredibleBash
#   logs, lsd    - any writable card/USB stick for the output folder
#   safearea     - <card>/carplay_safearea.conf (wide VC map),
#                  <card>/carplay_safearea_small.conf (classic small map) and/or
#                  <card>/carplay_safearea_sport.conf (sport small map), x=/y=/w=/h=
#                  like the altscreen_safearea mod's safearea.conf
#
# QNX 6.5 /bin/sh is ksh; stays inside its portable subset.
# Copyright (c) 2026
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/sbin
export PATH
unset LD_PRELOAD

case $0 in */*) M=${0%/*} ;; *) M=. ;; esac
M=$(cd "$M" && pwd) || exit 1
A=$M/actions
GEM_DIR=${CP_GEM_DIR:-/mnt/app/eso/hmi/engdefs}
ESD=$GEM_DIR/mib2q-carplay.esd
CARDS=${CP_CARDS:-/fs/sda0 /fs/sdb0 /fs/usb0_0 /net/mmx/fs/sda0 /net/mmx/fs/sdb0 /net/mmx/fs/usb0_0}

can_write() { : > "$1/.carplay_write_test" 2>/dev/null && rm -f "$1/.carplay_write_test"; }

# First present card/stick that is (or can be remounted) writable.
writable_card() {
    for c in $CARDS; do
        [ -d "$c" ] || continue
        can_write "$c" || mount -uw "$c" 2>/dev/null
        can_write "$c" && { echo "$c"; return 0; }
    done
    return 1
}

# First card holding a staged release.
release_dir() {
    for c in $CARDS; do
        for r in "$c/mod/carplay" "$c/carplay"; do
            [ -f "$r/libcarplay_hook.so" ] && { echo "$r"; return 0; }
        done
    done
    return 1
}

run_action() {
    [ -f "$A/$1/custom.sh" ] || { echo "FAILED: action $1 missing in $A (re-run menu_install)"; exit 1; }
    exec /bin/sh "$A/$1/custom.sh"
}

ACT=${1:-}
echo "CarPlay-RGI menu: $ACT"
case $ACT in
    install)
        R=$(release_dir) || {
            echo "FAILED: no release on the SD card."
            echo "Copy install_MoreIncredibleBash/mod/ to the card as /mod/ (it holds carplay/)."
            exit 1
        }
        echo "release: $R"
        CP_INSTALL_RES=$R
        export CP_INSTALL_RES
        run_action install
        ;;
    logs|lsd)
        C=$(writable_card) || { echo "FAILED: no writable SD card or USB stick found"; exit 1; }
        CP_CARD=$C
        export CP_CARD
        [ "$ACT" = logs ] && run_action logging
        run_action extract_lsd
        ;;
    safearea)
        # carplay_safearea.conf = wide VC map (ViewArea 0),
        # carplay_safearea_small.conf = classic small map window (ViewArea 1),
        # carplay_safearea_sport.conf = sport small map window (ViewArea 2).
        n=0
        for name in carplay_safearea.conf:mibr-carplay111-safearea.conf \
                    carplay_safearea_small.conf:mibr-carplay111-safearea-small.conf \
                    carplay_safearea_sport.conf:mibr-carplay111-safearea-sport.conf; do
            F=
            for c in $CARDS; do
                [ -f "$c/${name%%:*}" ] && { F=$c/${name%%:*}; break; }
            done
            [ -n "$F" ] || continue
            echo "values: $F"
            CP_SAFEAREA_SRC=$F CP_SAFEAREA_DST=/mnt/app/root/${name#*:} \
                /bin/sh "$A/altscreen_safearea/custom.sh" || exit 1
            n=$((n+1))
        done
        [ "$n" -gt 0 ] || { echo "FAILED: no carplay_safearea.conf / carplay_safearea_small.conf / carplay_safearea_sport.conf in the root of the SD card"; exit 1; }
        ;;
    safearea_reset)
        echo reset > /tmp/carplay_safearea_reset.conf || exit 1
        for f in mibr-carplay111-safearea.conf mibr-carplay111-safearea-small.conf mibr-carplay111-safearea-sport.conf; do
            CP_SAFEAREA_SRC=/tmp/carplay_safearea_reset.conf CP_SAFEAREA_DST=/mnt/app/root/$f \
                /bin/sh "$A/altscreen_safearea/custom.sh" || exit 1
        done
        ;;
    singleview)
        # Fallback: advertise one ViewArea (as every test before the classic layout).
        M=/mnt/app/root/mibr-carplay111-viewareas.single
        mount -uw /mnt/app 2>/dev/null
        if [ -e "$M" ]; then
            rm -f "$M"; sync
            echo "FERTIG. Kartenbereiche breit + klassisch (+ Sport, falls an) ab der naechsten CarPlay-Verbindung."
        else
            : > "$M" || { echo "FAILED: cannot create $M"; exit 1; }
            sync
            echo "FERTIG. Nur ein Kartenbereich (breit) ab der naechsten CarPlay-Verbindung."
        fi
        ;;
    sportview)
        # Opt-in: own ViewArea for the Sport layout's small map (x=590 y=88 350x296),
        # instead of the classic one. Read when the AltScreen hook starts its profile.
        M=/mnt/app/root/mibr-carplay111-viewareas.sport
        mount -uw /mnt/app 2>/dev/null
        if [ -e "$M" ]; then
            rm -f "$M"; sync
            echo "FERTIG. Eigener Sport-Kartenbereich AUS (Standard): Sport nutzt den klassischen Bereich. iPhone neu anstecken; wenn sich nichts aendert, MMI neu starten."
        else
            : > "$M" || { echo "FAILED: cannot create $M"; exit 1; }
            sync
            echo "FERTIG. Eigener Sport-Kartenbereich AN. iPhone neu anstecken; wenn sich nichts aendert, MMI neu starten."
        fi
        ;;
    appcard)
        # Opt-in: keep the app's own turn card (e.g. "Start on <street>") and ETA in the
        # cluster video while route guidance is on, as before 1.2. The hook re-reads the
        # marker on every guidance edge, so it applies from the next route start.
        M=/mnt/app/root/mibr-carplay111-rgi-url.disabled
        mount -uw /mnt/app 2>/dev/null
        if [ -e "$M" ]; then
            rm -f "$M"; sync
            echo "FERTIG. App-Abbiegekarte AUS (Standard): bei Route nur Karte + Pfeil. Gilt ab dem naechsten Routenstart."
        else
            : > "$M" || { echo "FAILED: cannot create $M"; exit 1; }
            sync
            echo "FERTIG. App-Abbiegekarte AN: die Abbiegekarte der App bleibt im Tacho. Gilt ab dem naechsten Routenstart."
        fi
        ;;
    longpress)
        # Ours (q7): a long press of the left steering-wheel roller toggles the cluster between
        # the phone's map and the stock Audi map. On by default; the marker turns it off.
        # Read on every long press, so it applies at once.
        M=/mnt/app/carplay_longpress_map.off
        mount -uw /mnt/app 2>/dev/null
        if [ -e "$M" ]; then
            rm -f "$M"; sync
            echo "FERTIG. Langdruck linke Walze -> Original-Audi-Karte AN (Standard). Gilt sofort."
        else
            : > "$M" || { echo "FAILED: cannot create $M"; exit 1; }
            sync
            echo "FERTIG. Langdruck linke Walze -> Original-Audi-Karte AUS. Gilt sofort."
        fi
        ;;
    status)
        # Ours (q7): which switches are set (absent marker = default).
        on_off() { if [ -e "$2" ]; then echo "$1: $3"; else echo "$1: $4"; fi; }
        on_off "Langdruck -> Audi-Karte" /mnt/app/carplay_longpress_map.off "AUS" "AN (Standard)"
        on_off "App-Abbiegekarte" /mnt/app/root/mibr-carplay111-rgi-url.disabled "AN" "AUS (Standard)"
        on_off "Eigener Sport-Kartenbereich" /mnt/app/root/mibr-carplay111-viewareas.sport "AN" "AUS (Standard)"
        on_off "Nur ein Kartenbereich" /mnt/app/root/mibr-carplay111-viewareas.single "AN" "AUS (Standard)"
        on_off "CarPlay-Karte im Tacho" /mnt/app/mibr-carplay111.noadvertise "AUS" "AN (Standard)"
        on_off "Android-Auto-Bruecke" /mnt/app/carplay_aa.disabled "AUS" "AN (Standard)"
        on_off "Abbiegehinweise" /mnt/app/carplay_rgd.disabled "AUS" "AN (Standard)"
        on_off "Hardware-Decoder" /mnt/app/root/altscreen_render.hwdecode.off "AUS" "AN (Standard)"
        on_off "2-Min-Verzoegerung Decoder" /mnt/app/root/altscreen_render.hwdecode.delayed "AN" "AUS (Standard)"
        on_off "Siri kurz" /mnt/app/carplay_siri_short.on "AN" "AUS (Standard)"
        on_off "Touchpad als Steuerkreuz" /mnt/app/carplay_touchpad_dpad.off "AUS" "AN (Standard)"
        on_off "Android-Auto-Tachokarte" /mnt/app/root/aa_cluster.off "AUS" "AN (Standard)"
        on_off "Android-Auto Tag/Nacht" /mnt/app/root/aa_cluster.daynight "AN" "AUS (Standard)"
        on_off "Ausfuehrliches Log" /mnt/app/carplay_verbose "AN" "AUS (Standard)"
        for f in mibr-carplay111-safearea.conf mibr-carplay111-safearea-small.conf mibr-carplay111-safearea-sport.conf; do
            [ -e "/mnt/app/root/$f" ] && echo "Eigener Kartenrand gesetzt: $f"
        done
        ;;
    grid)
        run_action altscreen_grid
        ;;
    hwdec)
        # Hardware decode is the default; these markers turn it OFF. altscreen_render
        # writes them itself after a real hardware failure (the /tmp one when /mnt/app
        # is read-only). Read per CarPlay connection.
        M=/mnt/app/root/altscreen_render.hwdecode.off
        B=/tmp/altscreen_render.hwdecode.off
        mount -uw /mnt/app 2>/dev/null
        rm -f /mnt/app/root/altscreen_render.hwdecode   # opt-in marker of older builds
        if [ -e "$M" ] || [ -e "$B" ]; then
            rm -f "$M" "$B"; sync
            echo "FERTIG. Hardware-Decoder AN (Standard) ab der naechsten CarPlay-Verbindung."
        else
            : > "$M" || { echo "FAILED: cannot create $M"; exit 1; }
            sync
            echo "FERTIG. Hardware-Decoder AUS (Software) ab der naechsten CarPlay-Verbindung."
        fi
        ;;
    hwdelay)
        # CarPlay starts on the hardware decoder at once (no switch, no blink). This marker
        # brings back the 2-minute wait after an MMI start (software decode until then),
        # for units that freeze when the decoder opens early (issue #10). Android Auto always
        # waits (issue #14). Read per CarPlay connection.
        M=/mnt/app/root/altscreen_render.hwdecode.delayed
        mount -uw /mnt/app 2>/dev/null
        if [ -e "$M" ]; then
            rm -f "$M"; sync
            echo "FERTIG. 2-Min-Verzoegerung AUS (Standard): Hardware-Decoder startet sofort, ab der naechsten Verbindung."
        else
            : > "$M" || { echo "FAILED: cannot create $M"; exit 1; }
            sync
            echo "FERTIG. 2-Min-Verzoegerung AN: Hardware-Decoder erst 2 Min nach MMI-Start (bis dahin Software)."
        fi
        ;;
    siri_short)
        # Opt-in: with CarPlay connected, a short press of the steering-wheel voice key opens
        # Siri instead of the car's own voice control (the long press always opens Siri).
        # Read on every key press, so it applies at once.
        M=/mnt/app/carplay_siri_short.on
        mount -uw /mnt/app 2>/dev/null
        if [ -e "$M" ]; then
            rm -f "$M"; sync
            echo "FERTIG. Sprachtaste kurz: Audi-Sprachbedienung (Standard). Lang: Siri."
        else
            : > "$M" || { echo "FAILED: cannot create $M"; exit 1; }
            sync
            echo "FERTIG. Sprachtaste kurz: Siri, solange CarPlay verbunden ist."
        fi
        ;;
    aa_daynight)
        # Opt-in: the Android Auto cluster map follows the MMI day/night design (Light by
        # day, Dark by night) instead of always Dark. Experimental. The theme is picked when
        # the phone connects: changing it in a running session drops Android Auto (#19).
        M=/mnt/app/root/aa_cluster.daynight
        mount -uw /mnt/app 2>/dev/null
        if [ -e "$M" ]; then
            rm -f "$M"; sync
            echo "FERTIG. Android-Auto-Tachokarte immer dunkel (Standard)."
        else
            : > "$M" || { echo "FAILED: cannot create $M"; exit 1; }
            sync
            echo "FERTIG. Android-Auto-Tachokarte folgt Tag/Nacht des MMI (Test)."
            echo "Stuerzt Android Auto am Handy ab: diesen Punkt nochmal druecken (wieder aus)."
        fi
        echo "Gilt ab der naechsten Handy-Verbindung."
        ;;
    reacquire)
        # Test: re-send the cluster showUI in the running session, so iOS picks
        # which navigation app draws the VC map again (/tmp, consumed by the hook).
        : > /tmp/mibr-alt111-gen2-reacquire || { echo "FAILED: cannot create the marker"; exit 1; }
        echo "FERTIG. Tachokarte neu angefordert."
        ;;
    omxprobe)
        # altscreen_render consumes the marker within ~1 s and logs the Qualcomm
        # OMX decoder's requirements to /tmp/altscreen_render.log (no decoding).
        mount -uw /mnt/app 2>/dev/null
        : > /mnt/app/root/altscreen_render.omxprobe || { echo "FAILED: cannot create the probe marker"; exit 1; }
        sync
        echo "FERTIG. Test angefordert, laeuft in ca. 1 s."
        echo "Danach 'Logs auf SD speichern' druecken."
        ;;
    uninstall|altscreen_on|altscreen_off|rgd_enable|rgd_disable|aa_cluster_on|aa_cluster_off|touchpad_dpad_on|touchpad_dpad_off)
        run_action "$ACT"
        ;;
    remove_menu)
        mount -uw /mnt/app 2>/dev/null
        rm -f "$ESD"
        rm -rf "$M"
        sync
        if [ -e "$ESD" ] || [ -d "$M" ]; then
            echo "FAILED: menu files still present (is /mnt/app read-only?)"
            exit 1
        fi
        echo "FERTIG. Menue entfernt; verschwindet nach dem naechsten Neustart."
        ;;
    *)
        echo "usage: run.sh install|uninstall|logs|lsd|altscreen_on|altscreen_off|rgd_enable|rgd_disable|aa_cluster_on|aa_cluster_off|aa_daynight|touchpad_dpad_on|touchpad_dpad_off|grid|safearea|safearea_reset|singleview|sportview|appcard|longpress|status|reacquire|hwdec|hwdelay|siri_short|omxprobe|remove_menu"
        exit 2
        ;;
esac
