#!/bin/bash
# Renders the Mac app's window for the Mac App Store screenshots (Tests/MacWindowSnapshotTests: the real ContentView in
# a window never on screen, drawn at 2x) and copies the PNGs into previews/mac/ (gitignored).
#
#   scripts/snapshot-mac.sh
#
# Needs a Retina display (the test fails by name on 1x). The test runs hosted by the sandboxed Mac app, whose container
# macOS keeps other processes out of: it prints each PNG as base64 lines, which this script decodes. The xcodebuild run
# is under `buildlock` when it is on PATH. No simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/.build/DerivedData"
OUT="$ROOT/previews/mac"
LOG="$(mktemp -t xfractal-mac-gallery)"
trap 'rm -f "$LOG"' EXIT

cd "$ROOT"
LOCK=(); command -v buildlock > /dev/null && LOCK=(buildlock --folder "$DD" --)
# TEST_RUNNER_<name> in xcodebuild's environment reaches the test process as <name>.
TEST_RUNNER_XFRACTAL_MAC_SNAPSHOT=1 "${LOCK[@]}" xcodebuild test -project xFractal.xcodeproj -scheme xFractal-MAS \
    -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" \
    -only-testing:xFractalTests/MacWindowSnapshotTests -parallel-testing-enabled NO > "$LOG" 2>&1 \
    || { grep -E "^mac-gallery: |error: |failed" "$LOG" | sed 's/^/  /' || true; echo "Mac snapshot test failed" >&2; exit 1; }

grep -E "^mac-gallery: " "$LOG" || true
mkdir -p "$OUT"
NAMES="$(awk '$1 == "mac-gallery-png" { print $2 }' "$LOG" | sort -u)"
[ -n "$NAMES" ] || { echo "the test printed no PNG" >&2; exit 1; }
for name in $NAMES; do
    awk -v n="$name" '$1 == "mac-gallery-png" && $2 == n { printf "%s", $3 }' "$LOG" | base64 -D > "$OUT/$name.png"
done
echo "wrote $(echo "$NAMES" | wc -l | tr -d ' ') window(s) into $OUT"
