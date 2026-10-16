#!/bin/sh
# maneuver_render monitor for one smartphone_integrator/dio generation.
# It never controls USB, OTG, dio_manager or the SI retry state machine.

H=${H:-/mnt/app/root/hooks}
WLOG=${WLOG:-/tmp/carplay_wrapper.log}
OWNER_FILE=${OWNER_FILE:-/tmp/carplay_supervisor.owner}
# Power-on gate: native navigation misses its ~60 s service-manager start deadline when a phone
# session starts in the same window, and is relaunched (carplay_logs 024/027).  The renderers
# are useless before navigation exists, so the first start after power-on waits for Java's
# NavReadyMarker, at most NAV_WAIT_MAX_S in total across generations.  /tmp is RAM.
NAV_READY=${NAV_READY:-/tmp/carplay_nav_ready}
NAV_GATE=${NAV_GATE:-/tmp/carplay_renderer_gate}
NAV_WAIT_MAX_S=${NAV_WAIT_MAX_S:-90}
DIO_PID=${1:-}

case "$DIO_PID" in
    ''|*[!0-9]*|0|1)
        echo "[monitor] invalid dio pid: $DIO_PID" >> "$WLOG"
        exit 2
        ;;
esac

if [ ! -r "$H/carplay_processes.sh" ]; then
    echo "[monitor] missing $H/carplay_processes.sh" >> "$WLOG"
    exit 127
fi
. "$H/carplay_processes.sh"

monitor_owns_generation()
{
    MON_OWNER=
    [ -r "$OWNER_FILE" ] && read MON_OWNER < "$OWNER_FILE"
    [ "$MON_OWNER" = "$DIO_PID" ]
}

monitor_dio_alive()
{
    [ -d "/proc/$DIO_PID" ]
}

monitor_current()
{
    monitor_owns_generation && monitor_dio_alive
}

start_renderer()
{
    MON_NAME=$1
    MON_REASON=$2
    monitor_current || return 0

    if cp_renderer_running "$MON_NAME"; then
        if [ "$MON_REASON" = initial ] && ! cp_renderer_healthy "$MON_NAME"; then
            echo "[monitor] $MON_NAME not ready; confirming in 2s" >> "$WLOG"
            sleep 2
            monitor_current || return 0
            if cp_renderer_running "$MON_NAME" && cp_renderer_healthy "$MON_NAME"; then
                echo "[monitor] $MON_NAME became ready" >> "$WLOG"
                return 0
            fi
            echo "[monitor] $MON_NAME still not ready; replacing" >> "$WLOG"
            cp_kill_renderer "$MON_NAME" 1
        else
            [ "$MON_REASON" = initial ] &&
                echo "[monitor] adopted $MON_NAME" >> "$WLOG"
            return 0
        fi
    fi

    if [ "$MON_REASON" = restart ]; then
        sleep 5
        monitor_current || return 0
    fi

    [ -x "$H/$MON_NAME" ] || {
        echo "[monitor] missing executable $H/$MON_NAME" >> "$WLOG"
        return 0
    }

    # Ownership may change during health probing or backoff. Re-scan before
    # spawning so a live renderer hidden by a stale PID file is adopted.
    monitor_current || return 0
    cp_renderer_running "$MON_NAME" && return 0
    echo "[monitor] starting $MON_NAME reason=$MON_REASON" >> "$WLOG"

    (
        cd "$H" || exit 1
        monitor_current || exit 0
        LD_PRELOAD= GRAPHICS_ROOT=/proc/boot exec "$H/$MON_NAME" \
            </dev/null >>"/tmp/$MON_NAME.log" 2>&1
    ) &
    MON_NEW_PID=$!

    # A replacement generation can take ownership between fork and publish.
    # The child performs the same check before exec; never overwrite the new
    # generation's registry after ownership has changed.
    if monitor_current; then
        cp_renderer_record_pid "$MON_NAME" "$MON_NEW_PID" || :
    fi
}

# 0 = start the renderers now, 1 = this generation ended while waiting.  NAV_GATE holds the
# seconds already waited this boot ("done" once released), so a replaced generation resumes the
# wait instead of restarting it.  A running renderer or a later connect never waits.
monitor_nav_gate()
{
    MON_WAITED=0
    [ -r "$NAV_GATE" ] && read MON_WAITED < "$NAV_GATE"
    [ "$MON_WAITED" = done ] && return 0
    case "$MON_WAITED" in ''|*[!0-9]*) MON_WAITED=0 ;; esac
    if [ -e "$NAV_READY" ] || cp_renderer_running maneuver_render; then
        echo done > "$NAV_GATE" 2>/dev/null
        return 0
    fi
    echo "[monitor] holding renderers until native navigation is up (waited ${MON_WAITED}s, max ${NAV_WAIT_MAX_S}s)" >> "$WLOG"
    while [ ! -e "$NAV_READY" ] && [ "$MON_WAITED" -lt "$NAV_WAIT_MAX_S" ]; do
        monitor_current || return 1
        sleep 2
        MON_WAITED=`expr "$MON_WAITED" + 2`
        echo "$MON_WAITED" > "$NAV_GATE" 2>/dev/null
    done
    if [ -e "$NAV_READY" ]; then
        echo "[monitor] native navigation up after ${MON_WAITED}s; starting renderers" >> "$WLOG"
    else
        echo "[monitor] native navigation not up after ${MON_WAITED}s; starting renderers anyway" >> "$WLOG"
    fi
    echo done > "$NAV_GATE" 2>/dev/null
    return 0
}

monitor_main()
{
    trap 'exit 0' 1 2 15

    # The renderer is a separate process and never gates dio (SI's 10 s budget ends
    # at the phone's control SETUP, which waits on USB/NCM/mDNS, not CPU).  It only
    # has to be ready before Java selects the cluster context, which needs native
    # navigation: so after power-on it waits for navigation (monitor_nav_gate),
    # otherwise it starts at once (GL programs load from the persistent binary cache).
    monitor_current || exit 0
    echo "[monitor] generation=$DIO_PID active" >> "$WLOG"

    cp_seed_renderer_pid_files
    monitor_nav_gate || exit 0
    start_renderer maneuver_render initial
    # AltScreen CarPlay-video renderer (optional): started only when installed.
    # Same ownership/identity discipline as maneuver_render; runs LD_PRELOAD-clear.
    [ -x "$H/altscreen_render" ] && start_renderer altscreen_render initial

    MON_TICKS=0
    while monitor_current; do
        start_renderer maneuver_render restart
        [ -x "$H/altscreen_render" ] && start_renderer altscreen_render restart
        sleep 2
        MON_TICKS=`expr "$MON_TICKS" + 1`
        if [ `expr "$MON_TICKS" % 150` -eq 0 ]; then
            cp_cap_all_logs "$WLOG"
        fi
    done

    if monitor_owns_generation; then
        echo "[monitor] dio_manager pid=$DIO_PID exited; renderer remains persistent" >> "$WLOG"
    else
        echo "[monitor] generation=$DIO_PID superseded" >> "$WLOG"
    fi
}

monitor_main
