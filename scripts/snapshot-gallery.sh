#!/bin/bash
# Renders every GalleryScenarios entry (light + dark) with one run of the xFractalGalleryTests target, imports the PNGs
# into previews/ and checks the gallery (planning/gallery-scenarios-plan.md).
#
#   scripts/snapshot-gallery.sh [--only PATTERN] [--lang en] [--keep-booted] [--no-open] [--verbose]
#   scripts/snapshot-gallery.sh --shutdown
#
# --only PATTERN   comma-separated substrings of scenario names or slugs; renders just those (the check covers all)
# --lang en        the languages to render (the app ships English only; another language is one more test run later)
# --keep-booted    fallback only: leave the simulator running for the next run (shut it down later with --shutdown)
# --no-open        do not open the page
# --verbose        also print the test's per-render timing lines
# --shutdown       fallback only: shut down the simulator this script booted, and nothing else; never creates or boots one
#
# One run at a time (a lock in the shared git directory, held across worktrees).
#
# The simulator comes from the machine-wide pool when `simpool` and `buildlock` are on PATH: `simpool acquire --spec
# iphone` (iPhone 17 Pro, iOS 27.0) leases a booted simulator to this script, waiting when the pool is full, and the
# cleanup gives it back with `simpool release` (still booted) on success, failure and INT/TERM/HUP. The script then
# never boots, shuts down, creates or erases a simulator, and both xcodebuild commands run under `buildlock` on the
# DerivedData folder (the test without a build slot).
#
# Fallback, without those tools: one simulator at a time; the script's own simulator is "xFractal Agent" (created when
# missing) and a simulator of anyone else is never touched. At the start the script
# waits up to 10 minutes for another simulator to go away; right before the boot, the build and the test it fails if
# one has appeared. Ownership is a marker file written the moment the boot is accepted ("pending", then
# "<source>:<identity>" once readable): only that boot is ever shut down, a pending one always. An "xFractal Agent"
# somebody else booted is borrowed and left running. A listing of the simulators that fails is a failure, never
# "none". INT, TERM and HUP run the same cleanup (owned work stopped: TERM, then KILL after XFRACTAL_SNAPSHOT_KILL_GRACE
# seconds, 10 by default; owned boot shut down) and exit 130, 143 and 129.
#
# DerivedData is persistent (XFRACTAL_SNAPSHOT_DD, default ~/Library/Developer/Xcode/DerivedData/xFractal-snapshots):
# build-for-testing is incremental. The whole gallery target runs, so its plain tests gate every render.
# The Xcode project is generated (XcodeGen) when it is missing or older than project.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_NAME="${XFRACTAL_SNAPSHOT_SIM:-xFractal Agent}"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
DD="${XFRACTAL_SNAPSHOT_DD:-$HOME/Library/Developer/Xcode/DerivedData/xFractal-snapshots}"
MARKER="${TMPDIR:-/tmp}/xfractal-snapshot-gallery.booted"

ARGS=("$@")
ONLY=""; LANGS=(en); KEEP_BOOTED=0; OPEN_PAGE=1; SHUTDOWN_ONLY=0; VERBOSE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="${2:?--only needs a pattern}"; shift 2 ;;
        --lang)
            IFS=',' read -r -a LANGS <<< "${2:?--lang needs a list such as en}"
            for l in "${LANGS[@]}"; do
                case "$l" in en) ;; *) echo "--lang supports en only (got '$l')" >&2; exit 2 ;; esac
            done
            shift 2 ;;
        --keep-booted) KEEP_BOOTED=1; shift ;;
        --no-open) OPEN_PAGE=0; shift ;;
        --verbose) VERBOSE=1; shift ;;
        --shutdown) SHUTDOWN_ONLY=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# One run at a time, across the main checkout and its worktrees. XFRACTAL_SNAPSHOT_LOCK is for the lifecycle tests.
