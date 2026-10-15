#!/bin/bash
# Lifecycle checks for scripts/snapshot-gallery.sh (planning/gallery-scenarios-plan.md): a stub `xcrun`, `xcodebuild` and
# `xcodegen` first on PATH answer from a state file, so no real simulator is touched.
#
#   scripts/test_snapshot_gallery.sh [case ...]                 # all cases, or the named ones
#   SNAPSHOT_GALLERY_SCRIPT=/path/to/copy scripts/test_snapshot_gallery.sh   # test a mutated copy (mutation checks)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${SNAPSHOT_GALLERY_SCRIPT:-$ROOT/scripts/snapshot-gallery.sh}"
FAILED=0
UDID="11111111-2222-3333-4444-555555555555"
OTHER="88888888-0000-0000-0000-000000000000"

setup() {   # $1 = state ("Booted"|"Shutdown"|"missing"), $2 = lastBootedAt
    T="$(mktemp -d)"
    mkdir -p "$T/bin"
    export TMPDIR="$T" STUB_LOG="$T/calls.log" STUB_STATE="$T/state.json" STUB_FAIL="" XFRACTAL_SNAPSHOT_LOCK="$T/lock" \
        STUB_COUNT="$T/count" XFRACTAL_SNAPSHOT_WAIT=0 XFRACTAL_SNAPSHOT_IDENT_WAIT=0 XFRACTAL_SNAPSHOT_DD="$T/dd" XFRACTAL_SNAPSHOT_KILL_GRACE=1 \
        PREVIEW_GALLERY_OUT="$T/previews"
    unset STUB_OTHER_GONE_AFTER STUB_OTHER_AFTER STUB_PGREP STUB_LSTART STUB_NO_IDENT STUB_OTHER_ON_BOOTSTATUS \
        STUB_BOOTSTATUS_BLOCK STUB_BUILD_BLOCK STUB_TEST_BLOCK STUB_BUILD_FAIL STUB_TEST_MODE STUB_OTHER_DURING_BUILD \
        STUB_IDENT_AFTER STUB_BOOT_NOOP STUB_SHUTDOWN_FAIL_AFTER_TEST STUB_IGNORE_TERM
    : > "$STUB_LOG"
    if [ "$1" = missing ]; then
        echo '{"devices": {"iOS 27.0": []}}' > "$STUB_STATE"
    else
        python3 - "$STUB_STATE" "$UDID" "$1" "${2:-}" <<'PY'
import json, sys
path, udid, state, boot = sys.argv[1:5]
device = {"name": "xFractal Agent", "udid": udid, "state": state, "isAvailable": True}
if boot: device["lastBootedAt"] = boot
json.dump({"devices": {"iOS 27.0": [device]}}, open(path, "w"))
PY
    fi
    cat > "$T/bin/xcrun" <<'STUB'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1" = simctl ] || exit 99
fails() { case ",$STUB_FAIL," in *",$1,"*) return 0 ;; esac; return 1; }
add_other() {
    python3 - "$STUB_STATE" "$1" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if not any(d["name"] == sys.argv[2] for ds in data["devices"].values() for d in ds):
    data["devices"]["iOS 27.0"].append({"name": sys.argv[2], "udid": "88888888-0000-0000-0000-000000000000", "state": "Booted", "isAvailable": True})
json.dump(data, open(sys.argv[1], "w"))
PY
}
set_state() {
    python3 - "$STUB_STATE" "$1" <<'PY'
import json, os, sys
path, state = sys.argv[1:3]
data = json.load(open(path))
for devices in data["devices"].values():
    for d in devices:
        if d["name"] != "xFractal Agent": continue
        d["state"] = state
        if state == "Booted" and not os.environ.get("STUB_NO_IDENT") and not os.environ.get("STUB_IDENT_AFTER"): d["lastBootedAt"] = "boot-new"
json.dump(data, open(path, "w"))
PY
}
case "$2" in
    list)
        fails list && { echo '{"devices": {}}'; echo "list refused" >&2; exit 1; }
        if [ -n "${STUB_OTHER_AFTER:-}" ]; then
            n=$(( $(cat "$STUB_COUNT.late" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_COUNT.late"
            [ "$n" -gt "$STUB_OTHER_AFTER" ] && add_other Late
        fi
        if [ -n "${STUB_IDENT_AFTER:-}" ]; then
            n=$(( $(cat "$STUB_COUNT.ident" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_COUNT.ident"
            [ "$n" -gt "$STUB_IDENT_AFTER" ] && python3 - "$STUB_STATE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for devices in data["devices"].values():
    for d in devices:
        if d["name"] == "xFractal Agent" and d["state"] == "Booted": d["lastBootedAt"] = "late-boot"
json.dump(data, open(sys.argv[1], "w"))
PY
        fi
        if [ -n "${STUB_OTHER_GONE_AFTER:-}" ]; then
            n=$(( $(cat "$STUB_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_COUNT"
            [ "$n" -gt "$STUB_OTHER_GONE_AFTER" ] && python3 - "$STUB_STATE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for devices in data["devices"].values():
    for d in devices:
        if d["name"] == "Other": d["state"] = "Shutdown"
json.dump(data, open(sys.argv[1], "w"))
PY
        fi
        cat "$STUB_STATE" ;;
    boot) [ -n "${STUB_BOOT_NOOP:-}" ] || set_state Booted ;;
    bootstatus)
        fails bootstatus && exit 1
        [ -n "${STUB_BOOTSTATUS_BLOCK:-}" ] && { echo $$ > "$TMPDIR/boot.pid"; if [ -n "${STUB_IGNORE_TERM:-}" ]; then trap '' TERM; while :; do sleep 0.2; done; fi; exec sleep 60; }
        [ -n "${STUB_OTHER_ON_BOOTSTATUS:-}" ] && add_other Midway
        exit 0 ;;
    shutdown) fails shutdown && { echo "shutdown refused" >&2; exit 1; }; set_state Shutdown ;;
    create) echo "$UDID_NEW" ;;
esac
STUB
    cat > "$T/bin/xcodebuild" <<'STUB'
#!/bin/bash
echo "xcodebuild $*" >> "$STUB_LOG"
case "$1" in
    build-for-testing)
        [ -n "${STUB_BUILD_BLOCK:-}" ] && { echo $$ > "$TMPDIR/xcb.pid"; if [ -n "${STUB_IGNORE_TERM:-}" ]; then trap '' TERM; while :; do sleep 0.2; done; fi; exec sleep 60; }
        [ -n "${STUB_BUILD_FAIL:-}" ] && exit 1
        if [ -n "${STUB_OTHER_DURING_BUILD:-}" ]; then
            python3 - "$STUB_STATE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["devices"]["iOS 27.0"].append({"name": "Late", "udid": "88888888-0000-0000-0000-000000000000", "state": "Booted", "isAvailable": True})
json.dump(d, open(sys.argv[1], "w"))
PY
        fi
        exit 0 ;;
    test-without-building)
        [ -n "${STUB_TEST_BLOCK:-}" ] && { echo $$ > "$TMPDIR/xcb.pid"; if [ -n "${STUB_IGNORE_TERM:-}" ]; then trap '' TERM; while :; do sleep 0.2; done; fi; exec sleep 60; }
        case "${STUB_TEST_MODE:-ok}" in
            fail) exit 1 ;;
            noimport) mkdir -p "$TEST_RUNNER_XFRACTAL_SNAPSHOT_DIR" ;;
            badcheck) mkdir -p "$TEST_RUNNER_XFRACTAL_SNAPSHOT_DIR"
                      echo '[{"name":"A","group":"G","slug":"a","size":{"w":4,"h":4},"kinds":[]}]' > "$TEST_RUNNER_XFRACTAL_SNAPSHOT_DIR/manifest.json" ;;
            *) mkdir -p "$TEST_RUNNER_XFRACTAL_SNAPSHOT_DIR"; echo '[]' > "$TEST_RUNNER_XFRACTAL_SNAPSHOT_DIR/manifest.json" ;;
        esac
        exit 0 ;;
