#!/bin/sh
# Exercise the actual monitor functions with harmless host-side fakes.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
export TEST_DIR

# The real startup path must publish its own PID, launch the monitor without the
# hook, and exec (not fork) dio_manager with the hook and original arguments.
STARTUP_APP=$TEST_DIR/app
STARTUP_HOOKS=$TEST_DIR/hooks
mkdir -p "$STARTUP_APP" "$STARTUP_HOOKS"
cat > "$STARTUP_APP/dio_manager" <<'SH'
#!/bin/sh
echo "$$|${LD_PRELOAD:-}|$*" > "$STARTUP_TEST_DIO"
SH
cat > "$STARTUP_HOOKS/carplay_monitor.sh" <<'SH'
#!/bin/sh
echo "${LD_PRELOAD:-}|$1" > "$STARTUP_TEST_MONITOR"
SH
chmod +x "$STARTUP_APP/dio_manager" "$STARTUP_HOOKS/carplay_monitor.sh"
: > "$STARTUP_HOOKS/libcarplay_hook.so"
: > "$STARTUP_HOOKS/carplay_processes.sh"
STARTUP_TEST_DIO=$TEST_DIR/dio.env
STARTUP_TEST_MONITOR=$TEST_DIR/monitor.env
export STARTUP_TEST_DIO STARTUP_TEST_MONITOR
DIODIR=$STARTUP_APP H=$STARTUP_HOOKS WLOG=$TEST_DIR/startup.log \
OWNER_FILE=$TEST_DIR/startup.owner \
    sh "$ROOT/deploy/smartphone_integrator/carplay_startup.sh" alpha beta
sleep 1
STARTUP_OLD_IFS=$IFS
IFS='|' read STARTUP_DIO_PID STARTUP_DIO_PRELOAD STARTUP_DIO_ARGS < "$STARTUP_TEST_DIO"
IFS='|' read STARTUP_MON_PRELOAD STARTUP_MON_PID < "$STARTUP_TEST_MONITOR"
IFS=$STARTUP_OLD_IFS
[ "$(cat "$TEST_DIR/startup.owner")" = "$STARTUP_DIO_PID" ]
[ "$STARTUP_DIO_PRELOAD" = "$STARTUP_HOOKS/libcarplay_hook.so" ]
[ "$STARTUP_DIO_ARGS" = 'alpha beta' ]
[ -z "$STARTUP_MON_PRELOAD" ]
[ "$STARTUP_MON_PID" = "$STARTUP_DIO_PID" ]

python3 - "$ROOT/deploy/smartphone_integrator/carplay_monitor.sh" "$TEST_DIR/functions.sh" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
functions = re.findall(r'^\w+\(\)\n\{\n.*?^\}', s, re.M | re.S)
open(sys.argv[2], 'w').write('\n\n'.join(functions))
PY
. "$TEST_DIR/functions.sh"

H=$TEST_DIR
WLOG=$TEST_DIR/wrapper.log
OWNER_FILE=$TEST_DIR/owner
DIO_PID=100
printf '#!/bin/sh\nexit 0\n' > "$H/maneuver_render"
chmod +x "$H/maneuver_render"

monitor_dio_alive() { [ "$ALIVE" = 1 ]; }
cp_renderer_running() { [ "$RENDERER_LIVE" = 1 ]; }
cp_renderer_healthy() { return 0; }
cp_renderer_record_pid() { echo "$1" >> "$TEST_DIR/spawns"; }
cp_kill_renderer() { echo "$1" >> "$TEST_DIR/replaced"; RENDERER_LIVE=0; }
cp_seed_renderer_pid_files() { :; }
cp_cap_all_logs() { :; }
sleep() {
    case "$SCENARIO:$1" in
        replace:5) echo 200 > "$OWNER_FILE" ;;
        death:5) ALIVE=0 ;;
        adopted:5) RENDERER_LIVE=1 ;;
        *) : ;;
    esac
}

for RENDERER in maneuver_render; do
    for SCENARIO in replace death adopted; do
        ALIVE=1
        RENDERER_LIVE=0
        echo 100 > "$OWNER_FILE"
        rm -f "$TEST_DIR/spawns"
        start_renderer "$RENDERER" restart || :
        wait
        if [ -s "$TEST_DIR/spawns" ]; then
            echo "FAIL: stale/ceased monitor spawned $RENDERER after $SCENARIO" >&2
            exit 1
        fi
    done
done

# The current generation starts a genuinely missing renderer.
SCENARIO=current
ALIVE=1
RENDERER_LIVE=0
echo 100 > "$OWNER_FILE"
rm -f "$TEST_DIR/spawns"
start_renderer maneuver_render restart
wait
[ "$(cat "$TEST_DIR/spawns")" = maneuver_render ]