# The locked run is a child this wrapper forwards INT/TERM/HUP to (to the script under lockf), so a signal reaches the
# script that owns the work.
if [ -z "${XFRACTAL_GALLERY_LOCKED:-}" ]; then
    # The lock lives in the git directory shared by the main checkout and its worktrees (also when the repository is a
    # submodule), so it is never part of a checkout.
    COMMON="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    [ -n "$COMMON" ] || COMMON="$ROOT/.build"
    LOCK="${XFRACTAL_SNAPSHOT_LOCK:-$COMMON/snapshot-gallery.lock}"
    mkdir -p "$(dirname "$LOCK")"
    /usr/bin/lockf -k -s -t 0 "$LOCK" true || echo "snapshot-gallery: waiting for another gallery run (up to 10 minutes)" >&2
    /usr/bin/lockf -k -t "${XFRACTAL_SNAPSHOT_LOCK_WAIT:-600}" "$LOCK" env XFRACTAL_GALLERY_LOCKED=1 "$ROOT/scripts/snapshot-gallery.sh" ${ARGS[@]+"${ARGS[@]}"} &
    LOCKED=$!
    # lockf does not pass a signal on to the command it runs: signal that command (its child), and lockf ends with it.
    # A background child ignores SIGINT, so every initiating signal is forwarded as TERM; the wrapper then exits with the
    # status of the signal that started it (130 INT, 129 HUP, 143 TERM) once the child's cleanup has finished.
    SIGSTATUS=""
    forward() { SIGSTATUS="$1"; pkill -TERM -P "$LOCKED" 2>/dev/null || kill -TERM "$LOCKED" 2>/dev/null || true; }
    trap 'forward 130' INT
    trap 'forward 129' HUP
    trap 'forward 143' TERM
    STATUS=0
    wait "$LOCKED" || STATUS=$?
    if [ "$STATUS" -gt 128 ]; then     # interrupted by the forwarded signal: collect the real status
        AGAIN=0; wait "$LOCKED" || AGAIN=$?
        [ "$AGAIN" != 127 ] && STATUS=$AGAIN
    fi
    [ "$STATUS" = 75 ] && echo "snapshot-gallery: another gallery run still holds the lock after 10 minutes" >&2
    [ -n "$SIGSTATUS" ] && STATUS="$SIGSTATUS"
    exit "$STATUS"
fi

# The machine-wide simulator pool and build lock, when installed.
POOL=0
if command -v simpool > /dev/null && command -v buildlock > /dev/null; then POOL=1; fi
APP_BUNDLE_ID="ch.arizonasoftware.xfractal"

# --- simulator queries (fallback) (one `simctl list devices -j` each) ---
# The listing is captured first and validated: a failed `simctl list` (inside `$(...)` errexit does not fire) must
# fail the script and never read as "no simulator booted".
sim_list() {
    local json
    json="$(xcrun simctl list devices -j)" || { echo "snapshot-gallery: 'xcrun simctl list devices' failed" >&2; return 1; }
    printf '%s' "$json" | python3 -c 'import json, sys; json.load(sys.stdin)["devices"]' \
        || { echo "snapshot-gallery: 'xcrun simctl list devices' printed no device list" >&2; return 1; }
    printf '%s' "$json"
}

sim_query() {   # $1 = mode (udid|state|boottime|others), $2 = name or UDID
    local json
    json="$(sim_list)" || return 1
    printf '%s' "$json" | python3 -c '
import json, sys
mode, arg = sys.argv[1], sys.argv[2]
devices = [d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d.get("isAvailable", True)]
if mode == "udid":        # our simulator by name
    print(next((d["udid"] for d in devices if d["name"] == arg), ""))
elif mode == "state":     # Booted | Shutdown | ... | gone
    d = next((d for d in devices if d["udid"] == arg), None)
    print(d["state"] if d else "gone")
elif mode == "boottime":  # simctl'"'"'s lastBootedAt, when it lists one
    d = next((d for d in devices if d["udid"] == arg), None)
    print(d.get("lastBootedAt", "") if d else "")
elif mode == "others":    # every other booted simulator
    print(" ".join(d["udid"] for d in devices if d["state"] == "Booted" and d["udid"] != arg))
' "$1" "$2"
}

# --- boot identity: ONE representation, "<source>:<value>", recorded with its source ---
# `proc` is the start time of the device's launchd_sim process (always there on a real Mac); `list` is simctl's
# lastBootedAt. A marker is only ever compared with the source it recorded, so a source that appears later cannot
# make the same boot look like another one. Empty = this source cannot be read now.
identity_from() {   # $1 = UDID, $2 = proc|list
    local pid started stamp
    case "$2" in
        proc)
            pid="$(pgrep -f "launchd_sim.*$1" | head -1 || true)"
            [ -n "$pid" ] || return 0
            started="$(ps -o lstart= -p "$pid" 2>/dev/null || true)"
            [ -n "$started" ] && echo "proc:$started"
            return 0 ;;
        list)
            stamp="$(sim_query boottime "$1")" || return 1
            [ -n "$stamp" ] && echo "list:$stamp"
            return 0 ;;
    esac
}
current_identity() {   # the first source that can be read now
    local ident
    ident="$(identity_from "$1" proc)" || return 1
    [ -n "$ident" ] || ident="$(identity_from "$1" list)" || return 1
    echo "$ident"
}