esac
exit 0
STUB
    printf '#!/bin/bash\necho "xcodegen $*" >> "$STUB_LOG"\nmkdir -p xFractal.xcodeproj && touch xFractal.xcodeproj/project.pbxproj\n' > "$T/bin/xcodegen"
    # pgrep and ps answer the process-start-time identity only when STUB_PGREP is set.
    printf '#!/bin/bash\n[ -n "$STUB_PGREP" ] && echo 4242 || exit 1\n' > "$T/bin/pgrep"
    printf '#!/bin/bash\necho "$STUB_LSTART"\n' > "$T/bin/ps"
    chmod +x "$T/bin/"*
    export PATH="$T/bin:$PATH"
    MARKER="$T/xfractal-snapshot-gallery.booted"
    # The script resolves its project from its own location: a scratch tree holds the script under test, the real
    # project.yml and a generated-looking project, so the stub xcodegen is not needed unless a case removes it.
    TREE="$T/tree"; mkdir -p "$TREE/scripts"
    cp "$SCRIPT" "$TREE/scripts/snapshot-gallery.sh"
    cp "$ROOT/scripts/preview-gallery.py" "$ROOT/scripts/preview-luminance.swift" "$TREE/scripts/"
    cp "$ROOT/project.yml" "$TREE/project.yml"
    mkdir -p "$TREE/xFractal.xcodeproj"; touch "$TREE/xFractal.xcodeproj/project.pbxproj"
}

