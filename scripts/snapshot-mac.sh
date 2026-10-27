#!/bin/bash
# Renders the Mac app's window for the Mac App Store screenshots (Tests/MacWindowSnapshotTests: the real ContentView in
# a window never on screen, drawn at 2x) and copies the PNGs into previews/mac/ (gitignored).
#
#   scripts/snapshot-mac.sh [--lang en,fr,de,it,es,pt-BR,ja,tr]
#
# --lang  the languages to render, one test run each: English into previews/mac/, another language into
#         previews/mac/<lang>/ (the app's own text in that language)
#
# Needs a Retina display (the test fails by name on 1x). The test runs hosted by the sandboxed Mac app, whose container
# macOS keeps other processes out of: it prints each PNG as base64 lines, which this script decodes. The xcodebuild run
# is under `buildlock` when it is on PATH: the DerivedData lock (with a build slot) inside a second lock, without a
# slot, on the app's container, so two worktrees never run the hosted app at once. The Mac stays awake for the run
# (`caffeinate -dims`). No simulator.
set -euo pipefail

if command -v caffeinate > /dev/null; then caffeinate -dims -w $$ > /dev/null 2>&1 & fi

LANGS=(en)
while [ $# -gt 0 ]; do
    case "$1" in
        --lang)
            IFS=',' read -r -a LANGS <<< "${2:?--lang needs a list such as en,fr}"
            for l in "${LANGS[@]}"; do
                case "$l" in en|fr|de|it|es|pt-BR|ja|tr) ;; *) echo "--lang is en, fr, de, it, es, pt-BR, ja or tr (got '$l')" >&2; exit 2 ;; esac
            done
            shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/.build/DerivedData"
LOG="$(mktemp -t xfractal-mac-gallery)"
trap 'rm -f "$LOG"' EXIT

cd "$ROOT"
CONTAINER="$HOME/Library/Containers/ch.arizonasoftware.xfractal"
LOCK=(); command -v buildlock > /dev/null && LOCK=(buildlock --folder "$CONTAINER" --no-slot -- buildlock --folder "$DD" --)
for lang in "${LANGS[@]}"; do
    OUT="$ROOT/previews/mac"; [ "$lang" = en ] || OUT="$OUT/$lang"
    case "$lang" in en) region=US ;; ja) region=JP ;; *-*) region="${lang#*-}" ;; *) region="$(echo "$lang" | tr a-z A-Z)" ;; esac
    # TEST_RUNNER_<name> in xcodebuild's environment reaches the test process as <name>.
    TEST_RUNNER_XFRACTAL_MAC_SNAPSHOT=1 "${LOCK[@]}" xcodebuild test -project xFractal.xcodeproj -scheme xFractal-MAS \
        -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" \
        -only-testing:xFractalTests/MacWindowSnapshotTests -parallel-testing-enabled NO \
        -testLanguage "$lang" -testRegion "$region" > "$LOG" 2>&1 \
        || { grep -E "^mac-gallery: |error: |failed" "$LOG" | sed 's/^/  /' || true; echo "Mac snapshot test failed [$lang]" >&2; exit 1; }

    grep -E "^mac-gallery: " "$LOG" | sed "s/^/[$lang] /" || true
    mkdir -p "$OUT"
    NAMES="$(awk '$1 == "mac-gallery-png" { print $2 }' "$LOG" | sort -u)"
    [ -n "$NAMES" ] || { echo "the test printed no PNG [$lang]" >&2; exit 1; }
    for name in $NAMES; do
        awk -v n="$name" '$1 == "mac-gallery-png" && $2 == n { printf "%s", $3 }' "$LOG" | base64 -D > "$OUT/$name.png"
    done
    echo "[$lang] wrote $(echo "$NAMES" | wc -l | tr -d ' ') window(s) into $OUT"
done