# Shuts down the simulator this script booted, if that boot is still running. A `pending` marker (written the moment
# the boot was accepted, before an identity could be read) is ours by definition. A readable identity that differs is
# somebody else's boot: the marker is dropped. An unreadable one keeps the marker and fails; so does a failed shutdown.
shutdown_ours() {
    [ -f "$MARKER" ] || return 0
    local udid rec state now
    udid="$(sed -n 1p "$MARKER")"; rec="$(sed -n 2p "$MARKER")"
    state="$(sim_query state "$udid")" || { echo "cannot read the state of simulator $udid; the marker $MARKER is kept" >&2; return 1; }
    if [ "$state" != Booted ]; then rm -f "$MARKER"; return 0; fi
    if [ "$rec" != pending ]; then
        now="$(identity_from "$udid" "${rec%%:*}")" || return 1
        if [ -z "$now" ]; then
            echo "cannot read the boot identity of simulator $udid; the marker $MARKER is kept" >&2
            return 1
        fi
        if [ "$now" != "$rec" ]; then rm -f "$MARKER"; return 0; fi   # another boot: not ours
    fi
    if xcrun simctl shutdown "$udid"; then
        rm -f "$MARKER"
        echo "simulator $udid shut down"
    else
        echo "could not shut down simulator $udid; the marker $MARKER is kept, run --shutdown again" >&2
        return 1
    fi
}

if [ "$SHUTDOWN_ONLY" = 1 ]; then
    if [ "$POOL" = 1 ]; then
        echo "--shutdown: simulators come from the pool (simpool), which shuts them down itself; nothing done" >&2
        exit 0
    fi
    shutdown_ours
    exit $?
fi

now() { python3 -c 'import time; print(time.time())'; }
elapsed() { python3 -c "print(f'{$2 - $1:.1f} s')"; }
T0=$(now)

# One simulator at a time (fallback): wait for anybody else's to go away, never touch it.
wait_for_others() {
    local i others
    for i in $(seq 1 40); do
        others="$(sim_query others "$UDID")" || exit 1
        [ -z "$others" ] && return 0
        [ "$i" = 40 ] && { echo "another simulator is still booted after 10 minutes; not using one: $others" >&2; exit 1; }
        echo "another simulator is booted ($others); waiting" >&2
        sleep "${XFRACTAL_SNAPSHOT_WAIT:-15}"
    done
}
# Right before the boot, the build and the test: a lock wait, a readiness wait or a build can take long enough for
# another session to boot its own. Fails rather than waits.
fail_if_others() {
    [ "$POOL" = 1 ] && return 0    # the pool keeps to the host's budget
    local others
    others="$(sim_query others "$UDID")" || exit 1
    [ -z "$others" ] || { echo "another simulator appeared ($others); not $1" >&2; exit 1; }
}
UDID=""
if [ "$POOL" = 0 ]; then
    # Our simulator, created when missing (never another project's).
    UDID="$(sim_query udid "$SIM_NAME")" || exit 1
    if [ -z "$UDID" ]; then
        UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")"
        echo "created simulator $SIM_NAME ($UDID)"
    fi
    wait_for_others
elif [ "$KEEP_BOOTED" = 1 ]; then
    echo "--keep-booted: the pool keeps its simulators booted anyway" >&2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/xfractal-gallery.XXXXXX")"
CHILD=""
LEASE_OUT=""    # the file a running `simpool acquire` prints its UDID to (read by the cleanup too)
LEASED=""       # the pool simulator to give back

# A foreground command that a signal can interrupt: run in the background, wait, and stop it from the cleanup.
run_logged() {   # $1 = log file, rest = command
    local log="$1" rc=0
    shift
    "$@" > "$log" 2>&1 &
    CHILD=$!
    wait "$CHILD" || rc=$?
    CHILD=""
    return "$rc"
}