expect() {   # $1 = case name, $2 = condition description, rest = test command
    local name="$1" what="$2"; shift 2
    if "$@"; then echo "ok   $name: $what"; else echo "FAIL $name: $what"; FAILED=1; fi
}
called() { grep -q -- "$1" "$STUB_LOG"; }
not_called() { ! called "$1"; }
marker_exists() { [ -f "$MARKER" ]; }
marker_absent() { [ ! -f "$MARKER" ]; }
marker_is() { [ "$(sed -n 2p "$MARKER" 2>/dev/null)" = "$1" ]; }
marker_source_is() { case "$(sed -n 2p "$MARKER" 2>/dev/null)" in "$1":*) return 0 ;; esac; return 1; }
gallery() { "$TREE/scripts/snapshot-gallery.sh" "$@" > "$T/out.log" 2>&1; }
dead() { ! kill -0 "$(cat "$1")" 2>/dev/null; }
alive_after() { kill -0 "$1" 2>/dev/null; }

# --- ownership ---

# The boot is accepted but no identity can be read: the marker is written at once (pending), the run fails, the boot
# is shut down; when that shutdown fails too, the pending marker survives and a later --shutdown finishes the job.
pending_marker() {
    setup Shutdown
    STUB_NO_IDENT=1 gallery --no-open; local status=$?
    expect pending_marker "unidentifiable boot: run fails" [ "$status" != 0 ]
    expect pending_marker "unidentifiable boot: shut down" called "simctl shutdown $UDID"
    expect pending_marker "unidentifiable boot: marker removed" marker_absent
    expect pending_marker "no build started" not_called xcodebuild
    setup Shutdown
    STUB_NO_IDENT=1 STUB_FAIL=shutdown gallery --no-open; status=$?
    expect pending_marker "failed shutdown: run fails" [ "$status" != 0 ]
    expect pending_marker "failed shutdown: the marker is kept, pending" marker_is pending
    unset STUB_NO_IDENT; STUB_FAIL=""
    gallery --shutdown; status=$?
    expect pending_marker "a pending marker is ours: --shutdown shuts it down" called "simctl shutdown $UDID"
    expect pending_marker "--shutdown exits zero" [ "$status" = 0 ]
    expect pending_marker "--shutdown removed the marker" marker_absent
}
missing_identity() { pending_marker; }

# TERM while the identity is still pending: the run ends, the boot is shut down, and a retry starts cleanly.
interrupted_retry() {
    setup Shutdown
    export STUB_NO_IDENT=1 XFRACTAL_SNAPSHOT_IDENT_WAIT=1
    "$TREE/scripts/snapshot-gallery.sh" --no-open > "$T/out.log" 2>&1 &
    local pid=$! i
    for i in $(seq 1 100); do marker_is pending && break; sleep 0.1; done
    expect interrupted_retry "the marker is pending while the identity is unreadable" marker_is pending
    kill -TERM "$pid"; wait "$pid"; local status=$?
    expect interrupted_retry "exits 143" [ "$status" = 143 ]
    expect interrupted_retry "the pending boot was shut down" called "simctl shutdown $UDID"
    expect interrupted_retry "marker removed" marker_absent
    unset STUB_NO_IDENT; export XFRACTAL_SNAPSHOT_IDENT_WAIT=0
    gallery --no-open; status=$?
    expect interrupted_retry "the retry runs to the end" [ "$status" = 0 ]
}