# Healthy adoption is preserved; an unhealthy initial adoption is replaced.
RENDERER_LIVE=1
rm -f "$TEST_DIR/spawns" "$TEST_DIR/replaced"
start_renderer maneuver_render initial
[ ! -e "$TEST_DIR/spawns" ] && [ ! -e "$TEST_DIR/replaced" ]
cp_renderer_healthy() { return 1; }
start_renderer maneuver_render initial
wait
[ "$(cat "$TEST_DIR/replaced")" = maneuver_render ]
[ "$(cat "$TEST_DIR/spawns")" = maneuver_render ]

# Power-on navigation gate: wait for Java's marker, resume across generations, cap, never twice.
NAV_READY=$TEST_DIR/nav_ready
NAV_GATE=$TEST_DIR/nav_gate
NAV_WAIT_MAX_S=6
RENDERER_LIVE=0
ALIVE=1
echo 100 > "$OWNER_FILE"
gate_reset() { rm -f "$NAV_READY" "$NAV_GATE"; : > "$WLOG"; }
sleep() { [ "$SCENARIO" = appears ] && [ "$(cat "$NAV_GATE" 2>/dev/null)" = 2 ] && : > "$NAV_READY"; :; }

SCENARIO=ready; gate_reset; : > "$NAV_READY"
gate_fail() { echo "FAIL: nav gate $SCENARIO: $1" >&2; exit 1; }
monitor_nav_gate || gate_fail released
[ "$(cat "$NAV_GATE")" = done ] && [ ! -s "$WLOG" ] || gate_fail 'marker present: no wait'

SCENARIO=appears; gate_reset
monitor_nav_gate || gate_fail released
[ "$(cat "$NAV_GATE")" = done ] && grep -q 'navigation up after 4s' "$WLOG" || gate_fail 'released by marker'

SCENARIO=never; gate_reset
monitor_nav_gate || gate_fail released
[ "$(cat "$NAV_GATE")" = done ] && grep -q 'not up after 6s; starting renderers anyway' "$WLOG" || gate_fail cap

SCENARIO=again; : > "$WLOG"                     # later connect this boot: no wait, no log
monitor_nav_gate || gate_fail released
[ ! -s "$WLOG" ] || gate_fail 'second start waited'

SCENARIO=superseded; gate_reset; echo 4 > "$NAV_GATE"; ALIVE=0
if monitor_nav_gate; then echo 'FAIL: ended generation released the renderers' >&2; exit 1; fi
[ "$(cat "$NAV_GATE")" = 4 ] || gate_fail 'wait not kept'   # the next generation resumes at 4 s
ALIVE=1
monitor_nav_gate || gate_fail released
grep -q 'waited 4s' "$WLOG" && grep -q 'not up after 6s' "$WLOG" || gate_fail 'resume'

SCENARIO=adopted; gate_reset; RENDERER_LIVE=1   # renderer already running: never hold it
monitor_nav_gate || gate_fail released
[ "$(cat "$NAV_GATE")" = done ] && [ ! -s "$WLOG" ] || gate_fail 'adopted renderer held'
RENDERER_LIVE=0

# Boot slog snapshots: once per boot, only while navigation is not up, never tied to the generation.
BOOT_SNAP_MARK=$TEST_DIR/boot_snap.started
BOOT_SNAP_PREFIX=$TEST_DIR/boot_slog_
BOOT_SNAP_AT='60 240'
snap_fail() { echo "FAIL: boot snapshot: $1" >&2; exit 1; }
sleep() { echo "$1" >> "$TEST_DIR/snap_sleeps"; }
pidin() { echo '123 /navigation/navStartup -sm-restart 1'; echo '9 /bin/other'; }
sloginfo() { echo 'Jan 01 00:00:32 startDomain( Nav, 0x700 )'; }
VERBOSE_MARKERS="$TEST_DIR/verbose_persist $TEST_DIR/verbose_tmp"
rm -f "$NAV_READY" "$TEST_DIR/snap_sleeps" $VERBOSE_MARKERS; : > "$WLOG"
monitor_boot_snapshot; wait                       # verbose off: nothing at all
[ ! -e "$BOOT_SNAP_MARK" ] && [ ! -s "$WLOG" ] && [ ! -e "$TEST_DIR/snap_sleeps" ] || snap_fail 'taken without verbose'
: > "$TEST_DIR/verbose_persist"
: > "$NAV_READY"
monitor_boot_snapshot; wait
[ ! -e "$BOOT_SNAP_MARK" ] && [ ! -s "$WLOG" ] || snap_fail 'taken although navigation was up'
rm -f "$NAV_READY"
monitor_boot_snapshot; wait
for s in 60 240; do
    f=${BOOT_SNAP_PREFIX}${s}s.txt
    [ -f "$f" ] && grep -q "== $s s after" "$f" && grep -q navStartup "$f" && ! grep -q /bin/other "$f" \
        && grep -q 'startDomain( Nav' "$f" || snap_fail "snapshot at ${s}s"
