#!/bin/sh
# Q7 (q7 builds only): bring the unit back to stock before the install, so every switch
# starts at its default.  Run by the SD setup (mod/custom.sh) as step 0, on the MMX.
#   - every *.carplay-stock backup renamed back (smartphone_integrator.json,
#     dio_manager.json, and from older private builds deva-ctrl-qc.so / lang_data.zip)
#   - every file the CarPlay builds add removed
#   - every switch/trigger file any q7 build (q7 .. q7n, incl. the old 5.1 sound) reads
#     removed: absent marker = default
#   - the hidden menu page, temp leftovers, the renderer cache and our renderers'
#     crash dumps removed
#   - if <card>/mod/clean/deva-ctrl-qc.so.stock exists, the audio driver is checked
#     against it and put back from it when it differs
# Exit 0 = clean; exit 1 = a problem (listed as PROBLEM), and the setup installs nothing.
# Output also goes to <card>/q7_clean_log.txt.  QNX 6.5 /bin/sh is ksh.
set -u
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin
export PATH
unset LD_PRELOAD

case $0 in */*) D=${0%/*} ;; *) D=. ;; esac
D=$(cd "$D" && pwd) || exit 1
CARD=${D%/mod/clean}
LOG=$CARD/q7_clean_log.txt
ST=/tmp/q7_clean.$$
: > "$LOG" 2>/dev/null || LOG=/dev/null

HOOKS=/mnt/app/root/hooks
JARS=/mnt/app/eso/hmi/lsd/jars
DEVA=/mnt/app/armle/lib/dll/deva-ctrl-qc.so
DEVA_STOCK=$D/deva-ctrl-qc.so.stock
GEM=/mnt/app/eso/hmi/engdefs

# Files the CarPlay builds add (no stock version exists).
OWNED="$HOOKS/libcarplay_hook.so $HOOKS/maneuver_render $HOOKS/flag_atlas.rgba
$HOOKS/carplay_startup.sh $HOOKS/carplay_monitor.sh $HOOKS/carplay_processes.sh
$HOOKS/carplay_cleanup.sh $HOOKS/libaltscreen111_mhi2q.so $HOOKS/altscreen_render
$HOOKS/libaa_cluster_hook.so $HOOKS/aa_startup.sh $HOOKS/libcarplay_apac.so
$HOOKS/scene_masknet_c.bin $HOOKS/carplay_audio51.state $HOOKS/carplay_upmix_texts.ok
$JARS/carplay_hook.jar"

# cmp, else SHA-1 (M.I.B. on the card / RCC), else cksum (CRC + size).
SHA1_TOOLS="$CARD/apps/sbin/sha1sum /net/rcc/usr/bin/sha1sum /usr/bin/sha1sum"
same_file() {
    [ -f "$1" ] && [ -f "$2" ] || return 1
    if command -v cmp >/dev/null 2>&1; then cmp -s "$1" "$2"; return; fi
    for s in $SHA1_TOOLS; do
        [ -f "$s" ] || continue
        a=$("$s" "$1" 2>/dev/null) && b=$("$s" "$2" 2>/dev/null) || continue
        a=${a%%[ 	]*}; b=${b%%[ 	]*}
        [ ${#a} -eq 40 ] && [ ${#b} -eq 40 ] || continue
        [ "$a" = "$b" ]; return
    done
    if command -v cksum >/dev/null 2>&1; then
        a=$(set -- $(cksum "$1" 2>/dev/null); echo "${1:-} ${2:-}")
        b=$(set -- $(cksum "$2" 2>/dev/null); echo "${1:-} ${2:-}")
        [ "$a" != " " ] && [ "$a" = "$b" ]; return
    fi
    return 1
}
file_size() { set -- $(ls -l "$1" 2>/dev/null); echo "${5:-}"; }

problem() { echo "  PROBLEM: $*"; echo x >> "$ST"; }
rm_file() {
    [ -f "$1" ] || [ -L "$1" ] || return 0
    if rm -f "$1" && [ ! -e "$1" ]; then echo "  entfernt $1"; else problem "kann $1 nicht entfernen"; fi
}

clean() {
    mount -uw /mnt/app    2>/dev/null || true
    mount -uw /mnt/system 2>/dev/null || true

    echo "-- Original-Dateien zurueck"
    L=/tmp/q7_clean_stock.$$
    find /mnt/app /mnt/system -name '*.carplay-stock' > "$L" 2>/dev/null
    n=0
    while IFS= read -r bak; do
        [ -n "$bak" ] || continue
        n=$((n+1)); orig=${bak%.carplay-stock}
        if mv -f "$bak" "$orig"; then echo "  zurueck: $orig"; else problem "zurueck $orig"; fi
    done < "$L"
    rm -f "$L"
    [ $n -gt 0 ] || echo "  (keine Sicherungen da)"

    echo "-- CarPlay-Dateien"
    for f in $OWNED; do rm_file "$f"; done

    echo "-- Schalter / Trigger-Dateien"
    for f in /mnt/app/root/mibr-carplay111* /mnt/app/root/mibr-alt111* \
             /mnt/app/root/aa_cluster.* /mnt/app/root/altscreen_render.* \
             /mnt/app/root/carplay_* /mnt/app/carplay_* /mnt/app/mibr-carplay111*; do
        [ -f "$f" ] && rm_file "$f"
    done

    echo "-- Reste"
    L=/tmp/q7_clean_tmp.$$
    find /mnt/app /mnt/system \( -name '*.carplay-new*' -o -name '*.carplay-work*' \) > "$L" 2>/dev/null
    while IFS= read -r f; do [ -n "$f" ] && rm_file "$f"; done < "$L"
    rm -f "$L"

    echo "-- Hidden-Menue-Seite"
    rm_file "$GEM/mib2q-carplay.esd"
    if [ -d "$GEM/scripts/carplay" ]; then
        rm -rf "$GEM/scripts/carplay"
        if [ -d "$GEM/scripts/carplay" ]; then problem "kann $GEM/scripts/carplay nicht entfernen"
        else echo "  entfernt $GEM/scripts/carplay/"; fi
    fi

    echo "-- Renderer-Zwischenspeicher und Absturzprotokolle unserer Renderer"
    if [ -d /mnt/persist/var/app/luka_carplay_maneuver ]; then
        rm -rf /mnt/persist/var/app/luka_carplay_maneuver && echo "  entfernt /mnt/persist/var/app/luka_carplay_maneuver/"
    fi
    for f in /mnt/ota/system/core/maneuver_render* /mnt/ota/system/core/altscreen_render*; do
        [ -f "$f" ] && rm_file "$f"
    done

    echo "-- Audio-Treiber"
    if [ ! -f "$DEVA_STOCK" ]; then
        echo "  (keine Pruefdatei auf der Karte - nur Sicherung zurueckgelegt)"
    elif [ ! -f "$DEVA" ]; then
        problem "$DEVA fehlt"
    elif same_file "$DEVA" "$DEVA_STOCK"; then
        echo "  $DEVA = Original (geprueft)"
    else
        echo "  $DEVA ist nicht das Original - Original von der Karte wird eingesetzt"
        t=$DEVA.q7-new.$$
        if cp "$DEVA_STOCK" "$t" && [ "$(file_size "$DEVA_STOCK")" = "$(file_size "$t")" ] &&
           chmod 755 "$t" && mv -f "$t" "$DEVA" && same_file "$DEVA" "$DEVA_STOCK"; then
            echo "  $DEVA = Original (eingesetzt und geprueft)"
        else
            rm -f "$t"; problem "Original-Audio-Treiber konnte nicht eingesetzt werden"
        fi
    fi
    sync
}

say_all() { while IFS= read -r l; do echo "$l"; echo "$l" >> "$LOG"; done; }

: > "$ST"
clean 2>&1 | say_all
if [ -s "$ST" ]; then rm -f "$ST"; exit 1; fi
rm -f "$ST"
echo "Unit sauber: keine CarPlay-Dateien und keine Schalter mehr." | say_all
exit 0