# xcodebuild, under buildlock on the DerivedData folder with the pool (a build takes a build slot, a test does not),
# its output in $1. Run in the background like run_logged, so the cleanup can stop it (buildlock passes the signal on).
run_xcodebuild() {   # $1 = log file, $2 = build|test, rest = xcodebuild arguments
    local log="$1" kind="$2" rc=0 lock
    shift 2
    if [ "$POOL" = 1 ]; then
        lock=(--folder "$DD" --log "$log")
        [ "$kind" = test ] && lock+=(--no-slot)
        : > "$log"
        buildlock "${lock[@]}" -- xcodebuild "$@" < /dev/null &
    else
        xcodebuild "$@" > "$log" 2>&1 < /dev/null &
    fi
    CHILD=$!
    wait "$CHILD" || rc=$?
    CHILD=""
    return "$rc"
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    if [ -n "$CHILD" ]; then
        # TERM first; a child that ignores it is killed after a grace period (only the one this script started), then reaped.
        kill "$CHILD" 2>/dev/null || true
        for _ in $(seq 1 $(( ${XFRACTAL_SNAPSHOT_KILL_GRACE:-10} * 10 ))); do
            kill -0 "$CHILD" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$CHILD" 2>/dev/null; then kill -KILL "$CHILD" 2>/dev/null || true; fi
        wait "$CHILD" 2>/dev/null || true
    fi
    if [ "$POOL" = 1 ]; then
        # A lease granted while the script was being signalled is given back too.
        if [ -n "$LEASE_OUT" ]; then LEASED="$(cat "$LEASE_OUT" 2>/dev/null || true)"; fi
        if [ -n "$LEASED" ]; then
            simpool release "$LEASED" --app "$APP_BUNDLE_ID" \
                || { echo "could not give simulator $LEASED back to the pool (simpool status)" >&2; status=1; }
        fi
    # A pending marker is ours whatever --keep-booted says: an identity that could not be read must not leave a
    # simulator nobody can account for.
    elif [ "$KEEP_BOOTED" = 0 ] || [ "$(sed -n 2p "$MARKER" 2>/dev/null)" = pending ]; then
        shutdown_ours || status=1
    fi
    # The logs of a failed run stay; the message names the directory.
    [ "$status" = 0 ] && rm -rf "$WORK"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

cd "$ROOT"
# The project is generated: a fresh worktree has none, and project.yml may be newer than the one on disk.
if [ ! -d xFractal.xcodeproj ] || [ project.yml -nt xFractal.xcodeproj/project.pbxproj ]; then
    command -v xcodegen >/dev/null || { echo "xFractal.xcodeproj is missing or stale and xcodegen is not installed (brew install xcodegen)" >&2; exit 1; }
    xcodegen generate > "$WORK/xcodegen.log" 2>&1 || { cat "$WORK/xcodegen.log"; echo "xcodegen failed (log: $WORK/xcodegen.log)" >&2; exit 1; }
fi

T_BOOT0=$(now)
if [ "$POOL" = 1 ]; then
    # Leased to this script's process ($$): waits, interruptibly, while the pool is full.
    LEASE_OUT="$WORK/lease"
    : > "$LEASE_OUT"
    rc=0
    simpool acquire --spec iphone --pid $$ > "$LEASE_OUT" < /dev/null &
    CHILD=$!
    wait "$CHILD" || rc=$?
    CHILD=""
    LEASED="$(cat "$LEASE_OUT")"; LEASE_OUT=""
    UDID="$LEASED"
    if [ "$rc" != 0 ] || [ -z "$UDID" ]; then
        # Not simpool's 75 (a wait that ran out): the wrapper reads 75 as its own lock wait.
        echo "no iphone simulator from the pool (simpool exit $rc; simpool status shows who holds them)" >&2
        exit 1
    fi
    echo "leased simulator $UDID from the pool"
else
    STATE="$(sim_query state "$UDID")" || exit 1
    # A marker whose simulator is not running, or whose identity is no longer the one recorded, is stale.
    if [ -f "$MARKER" ] && [ "$STATE" != Booted ]; then rm -f "$MARKER"; fi
    if [ -f "$MARKER" ] && [ "$STATE" = Booted ] && [ "$(sed -n 2p "$MARKER")" != pending ]; then
        rec="$(sed -n 2p "$MARKER")"; now_id="$(identity_from "$UDID" "${rec%%:*}")" || exit 1
        [ -z "$now_id" ] || [ "$now_id" = "$rec" ] || rm -f "$MARKER"
    fi
    if [ "$STATE" != Booted ]; then
        fail_if_others "booting"
        xcrun simctl boot "$UDID"
        # Ownership is written the moment the boot is accepted: pending, then the identity with its source once it can be
        # read. Without an identity the run fails, and the pending marker makes the cleanup shut this boot down.
        printf '%s\npending\n' "$UDID" > "$MARKER"
        IDENT=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            if [ "$(sim_query state "$UDID" 2>/dev/null)" = Booted ]; then
                IDENT="$(current_identity "$UDID" 2>/dev/null)" || IDENT=""
                [ -n "$IDENT" ] && break
            fi
            sleep "${XFRACTAL_SNAPSHOT_IDENT_WAIT:-1}"
        done
        if [ -z "$IDENT" ]; then
            echo "booted $UDID but cannot identify the boot; the marker stays pending and the boot is shut down" >&2
            exit 1
        fi
        printf '%s\n%s\n' "$UDID" "$IDENT" > "$MARKER"
        run_logged "$WORK/bootstatus.log" xcrun simctl bootstatus "$UDID"    # interruptible: the cleanup stops it
    elif [ ! -f "$MARKER" ]; then
        echo "$SIM_NAME was booted by someone else: borrowing it, it stays running" >&2
    fi
fi
T_BOOT1=$(now)

T_BUILD0=$(now)
fail_if_others "building"    # after readiness: another session may have booted meanwhile
run_xcodebuild "$WORK/build.log" build build-for-testing -project xFractal.xcodeproj -scheme xFractal-iOS \
    -destination "id=$UDID" -derivedDataPath "$DD" \
    || { tail -30 "$WORK/build.log"; echo "build failed (log: $WORK/build.log)" >&2; exit 1; }
T_BUILD1=$(now)

FIRST_PAGE=""
for lang in "${LANGS[@]}"; do
    fail_if_others "testing"    # immediately before the test command
    T_TEST0=$(now)
    # TEST_RUNNER_<name> in xcodebuild's environment reaches the test process as <name>.
    TEST_RUNNER_XFRACTAL_SNAPSHOT_DIR="$WORK/png-$lang" TEST_RUNNER_XFRACTAL_SNAPSHOT_ONLY="$ONLY" \
    run_xcodebuild "$WORK/test-$lang.log" test test-without-building -project xFractal.xcodeproj -scheme xFractal-iOS \
        -destination "id=$UDID" -derivedDataPath "$DD" \
        -only-testing:xFractalGalleryTests \
        -parallel-testing-enabled NO -enableCodeCoverage NO \
        -testLanguage "$lang" -testRegion US \
        || { grep -E "^gallery: |: error: |✘" "$WORK/test-$lang.log" | sed 's/^/  /' || true
             echo "snapshot test failed [$lang] (log: $WORK/test-$lang.log)" >&2; exit 1; }
    T_TEST1=$(now)
    grep -E "^gallery: [0-9]+ scenario" "$WORK/test-$lang.log" | sed "s/^/[$lang] /" || true
    [ "$VERBOSE" = 1 ] && { grep -E '^gallery: [a-z0-9-]+ (light|dark) ' "$WORK/test-$lang.log" | sed "s/^/[$lang] /" || true; }
    echo "[$lang] $(grep -cE '^gallery: [a-z0-9-]+ (light|dark) ready' "$WORK/test-$lang.log" || true) per-render timing line(s)"
    lang_flag=(--lang "$lang")
    python3 scripts/preview-gallery.py --import "$WORK/png-$lang" ${ONLY:+--partial} "${lang_flag[@]}"
    python3 scripts/preview-gallery.py --check "${lang_flag[@]}"
    echo "timings [$lang]: test $(elapsed "$T_TEST0" "$T_TEST1")"
    if [ -z "$FIRST_PAGE" ]; then
        FIRST_PAGE="$ROOT/previews/index.html"
        [ "$lang" = en ] || FIRST_PAGE="$ROOT/previews/$lang/index.html"
    fi
done

echo "network: none"    # the iOS app has no network client
echo "timings: boot $(elapsed "$T_BOOT0" "$T_BOOT1"), build $(elapsed "$T_BUILD0" "$T_BUILD1"), total $(elapsed "$T0" "$(now)")"
[ "$OPEN_PAGE" = 1 ] && open "$FIRST_PAGE"
exit 0