done
[ "$(tr '\n' ' ' < "$TEST_DIR/snap_sleeps")" = '60 180 ' ] || snap_fail "sleeps: $(cat "$TEST_DIR/snap_sleeps")"
grep -q 'boot slog snapshots in 60 240s' "$WLOG" || snap_fail 'not logged'
rm -f "${BOOT_SNAP_PREFIX}"*; : > "$WLOG"
monitor_boot_snapshot; wait                       # later generation this boot: nothing
[ ! -e "${BOOT_SNAP_PREFIX}60s.txt" ] && [ ! -s "$WLOG" ] || snap_fail 'taken twice'
unset -f pidin sloginfo

# Power-on navigation boost: once per boot, only while navigation is not up, re-applied until it
# is up, then restored; off marker and a missing helper mean nothing; trace only with verbose.
NAV_BOOST_MARK=$TEST_DIR/nav_boost.started
NAV_BOOST_STATE=$TEST_DIR/nav_boost.state
NAV_BOOST_OFF=$TEST_DIR/nav_boost.off
NAV_BOOST_MAX_S=8
NAV_BOOST_FROM=10
NAV_BOOST_TO=12
NAV_BOOST_NAMES='AppStartATF navStartup'
boost_fail() { echo "FAIL: nav boost: $1" >&2; exit 1; }
boost_reset() { rm -f "$NAV_BOOST_MARK" "$NAV_BOOST_OFF" "$NAV_READY" "$TEST_DIR/boost_calls" "$H/nav_boost"; : > "$WLOG"; }
boost_helper() {
    printf '#!/bin/sh\necho "$*" >> "%s"\ncase $1 in 10) echo 7 1 ;; *) echo 7 1 ;; esac\n' \
        "$TEST_DIR/boost_calls" > "$H/nav_boost"
    chmod +x "$H/nav_boost"
}
sleep() { n=`cat "$TEST_DIR/boost_calls" 2>/dev/null | wc -l`; [ "$SCENARIO" = up ] && [ "$n" -ge 2 ] && : > "$NAV_READY"; :; }

SCENARIO=up; boost_reset; boost_helper; rm -f $VERBOSE_MARKERS
monitor_nav_boost; wait
[ "$(sed -n 1p "$TEST_DIR/boost_calls")" = "10 12 $NAV_BOOST_STATE AppStartATF navStartup" ] || boost_fail "boost call: $(cat "$TEST_DIR/boost_calls")"
[ "$(tail -1 "$TEST_DIR/boost_calls")" = "-r $NAV_BOOST_STATE" ] || boost_fail 'not restored'
[ "$(grep -c '^10 12' "$TEST_DIR/boost_calls")" = 2 ] || boost_fail "not re-applied until up: $(cat "$TEST_DIR/boost_calls")"
[ ! -s "$WLOG" ] || boost_fail 'logged without verbose'

SCENARIO=never; boost_reset; boost_helper; : > "$TEST_DIR/verbose_persist"
monitor_nav_boost; wait
[ "$(grep -c '^10 12' "$TEST_DIR/boost_calls")" = 4 ] && [ "$(tail -1 "$TEST_DIR/boost_calls")" = "-r $NAV_BOOST_STATE" ] \
    || boost_fail "cap: $(cat "$TEST_DIR/boost_calls")"
grep -q 'priority 10 -> 12' "$WLOG" && grep -q 'nav boost ended after 8s (nav_ready=no): restored 7 1' "$WLOG" || boost_fail 'verbose trace'
: > "$TEST_DIR/boost_calls.before"; cp "$TEST_DIR/boost_calls" "$TEST_DIR/boost_calls.before"
monitor_nav_boost; wait                           # later generation this boot
cmp -s "$TEST_DIR/boost_calls" "$TEST_DIR/boost_calls.before" || boost_fail 'ran twice'

for case in ready off missing; do
    boost_reset; boost_helper
    case $case in ready) : > "$NAV_READY" ;; off) : > "$NAV_BOOST_OFF" ;; missing) rm -f "$H/nav_boost" ;; esac
    monitor_nav_boost; wait
    [ ! -e "$TEST_DIR/boost_calls" ] && [ ! -e "$NAV_BOOST_MARK" ] || boost_fail "ran with $case"
done
rm -f "$H/nav_boost" $VERBOSE_MARKERS

# Runtime supervisor code must remain out of USB/OTG and dio ownership.
if grep -E 'media-con-ctrl|reset port|start_stack|kill .*DIO_PID' \
    "$ROOT/deploy/smartphone_integrator/carplay_startup.sh" \
    "$ROOT/deploy/smartphone_integrator/carplay_monitor.sh" \
    "$ROOT/deploy/smartphone_integrator/carplay_processes.sh" >/dev/null; then
    echo 'FAIL: supervisor contains USB/OTG or dio kill policy' >&2
    exit 1
fi

echo 'Supervisor lifecycle: generation handoff, death/backoff, adoption and USB ownership PASS'
sh "$ROOT/tests/renderer_pid_identity_test.sh"