# The boot becomes identifiable only after a few listings: the run waits for it and goes on.
delayed_identity() {
    setup Shutdown
    export STUB_NO_IDENT=1 STUB_IDENT_AFTER=6
    gallery --no-open; local status=$?
    expect delayed_identity "exits zero" [ "$status" = 0 ]
    expect delayed_identity "reached the build" called "xcodebuild build-for-testing"
    expect delayed_identity "shut its own boot down" called "simctl shutdown $UDID"
}

# The boot never shows as Booted (no identity possible): fails, nothing built, marker gone.
boot_not_booted() {
    setup Shutdown
    STUB_BOOT_NOOP=1 gallery --no-open; local status=$?
    expect boot_not_booted "exits non-zero" [ "$status" != 0 ]
    expect boot_not_booted "no build started" not_called xcodebuild
    expect boot_not_booted "marker removed" marker_absent
}

# Without a process identity the marker uses simctl's boot time ("list"); a source that appears later never makes the
# same boot look like another one; an unreadable source keeps the marker.
fallback_identity() {
    setup Shutdown
    export STUB_BOOTSTATUS_BLOCK=1
    "$TREE/scripts/snapshot-gallery.sh" --no-open > "$T/out.log" 2>&1 &
    local pid=$! i
    for i in $(seq 1 100); do [ -s "$T/boot.pid" ] && break; sleep 0.1; done
    expect fallback_identity "recorded with the list source" marker_source_is list
    kill -TERM "$pid"; wait "$pid" 2>/dev/null
    setup Shutdown
    export STUB_BOOTSTATUS_BLOCK=1 STUB_PGREP=1 STUB_LSTART="Thu Oct 15 01:00:00 2026"
    "$TREE/scripts/snapshot-gallery.sh" --no-open > "$T/out.log" 2>&1 &
    pid=$!
    for i in $(seq 1 100); do [ -s "$T/boot.pid" ] && break; sleep 0.1; done
    expect fallback_identity "recorded with the proc source when a process is visible" marker_source_is proc
    kill -TERM "$pid"; wait "$pid" 2>/dev/null
}

identity_source_change() {
    setup Booted boot-2
    export STUB_PGREP=1 STUB_LSTART="Thu Oct 15 01:00:00 2026"
    printf '%s\nlist:boot-2\n' "$UDID" > "$MARKER"
    gallery --shutdown; local status=$?
    expect identity_source_change "list marker, same boot, a process now visible: ours, shut down" called "simctl shutdown $UDID"
    expect identity_source_change "exits zero" [ "$status" = 0 ]
    setup Booted boot-2        # a proc marker whose process cannot be read now
    printf '%s\nproc:Thu Oct 15 01:00:00 2026\n' "$UDID" > "$MARKER"
    gallery --shutdown; status=$?
    expect identity_source_change "unreadable source: exits non-zero" [ "$status" != 0 ]
    expect identity_source_change "unreadable source: no shutdown" not_called "simctl shutdown"
    expect identity_source_change "unreadable source: marker kept" marker_exists
    setup Booted
    export STUB_PGREP=1 STUB_LSTART="Thu Oct 15 02:00:00 2026"
    printf '%s\nproc:Thu Oct 15 01:00:00 2026\n' "$UDID" > "$MARKER"
    gallery --shutdown
    expect identity_source_change "proc marker, another start time: not ours" not_called "simctl shutdown"
    expect identity_source_change "proc marker, another start time: marker dropped" marker_absent
}

stale_marker() {   # the marker's boot is not the running one: nothing is shut down, marker dropped
    setup Booted boot-2
    printf '%s\nlist:boot-1\n' "$UDID" > "$MARKER"
    gallery --shutdown; local status=$?
    expect stale_marker "exits zero" [ "$status" = 0 ]
    expect stale_marker "no shutdown call" not_called "simctl shutdown"
    expect stale_marker "marker removed" marker_absent
}

borrowed() {   # a simulator booted by someone else (no marker) is borrowed
    setup Booted boot-2
    gallery --shutdown; local status=$?
    expect borrowed "exits zero" [ "$status" = 0 ]
    expect borrowed "no shutdown call" not_called "simctl shutdown"
}

borrowed_run() {   # a normal run on a simulator somebody else booted (no marker): used, never shut down
    setup Booted boot-2
    gallery --no-open
    expect borrowed_run "reached the build" called "xcodebuild build-for-testing"
    expect borrowed_run "no boot call" not_called "simctl boot"
    expect borrowed_run "no shutdown call" not_called "simctl shutdown"
    expect borrowed_run "no marker written" marker_absent
}

owned() {   # the same boot as the marker's: it is ours and goes down
    setup Booted boot-2
    printf '%s\nlist:boot-2\n' "$UDID" > "$MARKER"
    gallery --shutdown; local status=$?
    expect owned "exits zero" [ "$status" = 0 ]
    expect owned "shut down the UDID" called "simctl shutdown $UDID"
    expect owned "marker removed" marker_absent
}

no_create() {   # --shutdown never creates or boots a simulator
    setup missing
    gallery --shutdown; local status=$?
    expect no_create "exits zero" [ "$status" = 0 ]
    expect no_create "no create call" not_called "simctl create"
    expect no_create "no boot call" not_called "simctl boot"
}

keep_booted() {   # --keep-booted leaves the boot and its marker; --shutdown ends it
    setup Shutdown
    gallery --keep-booted --no-open; local status=$?
    expect keep_booted "exits zero" [ "$status" = 0 ]
    expect keep_booted "not shut down" not_called "simctl shutdown"
    expect keep_booted "marker kept" marker_exists
    gallery --shutdown; status=$?
    expect keep_booted "--shutdown exits zero" [ "$status" = 0 ]
    expect keep_booted "--shutdown shut it down" called "simctl shutdown $UDID"
    expect keep_booted "marker removed" marker_absent
}

owned_run() {   # a normal run on a shut-down simulator: boots it, runs, shuts it down
    setup Shutdown
    gallery --no-open; local status=$?
    expect owned_run "exits zero" [ "$status" = 0 ]
    expect owned_run "ran build and test in the gallery target" called "only-testing:xFractalGalleryTests"
    expect owned_run "one device, no parallel testing" called "parallel-testing-enabled NO"
    expect owned_run "shut down its own boot" called "simctl shutdown $UDID"
    expect owned_run "marker removed" marker_absent
    expect owned_run "network: none is printed" grep -q "network: none" "$T/out.log"
}

# --- queries and other simulators ---

failed_list_shutdown() {
    setup Booted boot-2
    printf '%s\nlist:boot-2\n' "$UDID" > "$MARKER"
    STUB_FAIL=list gallery --shutdown; local status=$?
    expect failed_list_shutdown "exits non-zero" [ "$status" != 0 ]
    expect failed_list_shutdown "marker kept" marker_exists
    expect failed_list_shutdown "no shutdown call" not_called "simctl shutdown"
}

failed_list_run() {   # a failed `simctl list` is a failure, never "no simulator booted"
    setup Shutdown
    STUB_FAIL=list gallery --no-open; local status=$?
    expect failed_list_run "at start: exits non-zero" [ "$status" != 0 ]
    expect failed_list_run "at start: no create call" not_called "simctl create"
    expect failed_list_run "at start: no boot call" not_called "simctl boot"
    expect failed_list_run "at start: no build started" not_called xcodebuild
}

waits_for_other() {   # another simulator booted when the run starts: it waits, then boots once the other one is gone
    setup Shutdown
    python3 - "$STUB_STATE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["devices"]["iOS 27.0"].append({"name": "Other", "udid": "99999999-0000-0000-0000-000000000000", "state": "Booted", "isAvailable": True})
json.dump(data, open(sys.argv[1], "w"))
PY
    STUB_OTHER_GONE_AFTER=3 gallery --no-open
    expect waits_for_other "waited" grep -q "another simulator is booted" "$T/out.log"
    expect waits_for_other "booted ours after the wait" called "simctl boot $UDID"
    expect waits_for_other "never touched the other" not_called "99999999"
}

appears_before_boot() {   # appeared after the first look, before our boot: fails, no boot
    setup Shutdown
    STUB_OTHER_AFTER=3 gallery --no-open; local status=$?
    expect appears_before_boot "exits non-zero" [ "$status" != 0 ]
    expect appears_before_boot "no boot call" not_called "simctl boot"
    expect appears_before_boot "never shut anything down" not_called "simctl shutdown"
    expect appears_before_boot "no build started" not_called xcodebuild
}

appears_before_build() {   # appeared while ours became ready: the build does not start; ours goes down
    setup Shutdown
    STUB_OTHER_ON_BOOTSTATUS=1 gallery --no-open; local status=$?
    expect appears_before_build "exits non-zero" [ "$status" != 0 ]
    expect appears_before_build "no build started" not_called xcodebuild
    expect appears_before_build "never touched the other" not_called "88888888"
    expect appears_before_build "its own boot is shut down" called "simctl shutdown $UDID"
}

appears_before_test() {   # appeared during the build: the test does not start
    setup Booted boot-2
    STUB_OTHER_DURING_BUILD=1 gallery --no-open; local status=$?
    expect appears_before_test "exits non-zero" [ "$status" != 0 ]
    expect appears_before_test "the build ran" called "xcodebuild build-for-testing"
    expect appears_before_test "the test did not start" not_called "xcodebuild test-without-building"
}

# --- failure paths: non-zero, own boot shut down, marker gone, logs kept, no stub child alive ---

failed_run_expects() {   # $1 = case, $2 = status
    expect "$1" "exits non-zero" [ "$2" != 0 ]
    expect "$1" "own boot shut down" called "simctl shutdown $UDID"
    expect "$1" "marker gone" marker_absent
    expect "$1" "the log directory is kept" bash -c 'ls -d "$0"/xfractal-gallery.* >/dev/null 2>&1' "$T"
}
build_fails() { setup Shutdown; STUB_BUILD_FAIL=1 gallery --no-open; failed_run_expects build_fails $?
    expect build_fails "no test started" not_called "xcodebuild test-without-building"; }
test_fails() { setup Shutdown; STUB_TEST_MODE=fail gallery --no-open; failed_run_expects test_fails $?; }
import_fails() { setup Shutdown; STUB_TEST_MODE=noimport gallery --no-open; failed_run_expects import_fails $?
    expect import_fails "said the manifest is missing" grep -q "manifest.json" "$T/out.log"; }
check_fails() { setup Shutdown; STUB_TEST_MODE=badcheck gallery --no-open; failed_run_expects check_fails $?
    expect check_fails "said CHECK FAILED" grep -q "CHECK FAILED" "$T/out.log"; }
interrupted_readiness() { setup Shutdown; STUB_FAIL=bootstatus gallery --no-open; failed_run_expects interrupted_readiness $?
    expect interrupted_readiness "no build started" not_called xcodebuild; }

# --- signals: sent to the wrapper while a stub child blocks ---

signalled() {   # $1 = signal, $2 = phase (bootstatus|build|test)
    local sig="$1" phase="$2" want block pidfile name
    name="signalled_$(echo "$1" | tr A-Z a-z)_$2${3:+_ignoring_term}"
    case "$sig" in INT) want=130 ;; TERM) want=143 ;; HUP) want=129 ;; esac
    setup Shutdown
    pidfile="$T/xcb.pid"
    case "$phase" in bootstatus) block=STUB_BOOTSTATUS_BLOCK; pidfile="$T/boot.pid" ;; build) block=STUB_BUILD_BLOCK ;; test) block=STUB_TEST_BLOCK ;; esac
    # A background job of a non-interactive shell starts with SIGINT ignored: exec through python with the default
    # disposition, as a terminal's Ctrl-C would find it.
    env "$block=1" ${3:+STUB_IGNORE_TERM=1} python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])' \
        "$TREE/scripts/snapshot-gallery.sh" --no-open > "$T/out.log" 2>&1 &
    local pid=$! i
    for i in $(seq 1 100); do [ -s "$pidfile" ] && break; sleep 0.1; done
    kill -"$sig" "$pid"
    for i in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    expect "$name" "ended within 3 s of the signal (grace period 1 s)" bash -c '! kill -0 "$0" 2>/dev/null' "$pid"
    expect "$name" "the blocking child was killed and reaped" dead "$pidfile"
    kill -KILL "$pid" 2>/dev/null; [ -s "$pidfile" ] && kill -KILL "$(cat "$pidfile")" 2>/dev/null
    wait "$pid"; local status=$?
    expect "$name" "exits $want" [ "$status" = "$want" ]
    expect "$name" "the owned boot was shut down" called "simctl shutdown $UDID"
    expect "$name" "marker removed" marker_absent
}
# signalled_<signal>_<phase>: nine cases (each of INT, TERM, HUP during bootstatus, the build and the test)
signalled_int_bootstatus() { signalled INT bootstatus; }
signalled_int_build() { signalled INT build; }
signalled_int_test() { signalled INT test; }
signalled_term_bootstatus() { signalled TERM bootstatus; }
signalled_term_build() { signalled TERM build; }
signalled_term_test() { signalled TERM test; }
signalled_hup_bootstatus() { signalled HUP bootstatus; }
signalled_hup_build() { signalled HUP build; }
signalled_hup_test() { signalled HUP test; }
# A child that ignores TERM is killed after the grace period (XFRACTAL_SNAPSHOT_KILL_GRACE) and reaped, and the
# cleanup still reaches the simulator shutdown.
signalled_term_bootstatus_ignoring_term() { signalled TERM bootstatus ignore; }
signalled_term_build_ignoring_term() { signalled TERM build ignore; }
signalled_term_test_ignoring_term() { signalled TERM test ignore; }

lock_held() {
    setup Booted boot-2
    mkdir -p "$(dirname "$XFRACTAL_SNAPSHOT_LOCK")"
    /usr/bin/lockf -k "$XFRACTAL_SNAPSHOT_LOCK" sleep 5 &
    local holder=$!
    sleep 0.5
    XFRACTAL_SNAPSHOT_LOCK_WAIT=1 gallery --no-open; local status=$?
    kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
    expect lock_held "exits 75" [ "$status" = 75 ]
    expect lock_held "said it waits" grep -q "waiting for another gallery run" "$T/out.log"
    expect lock_held "said it still holds the lock" grep -q "still holds the lock" "$T/out.log"
    expect lock_held "touched nothing" not_called xcodebuild
}

failed_shutdown() {   # a failed shutdown keeps the marker and fails; the next --shutdown finishes the job
    setup Booted boot-2
    printf '%s\nlist:boot-2\n' "$UDID" > "$MARKER"
    STUB_FAIL=shutdown gallery --shutdown; local status=$?
    expect failed_shutdown "exits non-zero" [ "$status" != 0 ]
    expect failed_shutdown "marker kept" marker_exists
    gallery --shutdown; status=$?
    expect failed_shutdown "second --shutdown exits zero" [ "$status" = 0 ]
    expect failed_shutdown "second --shutdown removed the marker" marker_absent
}

failed_final_shutdown() {   # a run that reaches CHECK OK, then fails to shut down: non-zero, marker kept
    setup Shutdown
    STUB_FAIL=shutdown gallery --no-open; local status=$?
    expect failed_final_shutdown "reached CHECK OK" grep -q "CHECK OK" "$T/out.log"
    expect failed_final_shutdown "exits non-zero" [ "$status" != 0 ]
    expect failed_final_shutdown "marker kept" marker_exists
    expect failed_final_shutdown "says how to finish" grep -q -- "--shutdown" "$T/out.log"
}

generates_project() {   # a fresh worktree has no project: xcodegen runs first
    setup Shutdown
    rm -rf "$TREE/xFractal.xcodeproj"
    gallery --no-open; local status=$?
    expect generates_project "exits zero" [ "$status" = 0 ]
    expect generates_project "ran xcodegen before the build" bash -c 'grep -n "xcodegen\|xcodebuild" "$0" | head -1 | grep -q xcodegen' "$STUB_LOG"
    setup Shutdown
    rm -rf "$TREE/xFractal.xcodeproj"
    rm "$T/bin/xcodegen"
    PATH="$T/bin:/usr/bin:/bin" gallery --no-open; status=$?
    expect generates_project "without xcodegen: exits non-zero" [ "$status" != 0 ]
    expect generates_project "without xcodegen: says so" grep -q "xcodegen is not installed" "$T/out.log"
    expect generates_project "without xcodegen: no build" not_called xcodebuild
}

ALL="pending_marker interrupted_retry delayed_identity boot_not_booted fallback_identity identity_source_change
stale_marker borrowed borrowed_run owned no_create keep_booted owned_run failed_list_shutdown failed_list_run waits_for_other
appears_before_boot appears_before_build appears_before_test build_fails test_fails import_fails check_fails
interrupted_readiness signalled_int_bootstatus signalled_int_build signalled_int_test signalled_term_bootstatus signalled_term_build
signalled_term_test signalled_hup_bootstatus signalled_hup_build signalled_hup_test signalled_term_bootstatus_ignoring_term
signalled_term_build_ignoring_term signalled_term_test_ignoring_term lock_held failed_shutdown failed_final_shutdown generates_project"
for c in ${@:-$ALL}; do
    if declare -F "$c" > /dev/null; then "$c"; else echo "FAIL unknown case: $c"; FAILED=1; fi
done
[ "$FAILED" = 0 ] && echo "all lifecycle checks passed"
exit "$FAILED"
