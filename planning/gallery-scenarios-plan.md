# Preview gallery: the iOS screen states as scenarios, no `#Preview`

Status: Implemented on main 2026-10-16.

Revision 3 (2026-10-15), the last plan round. Branch `gallery-scenarios`, cut from `gallery-spike` (923a205). Evidence for the capture
method: `planning/gallery-capture-spike.md` and `GalleryTests/CaptureSpikeTests.swift`.

## Revision history

- **Revision 3** (2026-10-15), plan review round 2 (1 blocker, 7 should-fix, all accepted):
  - Journal (blocker): loading the journal first would still replace its last snapshot (`journalStart` makes the
    state's timestamp coalesce with it). The fix is now **no recording during hydration**; the red test seeds a
    non-default state and asserts exact preservation after the debounce and after an immediate background flush.
  - Captured content is validated against the expected fixture: a reference render of the scenario's state through
    the same renderer, compared with the captured fractal region; the observed frame's state must equal the
    expected one; a stale-frame negative test. Replay stability is bounded (capture within 10 s of `replay()`,
    the snap lasts 15 s) and asserted on the observed frame.
  - Calibration: an explicit measurement mode (`--measure`) collects every board pair and every sheet pair before
    any peek or sheet threshold is enforced; fixed floors reject non-positive separation and inadequate coverage
    instead of deriving a passing threshold from whatever was measured.
  - Region validation: finite, positive, image-contained regions with equal geometry across a pair, with tests;
    the capsule measurement reports component coverage, bounds, component count and surrounding differences for
    inspection before it is enforced.
  - Scroll: the vertical form is chosen by vertical scrollable extent with adjusted insets, and the presets and the
    journal actions are verified visible; horizontally hidden presets are an explicit exclusion.
  - SwiftUI's size class is asserted inside the presented sheet too, through a nil-by-default probe slot.
  - Step 1 defines every builder (fixtures) and renders three; the tests that mount other scenarios use the fixtures.
  - The privacy inventory covers unstaged and untracked files, generated artifacts and image metadata.
- **Revision 2** (2026-10-15), plan review round 1 (2 blockers, 10 should-fix, 4 simpler, 1 already-exists, all
  accepted):
  - Readiness is frame-specific: a renderer frame observer proves that the explicit draw submitted a command
    buffer, that the buffer completed without error and that its drawable was presented, each with a bounded wait.
    The image check stays as a separate safeguard (blocker 1).
  - The peek check measures the capsule from the light/dark difference mask and validates that the fractal pixels
    around it are identical; thresholds are calibrated over every board fixture in step 2, provisional in step 1.
    The sheet check requires background coverage inside an inset region of the measured sheet frame (blocker 2).
  - Inventory 15 → 17: controls with an empty journal, controls while replaying, the Julia sheet scrolled to its
    end; exclusions listed explicitly (picker menus, gestures, landscape, Dynamic Type).
  - The scene-phase cause is stated as a likely cause, not proven; its test covers the first render, repeated
    updates and a replay.
  - Detents: the sheet's own presentation controller, its detents verified, settled geometry awaited; minimal detent
    support moves into step 1 (scenario 11 needs it). Zero redraws is now a gate, not a target.
  - The iPad group is renamed "Regular width (approximation)", with asserted UIKit and SwiftUI traits; it is not
    iPad coverage.
  - A separate red-first test for the journal-persistence hazard in `StateStore.load()` (a production bug), and a
    hosted identity test for the lazy `ContentView` seam.
  - Lifecycle: every background child (readiness and `xcodebuild`) is tracked, stopped and reaped; signals are
    forwarded through `lockf`; failure-path tests for build, test, import and check.
  - A public privacy check over every file the branch adds or changes, staged content included.
  - Simpler: no preference restore and no build-lock wrapper (no longer open decisions); red proofs are tests
    written before the code or mutation checks on a temporary copy, never commit-and-revert; the script source is
    fixed (Design 3).
  - Already-exists: the spike's target, scheme wiring, injected defaults and clock and `StateStoreTests`' persistence
    tests are extended, not reinstalled.
  - The plan and the spike note move from `docs/` (served by GitHub Pages) to `planning/`, which is not published.
    Jean can reverse that.
- **Revision 1** (2026-10-15): first draft.

Decisions already made (not re-asked): the scenario list in the test target is the only source, no `#Preview`;
`.claude/skills/preview-gallery` is installed (privacy-checked, this repo is public) and reached by Codex through
the existing `.agents/skills -> ../.claude/skills` symlink; the Mac app is out of scope (below, "Mac").

Languages the app ships: **English only.** `xFractal/Info-iOS.plist` has `CFBundleDevelopmentRegion` `en`, and
`xFractal/` holds no `.xcstrings`, `.strings` or `.lproj` (the localisations under `Frameworks/Sparkle.framework`
belong to Sparkle, which is macOS only). One pass, `-testLanguage en`. The page script keeps its per-language
layout (below), so a second language is one more test run later, not a redesign.

## Problem with evidence

- xFractal has no `#Preview` and no way to look at its iOS screens without running the app by hand. There is
  nothing to delete: the conversion is "add the gallery", not "replace previews".
- The app is one screen and one sheet (`xFractal/ContentView.swift`): the Metal board (`FractalView`, lines 26-30),
  the bottom peek capsule (`iOSPeek`, 328-372) and the controls sheet (`iOSControlsSheet`, 374-452, detents
  `.height(260)`, `.medium`, `.large`, line 47) with a type-specific section (`iOSTypeSpecificSection`, 455-520).
  Its states come from `StateStore` (`xFractal/FractalState.swift:137`): the `ViewState`, the journal and
  `isReplaying`.
- The spike proved a capture (GO, 32 good captures in two runs) with two weaknesses:
  1. **Fixed sleeps** (600 + 300 + 100 ms per capture, `CaptureSpikeTests.swift:28-33`), 1.0 s of its 1.2 s.
  2. **One blank fractal** before the explicit `draw()` was added. Likely cause, from reading the code (not
     proven): in a test window `scenePhase` is `.background`, so `FractalView` makes the view paused
     (`FractalView.swift:51`); a view unpaused from outside is paused again, with its drawables released, by the
     next SwiftUI update (`FractalView.swift:84-89`: `isPaused == isActive` is `false == false`), and the sheet
     presentation is such an update. Once paused, later updates leave it alone. The app treats `.inactive` as
     active too (`isActive: scenePhase != .background`, `ContentView.swift:27`).
- The reference check judges the mean luminance of the whole image. Here the fractal fills most of the frame
  and is legitimately bright or dark in both appearances, so a whole-image check would fail correct renders and
  pass a blank one.
- **The spike's seam constructs a store on every init**: `init(store: StateStore = StateStore(), …)` with
  `_store = StateObject(wrappedValue: store)` (`ContentView.swift:13-14`) evaluates `StateStore()` each time
  `ContentView` is initialised, not once like the original `@StateObject private var store = StateStore()`.
- **A journal-persistence hazard in production** (`FractalState.swift:165-176`, found while tracing the seam):
  `load()` assigns `state` *before* it loads the journal. The assignment fires `didSet` → `recordSnapshot()`
  while `journal` is still empty, so `journal` becomes `[state]` and a journal save of `[state]` is scheduled
  (`saveJournalDebounced`, 0.5 s, lines 229-240). The persisted journal is then assigned in memory, but the
  scheduled save still writes `[state]` over it, as does `enterBackground()` (which performs pending saves).
  Expected effect: a relaunch that changes nothing truncates the saved journal to one entry. Loading the journal
  first is not enough: `load()` then sets `journalStart` so the journal's last entry is "now"
  (`FractalState.swift:174`), and a persisted state that differs from that entry is recorded at the same instant,
  which `journal(byApplying:)` coalesces into a **replacement** of the last snapshot (lines 205-206). The red test
  below decides it; if it passes, the hazard is not real and the fix is dropped.

## Design

### 1. Test target and harness (`GalleryTests/`, iOS, hosted by the app)

Extended from the spike, not reinstalled: the `xFractalGalleryTests` target in `project.yml` (iOS unit tests,
`TEST_HOST` = the iOS app, in the `xFractal-iOS` scheme's test action), the `ContentView.init(store:showingSheet:)`
seam, `StateStore(defaults:now:)` and the method (a `UIWindow` on the app's scene, the `MTKView` drawn,
`window.drawHierarchy(in:afterScreenUpdates: true)` at 2x). XCTest, as in `Tests/`.

Files:

- `GalleryTests/GalleryFixtures.swift`: every scenario's seeded state, journal, sheet, scroll and size, defined once
  (all 17 from step 1).
- `GalleryTests/GalleryScenarios.swift`: `GalleryScenario` (name, group, size, sheet, regions, builder from a
  fixture) and the rendered list.
- `GalleryTests/SnapshotGalleryTests.swift`: the render test, skipped (`XCTSkip`) unless `XFRACTAL_SNAPSHOT_DIR`
  is set; filters by `XFRACTAL_SNAPSHOT_ONLY` (comma-separated substrings of names or slugs); writes
  `<slug>.png`, `<slug>.dark.png` and `manifest.json` (every scenario, filtered or not).
- `GalleryTests/GalleryScenarioTests.swift`: plain tests, never skipped (Test plan).
- `GalleryTests/CaptureSpikeTests.swift`: **deleted in step 1.** Its capture code is folded into
  `SnapshotGalleryTests` (hosting, the `MTKView` search, `drawHierarchy` at 2x); its sleeps, its `SPIKE_DIR`
  and its hard-coded 393 x 852 size are not kept. `planning/gallery-capture-spike.md` stays as the evidence.

**The lazy seam.** `init(store: @autoclosure @escaping () -> StateStore = StateStore(), showingSheet: Bool = false)`
with `_store = StateObject(wrappedValue: store())`: `StateObject(wrappedValue:)` takes its own autoclosure, so the
store is built once per view identity, as before the spike. `xFractalApp.swift:21` still calls `ContentView()`.

**The journal fix** (only if its red test fails): **no recording during hydration.** `load()` sets a private
`isHydrating` flag around its two assignments; `onStateChanged` returns at once while it is set, so loading neither
records a snapshot nor schedules a save. The loaded state and journal are what was persisted, so nothing needs
saving. Preservation policy: after a load, the persisted journal and state are byte-for-byte what they were until
the user changes something. Pure `StateStore` logic, tested in `Tests/StateStoreTests.swift` next to the existing
persistence tests.

**Builder: fresh per appearance.** The test calls the scenario's builder once per appearance; each call makes a
new `UserDefaults` suite named `gallery.<slug>.<light|dark>` (its persistent domain removed first), seeds it, and
returns a new `StateStore(defaults: suite, now: { fixedDate })` and a new `ContentView`. Nothing is shared between
the two renders of a scenario or between scenarios. Teardown per render: `store.enterBackground()` (stops a
replay, flushes and cancels the debounced saves, `FractalState.swift:322-330`), `removePersistentDomain`, then
`window.isHidden = true; window.rootViewController = nil`.

**Production read path for every scenario.** The builder writes the scenario's `ViewState` and journal
(`[Snapshot]`) with `JSONEncoder` under `StateStore.stateKey` and `StateStore.journalKey`, the encoding of the
production save (`FractalState.swift:221-222, 234-235`). `StateStore.init` reads them through `load()`
(`FractalState.swift:165-176`), as on a relaunch; from there everything is production code: `ContentView` →
`FractalView(state:)` (`ContentView.swift:26`) → `FractalRenderer.state` (`FractalView.swift:83`) → the uniforms in
`draw(in:)` (`FractalRenderer.swift:128-165`); the peek reads `state.type.label`, `maxIterations`, `journal.count`
and `isReplaying` (`ContentView.swift:334-366`); the sheet reads the same store (374-520). No scenario sets
`store.state` after construction; the replay scenarios call the production `store.replay()`.

**Fixed parameters.** Every `ViewState` is written out in the scenario (values below), the clock is fixed
(`now: { Date(timeIntervalSince1970: 1_800_000_000) }`), the phone size is read from the simulator's screen
(`UIScreen` bounds of the iPhone 17 Pro agent, 402 x 874 pt, not the spike's 393 x 852), the regular-width size is
fixed (834 x 1210 pt), the scale is 2. The host app's own window also runs a `ContentView` on
`UserDefaults.standard`; the test pauses that `MTKView` once at start so it does not compete for the GPU (nothing
the scenarios read).

**Scene phase (no app change).** The harness hosts `ContentView(…).environment(\.scenePhase, .active)`.
`ContentView` reads `scenePhase` from its environment (`ContentView.swift:6, 27`), so `isActive` is true: the
`MTKView` is made running and no update pauses it. This is the real app's foreground state, not a forced appearance
or language. Whether the old conflict caused the spike's blank is not claimed; the test covers the first render,
repeated updates and a replay. Fallback if the override does not reach `ContentView`: an `isActive` seam in
`ContentView.init` (default: follow `scenePhase`), with the same test.

**Readiness: frame-specific evidence, bounded waits.** `FractalRenderer` gets one optional hook, nil in the app:
`var frameObserver: ((MTLCommandBuffer, MTLDrawable, ViewState) -> Void)?`, called in `draw(in:)` right before
`cmd.present(drawable)` / `cmd.commit()` (`FractalRenderer.swift:164-165`) with the state the frame encoded. And one
extraction, behaviour-preserving: the encoding part of `draw(in:)` (lines 134-163) becomes
`encodeFrame(state:aspect:into:commandBuffer:)`, which `draw(in:)` calls with its drawable's pass and which the
harness calls with an offscreen texture for the reference render. Both are Metal glue, exempt from TDD by AGENTS.md;
the readiness tests below cover them. Per render, after `makeKeyAndVisible()`:

1. **Layout settled** (poll every 16 ms, 5 s bound): the `MTKView` is in the window with non-empty bounds and
   `drawableSize == bounds.size * contentScaleFactor`; for a sheet scenario, `presentedViewController` exists,
   `isBeingPresented == false`, `transitionCoordinator == nil`, the requested detent is selected (below) and the
   presented view's frame is equal on three consecutive polls.
2. **Our frame.** The harness arms the observer, calls `mtk.draw()` (synchronous: `draw(in:)` runs inside the
   call) and disarms it. The observer, while armed, captures that frame's command buffer and drawable and
   registers `addCompletedHandler` and `addPresentedHandler`, and records the encoded state, which must equal the
   scenario's expected state (snapshot A for a replay). No callback during the call means `draw(in:)`
   returned without submitting (no drawable or pass descriptor): wait one 16 ms tick and try again, at most 3
   times, then fail the render with "no frame submitted".
3. **Completed and presented** (2 s bound each): the completed handler reports `status == .completed` and
   `error == nil`; the presented handler reports `presentedTime > 0`. A timeout or an error fails the render with
   its reason.
4. **Capture**, then **content validation against the expected fixture**. Presentation proves the drawable was
   displayed, not that `drawHierarchy` returned its pixels, so the captured fractal region is compared with a
   **reference render**: the harness encodes the scenario's expected state with `encodeFrame` into an offscreen
   texture of the view's drawable size and pixel format (a fresh command buffer, waited on), reads it back, and
   compares the same region, both reduced to 64 x 64 luminance. Rule: Pearson correlation >= 0.95 (a sheet's
   dimming is a linear blend and keeps the correlation); for a region whose reference has standard deviation under
   0.02, mean absolute difference <= 0.03 instead. A blank, stale or different fractal fails it. A failed
   comparison after a presented frame is a redraw from step 2, at most 2, each printed; still failing fails the
   render. Thresholds are checked in step 1 against the measured values and recorded.

Each render prints `gallery: <slug> <light|dark> ready <ms> submits <n> redraws <n> total <ms>`; the gates
record min, median and max of `ready` (the measured settle). There is no `settle` field and no sleep. The view
keeps running at 60 Hz meanwhile; for a fixed state every frame is the same. **Replay is bounded:** the replay
scenarios (7, 15) record the time of `store.replay()` and fail the render if the capture ends more than 10 s later
(the snap to snapshot A holds for 15 s), and the observed frame's state must be A.

**Detents (in step 1).** SwiftUI presents the sheet through a `UISheetPresentationController`, reached as
`host.presentedViewController?.sheetPresentationController` (public API, no hierarchy walk). For a medium or large
scenario the harness verifies that `detents` holds three entries including the system `.medium` and `.large`
identifiers, sets `selectedDetentIdentifier` inside `animateChanges`, then waits for readiness step 1 (identifier
equal *and* the frame stable, since the identifier changes before the animation ends). The opening-detent
scenario touches nothing and records the identifier and height SwiftUI opened at. Fallback, if SwiftUI resets the
selection or the detents are not the expected ones: a `ContentView` seam
`presentationDetents(_, selection: $sheetDetent)` whose `@State` resets to the current opening detent on dismiss,
so the app still opens the sheet as today.

**Regular width (approximation).** Two scenarios run on the same iPhone simulator in an 834 x 1210 window with
`host.traitOverrides.horizontalSizeClass = .regular`. The test asserts the effective traits: the hosting
controller's and the presented sheet controller's `traitCollection.horizontalSizeClass == .regular`, and SwiftUI's
`horizontalSizeClass` read twice: by a probe view the harness wraps around `ContentView`, and **inside the
presented sheet** by a probe placed through a nil-by-default slot, `ContentView(…, sheetProbe: AnyView? = nil)`,
drawn as a zero-size `.background` of `iOSControlsSheet` (iOS only; the app passes nothing). Idiom, safe areas and
presentation adaptation stay the phone's: these cards are **not iPad coverage** and the skill says so. A real iPad
pass is an iPad simulator run after the iPhone one, later if wanted.

**Scroll position.** The "bottom" scenario scrolls the sheet's form to its end. The form is chosen among the
presented view's `UIScrollView`s as the one with the largest vertical scrollable extent
(`contentSize.height + adjustedContentInset.top + adjustedContentInset.bottom - bounds.height > 0`, and not wider
than its bounds), which excludes the horizontal presets scroll view. The harness sets `contentOffset.y` to
`contentSize.height + adjustedContentInset.bottom - bounds.height`, waits for readiness step 1, asserts the offset
holds within 1 pt, and verifies visibility: the accessibility elements labelled "Rabbit" (a preset) and "Clear
Journal" have frames inside the sheet's visible frame. If SwiftUI's accessibility tree is not reachable from the
test, the render fails with that reason (and the fallback is decided then, not silently skipped). Presets beyond the
horizontal scroll's visible width ("Galaxy", "San Marco" on a phone) are not captured: an explicit exclusion.

### 2. The luminance check judges the UI regions only

Whole-image luminance is not judged. Each scenario declares its regions; the test **measures** them at render
time and writes them per image into the manifest (`regions` per slug and appearance, in points). **Region
validation** (always enforced): every coordinate finite, width and height positive, the region inside the image
bounds (points times the image's scale), and the light and dark regions of a pair equal within 1 pt; anything else
is a check failure, never a skipped region. A scenario not
rendered by an `--only` run keeps its last measured regions: the partial import merges the manifest entries of the
rendered slugs into the existing manifest instead of replacing it.

| kind | measured how | rule |
|---|---|---|
| `sheet` | the presented sheet view's frame in window coordinates, inset 16 pt on every side and below its navigation bar (no rounded corners, no grabber); for the opening and medium detents the visible part only | **coverage**: in light, at least 60 % of the region's pixels have luminance >= 0.85; in dark, at least 60 % have luminance <= 0.20 (the grouped background; text, separators and controls are the rest) |
| `peek` | the capsule found in the pair's **difference mask**: inside the bottom 140 pt band, the pixels where light and dark differ by more than 0.04; the bounding box of the largest connected blob | the box exists and is capsule-sized (120-380 pt wide, 28-60 pt high, centred within 40 pt); light mean - dark mean inside the box >= `PEEK_DELTA`; **outside** the box, within the band, at most 0.5 % of pixels differ (the fractal behind is the same in both, which validates the deterministic-render assumption on every board) |
| `fractal` | the board area no UI covers: below the top safe area, above the peek band or the sheet; none at the large detent | standard deviation >= 0.02 and 0.02 < mean < 0.98 in both images: drawn, not blank white, not blank black |

**Measurement before enforcement.** `preview-gallery.py --check --measure` enforces everything except the `peek`
and `sheet` thresholds, and prints and writes (`previews/calibration.json`, gitignored with `previews/`) per pair:
for a peek, the light-dark difference inside the box, the box bounds, the component count in the band, the share of
the box the largest component covers, and the differing share outside it; for a sheet, the coverage in each
appearance. Step 1 runs only in measure mode for those two kinds. Step 2 renders all 17, runs measure mode over
**every board pair** (scenarios 1-7 and 16, the peek) and **every sheet pair** (8-15 and 17, the coverage), the
numbers and the images are inspected, then the thresholds are set and enforced:

- `PEEK_DELTA` = half the smallest measured light-dark difference, but never below the floor **0.03**; a
  non-positive or sub-floor separation on any board is a finding (the capsule is not distinguishable), never a
  reason to lower the floor. The same for the capsule's component coverage (floor 70 % of the box), the box size
  band above, and the outside-difference share (ceiling 0.5 %).
- Sheet coverage threshold = halfway between 0 and the smallest measured coverage, never below the floor **50 %**;
  a sheet below the floor is a finding.

The thresholds and the measured table are recorded in this plan and in the script, and the step 2 gate fails if
any fixture falls outside them. Kept from the reference check: a scenario missing an image, a stray PNG,
a duplicate slug, a dark image byte-identical to its light one, an undecodable image.

`scripts/preview-luminance.swift` changes from "mean of each PNG" to jobs on stdin: `(mode, file, [file2], x, y, w,
h)` with modes `stats` (mean, standard deviation, share of pixels above/below a cut) and `diff` (the difference
mask's largest blob and the outside-blob share); `-1` when an image cannot be decoded.
`scripts/preview-gallery.py --check` builds the jobs from the manifest.

### 3. Scripts

Sources, fixed: the page script, the luminance helper, their contract tests and the lifecycle script with its
stubbed tests are copied from the reference conversion's scripts, with the backgrounded readiness, signal
forwarding and child handling of a second conversion. Both are private repositories; the parent session gives the
implementer their exact paths and commits, and they are not named in this public repo. Copied files are edited for
xFractal, never rewritten, and every copied file passes the privacy check (Gates) before it is committed.

- `scripts/preview-gallery.py`: `--import DIR [--partial] [--lang L]`. English lives in `previews/`, another
  language in `previews/<lang>/`; an import deletes only its own language's top-level PNGs, manifest and page,
  **never another language's folder**; `--partial` replaces only the files of an `--only` run and merges their
  manifest entries. `--check` **rebuilds the page first** from the PNGs on disk, then judges every scenario of the
  manifest. `--coverage`: view types in `xFractal/` no scenario names (expect `ContentView`, `FractalView`).
- `previews/` added to `.gitignore` (the spike worktree already holds an untracked `previews/`).

`scripts/snapshot-gallery.sh [--only P] [--keep-booted] [--no-open] | --shutdown` owns the **xFractal Agent**
simulator the spike created (iPhone 17 Pro, iOS 27.0, found by name, created if missing), DerivedData
`${XFRACTAL_SNAPSHOT_DD:-~/Library/Developer/Xcode/DerivedData/xFractal-snapshots}`, marker
`${TMPDIR}/xfractal-snapshot-gallery.booted`. The lifecycle:

1. **A failed `simctl list` fails the run**, never read as "no simulator" or "not booted": every query is
   checked, including the first name lookup. In `--shutdown` the marker stays.
2. **Ownership marker:** `pending` written the moment `simctl boot` returns 0, then the identity with its source
   (`proc`: the launchd_sim start time; `json`: `lastBootedAt`), compared only within the recorded source. A boot
   that cannot be identified is shut down and fails the run; a pending marker is shut down even with
   `--keep-booted`. A stale marker (another boot) is dropped; an unreadable one is kept. An "xFractal Agent" booted
   by someone else is borrowed and left running.
3. **`lockf`:** one gallery run at a time across the main checkout and its worktrees, lock in the main checkout's
   `.build/snapshot-gallery.lock` (`.build/` is gitignored); a second run waits up to 10 minutes, then exits 75
   with a message. The locked run is a background child of the wrapper, which forwards INT, TERM and HUP to it
   (lockf does not) and exits 130, 143 or 129 once the child's cleanup has finished.
4. **Children tracked and reaped:** `simctl bootstatus` and every `xcodebuild` run through one helper that starts
   the command in the background, records its pid in `CHILD`, and `wait`s (bash defers a trap until a foreground
   child exits). The `EXIT` cleanup kills `CHILD` if set, `wait`s for it, then shuts down its own boot; it never
   signals a process it did not start. INT, TERM and HUP exit 130, 143 and 129 through that cleanup.
5. **Re-check before every boot, build and test:** right before `simctl boot`, `build-for-testing` and
   `test-without-building`, any other booted simulator fails the run. Before the first one, the script waits (up
   to 10 minutes) for another simulator to go away, as the global rule asks. Limits, stated in the skill: the
   gallery lock serialises gallery runs only; another session's `xcodebuild` of xFractal is not serialised with it
   (it uses its own DerivedData, so they do not share build products), and a simulator booted after the last
   re-check is noticed only by the next run.
6. **No preference is changed**, so nothing is restored: xFractal shows no time, date or locale-formatted value
   (`String(format: "%.4f")` and integer interpolations only).
7. **A shutdown failure propagates:** a failed final shutdown keeps the marker, prints how to finish
   (`--shutdown`), and makes the run exit non-zero even after `CHECK OK`.
8. **The project is generated** when `xFractal.xcodeproj` is missing or older than `project.yml` (a fresh worktree
   has none): `xcodegen generate` first, a clear message if XcodeGen is missing. No Swift packages, so no
   package-resolution flags.
9. `build-for-testing` once, then one `test-without-building -only-testing:xFractalGalleryTests
   -parallel-testing-enabled NO -enableCodeCoverage NO -testLanguage en -testRegion US`, with
   `TEST_RUNNER_XFRACTAL_SNAPSHOT_DIR` / `TEST_RUNNER_XFRACTAL_SNAPSHOT_ONLY` in xcodebuild's environment. The
   whole target runs, so the plain scenario tests gate every render. Then import, `--check`, open the page,
   print `timings: boot, build, test, total`, the readiness summary and `network: none` (the iOS app has no
   network client; Sparkle is macOS only).

`scripts/test_snapshot_gallery.sh` puts a stub `xcrun`, `xcodebuild` and `xcodegen` first on `PATH`, answering from
a state file; no real simulator is touched. `SNAPSHOT_GALLERY_SCRIPT` selects the script under test (default: the
real one), for the mutation checks. Cases:

- ownership: `pending_marker`, `interrupted_retry` (TERM while the identity is pending), `stale_marker`, `borrowed`,
  `borrowed_run`, `owned`, `no_create`, `fallback_identity`, `missing_identity`, `identity_source_change`,
  `delayed_identity`, `boot_not_booted`, `keep_booted`;
- queries and other simulators: `failed_list_shutdown`, `failed_list_run`, `waits_for_other`,
  `appears_before_boot`, `appears_before_build`, `appears_before_test`;
- failure paths (each: exit non-zero, own boot shut down, marker gone, logs kept, no stub child alive):
  `build_fails`, `test_fails`, `import_fails`, `check_fails`, `interrupted_readiness` (bootstatus fails);
- signals (each of INT, TERM, HUP, sent to the wrapper, during `bootstatus`, the build and the test: the expected
  exit status within 3 s, the blocking stub child killed and reaped, own boot shut down, marker gone):
  `signalled_<signal>_<phase>`, nine cases;
- `lock_held` (the message, then exit 75 with `XFRACTAL_SNAPSHOT_LOCK_WAIT` shortened), `failed_shutdown`
  (`--shutdown`), `failed_final_shutdown` (a run that reaches `CHECK OK`, then fails its shutdown: exit non-zero,
  marker kept), `generates_project`.

**Red proofs without commits.** Tests written for new code are run and seen red before the code exists. For the
copied lifecycle script, whose guards arrive together, each guard gets a **mutation check**: copy the script to a
scratch directory, remove the guard in the copy, run `SNAPSHOT_GALLERY_SCRIPT=<copy> scripts/test_snapshot_gallery.sh`
and see the named case fail; the working tree is never edited for it. Mutations: the `pending` write
(`interrupted_retry`), backgrounding `bootstatus` (`signalled_term_bootstatus`), the child kill and reap
(`signalled_term_test`), the signal forwarding (`signalled_int_build`), the list-failure check (`failed_list_run`),
each re-check (`appears_before_boot`, `appears_before_build`, `appears_before_test`), the shutdown status in the
cleanup (`failed_final_shutdown`), the lock (`lock_held`). Same method for the Swift guards that are not new tests'
subjects (the `.active` environment line, the lazy seam): a scratch copy of the file is not possible inside the
build, so those are proven by tests written before the code (Test plan).

### 4. Skill and working agreement (step 3)

`.claude/skills/preview-gallery/SKILL.md`: the reference skill with xFractal's repo-specific blocks (project
`xFractal.xcodeproj` generated by XcodeGen, scheme `xFractal-iOS`, target `xFractalGalleryTests`, the files above,
output `previews/`, groups Board / Controls / Regular width (approximation); platforms: iPhone, English only,
regular width approximated, no iPad and no Mac coverage; status: adopted, there never were `#Preview`s; script
facts and their limits; extras: the Metal readiness, the region check and its calibration table). `AGENTS.md` gets
a "Preview gallery" section: no `#Preview`, every screen state needs a scenario, the command, the simulator, and
that `GalleryTests/` is the iOS test target (the TDD section's `Tests/` stays the macOS logic tests). The parent
session registers the skill in its repo index (not in this repo).

## Scenario inventory (17)

Phone = the simulator screen (402 x 874 pt); RW = 834 x 1210 pt, regular width (approximation). Journal "[s]": one
snapshot of the state at time 0 (Replay disabled, Clear Journal enabled); "A→B": two snapshots, A at 0 s and B at
30 s, B the current state, palettes chromatic → cold; "empty": nothing seeded (`ViewState.defaultState`, journal
empty, both journal actions disabled). All read paths: suite → `StateStore.load()` → `ContentView` →
`FractalView` / peek / sheet. Regions: P = peek, F = fractal, S = sheet.

| # | Name | Group | Size | Seeded state | Sheet | Regions | Shows |
|---|---|---|---|---|---|---|---|
| 1 | Board · Mandelbrot · First launch | Board | phone | empty | none | P, F | peek "Mandelbrot · 512", Replay disabled |
| 2 | Board · Julia | Board | phone | Julia defaults, c = Rabbit (-0.123, 0.745), palette cold; [s] | none | P, F | |
| 3 | Board · Newton | Board | phone | Newton defaults (64 iterations, z³ − 1, smooth off); [s] | none | P, F | |
| 4 | Board · Multibrot | Board | phone | Multibrot defaults, exponent 5, palette hot; [s] | none | P, F | |
| 5 | Board · Mandelbrot · Deep zoom | Board | phone | Mandelbrot, centre (-0.743643887037151, 0.131825904205330), scale 1e-10, 2048 iterations, perturbation on, palette gray; [s] | none | P, F | the perturbation path (`ensureOrbit`) |
| 6 | Board · Replay ready | Board | phone | Mandelbrot defaults; A→B | none | P, F | Replay enabled |
| 7 | Board · Replaying | Board | phone | as 6, then `store.replay()` | none | P, F | stop icon; the state is A for 15 s (palettes differ, so `ViewState.interpolate` snaps while t < 0.5, `FractalState.swift:102-105`) |
| 8 | Controls · Mandelbrot · Opening detent | Controls | phone | Mandelbrot defaults; [s] | opening, untouched | S, F | the first view of the sheet; records its detent |
| 9 | Controls · Mandelbrot · Medium | Controls | phone | as 8 | `.medium` | S, F | Appearance section, Perturbation toggle |
| 10 | Controls · Mandelbrot · Large · First launch | Controls | phone | empty | `.large` | S | every section; Replay and Clear Journal disabled |
| 11 | Controls · Julia · Large | Controls | phone | Julia, c = Rabbit; A→B | `.large` | S | Julia c section, presets; Replay enabled (as far as fits) |
| 12 | Controls · Julia · Large · Bottom | Controls | phone | as 11 | `.large`, scrolled to the end | S | the presets and the journal actions together |
| 13 | Controls · Newton · Large | Controls | phone | Newton, z⁸ + 15z⁴ − 16 (flavor 2); [s] | `.large` | S | the polynomial picker row |
| 14 | Controls · Multibrot · Large | Controls | phone | Multibrot, exponent 5; [s] | `.large` | S | "n = 5" |
| 15 | Controls · Replaying | Controls | phone | as 7 (replay started), sheet reopened | `.large` | S | "Stop Replay", Clear Journal disabled (reachable: reopening Controls during a replay) |
| 16 | Regular width · Board · Julia | Regular width (approximation) | RW | as 2 | none | P, F | |
| 17 | Regular width · Controls · Mandelbrot | Regular width (approximation) | RW | as 8 | as presented in regular width | S, F | |

Excluded, by design (said in the skill): the Julia presets beyond the horizontal scroll's visible width, open picker menus (Type, Palette, Polynomial: system menus, not app
layout), gestures in progress (drag, pinch, slider drags), the Done and Reset actions' results (they are other
listed states), landscape (the window keeps the simulator's portrait orientation; a rotated simulator pass later if
wanted), Dynamic Type variants (an optional pass), real iPad idiom and multitasking sizes, and the macOS HUD and
parameter panel (`ContentView.swift:117-243`).

## Mac

Out of scope, and not trivially the same: the Mac UI is a different view tree (the HUD and the parameter panel,
`#if os(macOS)`), the host would be an `NSHostingView` in the macOS `xFractalTests` target, and capturing a
`CAMetalLayer` from an `NSView` is unproven, the problem the spike solved for iOS. The reference marks the Mac host
itself "not proven yet". A later plan, after its own spike.

## Alternatives rejected

- **The spike's sleeps**: replaced by frame-specific readiness. A longer sleep only makes a race rarer.
- **An empty command buffer as a fence**: proves earlier GPU work finished, not that our draw submitted anything,
  nor that its drawable was presented (review round 1). Replaced by the frame observer.
- **`layer.render(in:)`**: blank where the Metal layer is (spike). **Drawable readback composited under the UI**:
  needs `framebufferOnly = false` and a second compositing path; `drawHierarchy` needs neither.
- **A fixed bottom band for the peek**: it measures mostly fractal. The difference mask finds the capsule itself.
- **Whole-image luminance with a looser threshold**: no threshold separates a bright fractal under a dark sheet from
  a blank light render.
- **A detent seam first**: the sheet's own presentation controller reaches the states with no app change; the seam
  is the fallback.
- **A real iPad simulator pass now**: a second boot (about 6 GB, minutes); the regular-width approximation is the
  cheap first step and is labelled as such.
- **A build-lock wrapper**: xFractal has none; the gallery's own DerivedData and lock cover gallery contention
  (limits in Design 3, point 5).
- **A preference save and restore**: nothing is changed.
- **Swift Testing**: the repo's tests are XCTest.

## Test plan (red first)

macOS, `Tests/` (the repo's TDD target, `xcodebuild test -scheme xFractal`):

- `StateStoreTests.testLoadPreservesPersistedJournalAfterDebounce`: seed a **non-default** state (Julia, so the
  load's assignment really changes `state` and fires `didSet`) and a two-snapshot Mandelbrot journal at 0 s and
  5 s, build the store, run the run loop 0.7 s (past both debounces), then assert the persisted data under
  `journalKey` and `stateKey` is **byte-for-byte** the seeded data, and the in-memory `journal` equals the seeded
  one exactly. Expected red today (`[state]` written).
- `StateStoreTests.testLoadPreservesPersistedJournalAfterImmediateBackground`: the same seed, `enterBackground()`
  right after the store is built (it performs pending saves), then the same exact assertions. Expected red today.
  Both extend the existing persistence tests (`testJournalLoadsFromInjectedDefaults`, line 106); the fix goes in
  only if they are red.
- `ContentViewInitTests.testStoreIsNotBuiltOnEveryInit`: `ContentView(store: makeCountedStore())` twice, unhosted;
  the factory ran 0 times. Red against the spike's eager seam.

iOS, `GalleryTests/GalleryScenarioTests` (run in every gallery run and in the step gates):

- `testHostedStoreIsBuiltOncePerIdentity`: a wrapper view hosts `ContentView(store: counted())` in a window and
  re-renders three times through its own `@State`; the factory ran once and the store seen by a probe is the same
  object each time. Then the wrapper changes the view's `.id`: the factory runs once more. Red against the eager
  seam (it runs on every re-render).
- `testSlugsAreUnique`.
- `testBuilderIsFreshPerCall`: two calls of every builder return different `StateStore` instances and suite names.
  Red first against a caching builder.
- `testSeededStateReadsBackThroughLoad`: for every scenario, the built store's `state` and `journal` equal the
  declared ones, so a renamed key or an undecodable `ViewState` (which `load()` ignores, showing defaults) fails here.
- `testActiveScenePhaseKeepsMetalRunning`: mounts scenario 1 through the harness and asserts the `MTKView` is not
  paused after the first render, after ten store updates, and during 0.5 s of a replay (scenario 7). Written before
  the `.environment(\.scenePhase, .active)` line, seen red (paused), then green.
- `testReadinessObservesOurFrame`: through the harness, the explicit draw yields exactly one observed submission,
  a completed status without error and a presented time; with the observer left unarmed the readiness reports "no
  frame submitted" within its bound. Written before the observer exists.
- `testDetentSelectionSettles`: scenario 9 and 10's sheets report the requested identifier and a frame that matches
  the detent's expected height band (medium about half the window, large near full height).
- `testRegularWidthTraits`: scenario 16 and 17 report `.regular` in the hosting controller, the sheet controller,
  the outer SwiftUI probe and the SwiftUI probe inside the sheet.
- `testContentMatchesReference`: scenario 2's capture matches its own reference render and **fails** against
  scenario 1's (a different fractal); a uniform region fails (blank).
- `testStaleFrameIsRejected`: the harness presents a frame of another state (Julia) through the observer path,
  then validates against the expected state (Mandelbrot) without a new draw: validation fails; after a fresh draw of
  the expected state it passes. Written before the comparison exists.
- `testReplayScenarioIsStable`: scenario 7's observed frame state equals snapshot A at two moments 0.5 s apart, and a
  render that ends more than 10 s after `replay()` is reported as failed (clock injected into the harness).
- `testScrollFindsVerticalForm`: in scenario 12, the chosen scroll view is the vertical form (not the presets row),
  the offset holds, and "Rabbit" and "Clear Journal" are inside the sheet's visible frame.

Page script contract tests (`scripts/test_preview_gallery.py`, copied, then extended red first): `test_check_ok`,
`test_duplicate_slug`, `test_missing_image`, `test_stray_png`, `test_undecodable_png`, `test_dark_identical_to_light`,
`test_partial_import_preserves`, `test_partial_import_merges_manifest`, `test_full_import_replaces_own_language_only`,
`test_languages_coexist`, `test_check_rebuilds_page`, and the region cases:
`test_bright_fractal_under_dark_sheet_passes` (red against the copied whole-image check),
`test_light_sheet_in_dark_slot_fails`, `test_sheet_text_heavy_region_fails_coverage`, `test_blank_fractal_fails`,
`test_peek_capsule_found`, `test_peek_missing_capsule_fails`, `test_peek_fractal_difference_outside_fails` (the
pixels around the capsule differ: the render was not deterministic), `test_peek_low_component_coverage_fails`,
`test_region_on_undecodable_image_fails`, the region validation cases `test_region_nan_fails`,
`test_region_non_positive_size_fails`, `test_region_outside_image_fails`, `test_region_pair_geometry_mismatch_fails`,
the measurement mode cases `test_measure_mode_reports_without_enforcing` and `test_measure_mode_still_enforces_structure`
(a missing image still fails), the floor cases `test_non_positive_peek_separation_fails` and
`test_sheet_coverage_below_floor_fails`, and `test_page_and_manifest_have_no_absolute_paths`.

Lifecycle tests and their mutation checks: Design 3.

## Gates

- **Tests:** `xcodebuild test -project xFractal.xcodeproj -scheme xFractal -configuration Debug` (macOS) passes;
  `GalleryScenarioTests` pass (they run in every gallery run); `python3 -m unittest discover -s scripts -p
  'test_preview_gallery.py'` and `scripts/test_snapshot_gallery.sh` pass. The number of tests run is read, not only
  the status.
- **Warnings:** `xFractal` and `xFractal-iOS` build with 0 warnings in our sources (target builds with their own
  `SYMROOT`, as the develop reference describes).
- **Gallery:** `CHECK OK [en]: <n> cards`, zero failed renders and **zero redraws**; a redraw is a finding to
  explain before the gate passes. Every card read in both appearances.
- **Public privacy check**, before every commit. Inventory: the committed branch (`git diff main...HEAD
  --name-only`), the staged content (`git diff --cached`), unstaged changes (`git diff`) and untracked files
  (`git status --porcelain --untracked-files=all`, ignored files listed separately with `--ignored`), plus the
  generated deliverables that may be shown or shared: `previews/index.html`, `previews/manifest.json`,
  `previews/calibration.json` and the PNGs. Rules: no absolute home path (`/Users/`), no email address outside commit
  trailers, no signing team ID (`DEVELOPMENT_TEAM`, ten-character team identifiers), no `Signing.local.xcconfig`
  tracked or staged, no PNG or other binary tracked or staged (`previews/` is ignored; screenshots are never
  committed), and none of the private repo names (the list comes from the parent session's repo index and is run from
  the scratchpad, never written into this repo). Metadata: the PNGs carry no text, `iTXt` or `eXIf` chunks (checked
  by chunk listing), the commits' author and committer are the repo's usual public identity
  (`git log main..HEAD --format='%an %ae %cn %ce'`). Logs under the run's scratch directory hold absolute paths;
  they are never committed or shared. Copied scripts, their test fixtures, the skill and the plan are all in scope.
- **Simulator:** the gates keep the xFractal Agent simulator booted from the first gallery gate to the last
  (`--keep-booted`), then `scripts/snapshot-gallery.sh --shutdown`, also when a gate fails and work stops.

## Invariants (AGENTS.md)

- **TDD**: holds; every new behaviour has a test seen red first, or a mutation check for copied guards. The capture
  itself (Metal, UIKit presentation) is verified by the gallery run and by reading the cards, as AGENTS.md asks.
- **Pure logic stays in `FractalMath.swift` / `FractalState.swift`**: holds; the journal fix is in `StateStore`.
  The app changes are the lazy seam, the hydration fix (if red), the nil-by-default frame observer and sheet
  probe slot, and the behaviour-preserving `encodeFrame` extraction.
- **The `.xcodeproj` is generated**: holds; only `project.yml` changes, `xcodegen generate` after.
- **Shared source tree, `#if os(...)` for platform UI**: holds; `GalleryTests/` is iOS only; the macOS build and
  tests run at every gate because `ContentView.swift`, `FractalState.swift` and `FractalRenderer.swift` are shared.
- **Public repo**: the privacy check above; `Signing.local.xcconfig` is never added.

## Risks

- **`\.scenePhase` override not honoured** in a `UIHostingController`: caught by
  `testActiveScenePhaseKeepsMetalRunning`; fallback seam named above.
- **Presented handler never fires** in the simulator for an offscreen-sized window: readiness fails with
  "presented timeout" within 2 s, never hangs. Then step 1 decides between a smaller regular-width window and an
  iPad simulator pass, and reports.
- **A window larger than the screen** may lay out or draw only the on-screen part. Step 1 renders scenario 16;
  if it fails, the regular-width group moves to an iPad simulator run after the iPhone one (one more boot, about
  6 GB and minutes), reported to Jean before it is built.
- **Non-identical fractal pixels between light and dark**: `test_peek_fractal_difference_outside_fails` and the
  step 2 measurement catch it; then the peek check falls back to the capsule box measured from the light image's
  material edge, decided with the data.
- **The reference render differs from the on-screen frame** (colour space, scale): measured in step 1 on scenarios
  1, 11 and 16 before the correlation threshold is relied on; a systematic mismatch is fixed in the reference path
  (same pixel format, same drawable size), not by lowering the threshold below 0.9.
- **SwiftUI's accessibility tree not reachable** for the scroll verification: the render fails loudly; then the
  verification moves to the reference-free card read, said so in the skill.
- **The selected detent reset by SwiftUI**: caught by `testDetentSelectionSettles`; fallback seam above.
- **Deep zoom**: the reference orbit is computed on the CPU inside `draw(in:)`; it lengthens that render only. Its
  `ready` time is reported separately.
- **Xcode Cloud**: the `main` workflow is build-only (Build - iOS, Build - macOS); the render test skips without
  `XFRACTAL_SNAPSHOT_DIR` anyway. The plain gallery tests need a simulator, so they run in gallery runs and local
  gates only. The journal fix and the lazy seam are covered by the macOS tests, which run locally.
- **Memory**: one simulator (the global rule); the gallery never boots a second one. Measured below.

## Measurements owed (recorded here, then in the skill)

Measured at the step 1 gate and the step 2 gate, on the xFractal Agent simulator, with `vm_stat` (active + wired +
compressed pages, sampled every 5 s in the background during the run; summed RSS over-counts shared memory):

- memory before boot, after boot, peak during the test, after shutdown (reference: boot about 6 GB, a run on a
  booted simulator about 0.25 GB);
- a **cold** run (simulator shut down, fresh DerivedData), a **warm** run, and `--only "replaying"` alone: boot,
  build, test, total;
- per render: `ready` (the settle) min / median / max, submits, redraws, total; the spike's figure to beat is 1.2 s
  per capture, of which 1.0 s sleep;
- the region calibration table (step 2, from `--measure`): per board pair, the peek light-dark difference, the
  capsule box, the component count and coverage, the outside-difference share; per sheet pair, the coverage in both
  appearances; per scenario, the reference correlation (or mean absolute difference);
- the run times of the contract and lifecycle suites (well under a minute).

| run | boot | build | test | total | ready median (max) | redraws | peak memory |
|---|---|---|---|---|---|---|---|
| step 1 cold | 70.7 s | 34.8 s | 75.8 s | 195.3 s | 152 ms (951) | 0 | see Outcome |
| step 1 warm | 0.3 s | 3.9 s | 18.3 s | 30.0 s | 112 ms (849) | 0 | |
| step 2 warm, run 1 | 0.3 s | 5.6 s | 52.5 s | 84.1 s | 699 ms (917) | 0 | |
| step 2 warm, run 2 | 0.3 s | 2.6 s | 40.2 s | 70.5 s | 709 ms (975) | 0 | |
| `--only replaying` (4 renders) | 0.3 s | 2.4 s | 15.5 s | 44.4 s | | 0 | |

## Steps

1. **Test target, scripts and three scenarios** — the journal tests (and the hydration fix if red) and the lazy
   seam with their tests; **all 17 scenario fixtures** (`GalleryTests/GalleryFixtures.swift`: every seeded state,
   journal, sheet, scroll and size), with `GalleryScenarios.all` rendering only scenarios 1 (board), 11 (sheet at
   the large detent) and 16 (regular width, the riskiest); the harness with the active scene phase, the frame
   observer, the `encodeFrame` extraction, the reference comparison, the sheet probe slot, minimal detent selection
   and the scroll handling; the region check with validation always on and `--measure` for the peek and sheet
   thresholds; the lifecycle script and its stubbed tests with their mutation checks; `CaptureSpikeTests.swift`
   deleted; `previews/` in `.gitignore`. The plain tests that mount other scenarios (7, 9, 10, 12, 17) mount their
   fixtures, so every test above runs in step 1. Gate: every test suite passes; a cold and a warm run end
   `CHECK OK [en]: 3 cards` with zero redraws (measure mode for peek and sheet); 0 warnings on both platforms; the
   reference-comparison values and the measurements recorded; the three cards read in both appearances; the
   privacy check.
2. **Every scenario** — the other 14 entries added to `GalleryScenarios.all` from their fixtures; a measure-mode
   run over all 17, the table and the images inspected, then the thresholds set (with their floors) and enforced.
   Gate: `CHECK OK [en]: 17 cards` with the thresholds enforced, on two consecutive warm runs with zero failed
   renders and zero redraws; the calibration table recorded and every fixture inside it; all test suites pass; 0
   warnings; every card read in both appearances, findings reported, not fixed in passing; the measurements
   recorded; the privacy check.
3. **Skill and AGENTS.md** — `.claude/skills/preview-gallery/SKILL.md` with xFractal's facts, limits and measured
   numbers; the AGENTS.md section. Gate: `git diff --check`, the skill's commands and paths resolve, the privacy
   check over the whole branch, the simulator is shut down; Jean reviews the gallery.

## Decisions left open for Jean

1. **iPad**: the regular-width approximation (default), or an iPad simulator pass after the iPhone one, which step 1
   brings back only if the oversized window does not draw.
2. **Where plans live**: `planning/` (not published; default as of revision 2), or back in `docs/`, which GitHub
   Pages serves.

## Outcome (implementation log)

Decisions left open took the plan's defaults (Jean, 2026-10-15): the regular-width approximation for iPad, plans stay in `planning/`.

### Step 1

- **Journal hazard: real.** `testLoadPreservesPersistedJournalAfterDebounce` was red (229 bytes written over 424), so the
  hydration fix is in (`isHydrating`); both journal tests are green. The lazy seam test was red against the eager seam.
- **Scene phase.** `testActiveScenePhaseKeepsMetalRunning` was seen red with the override off (the view was paused) and is
  green with `.environment(\.scenePhase, .active)`. Mutation checks (a scratch edit, never committed) made the lazy-seam,
  frame-observer, stale-frame and reference tests red.
- **Cold run** (DerivedData removed, simulator shut down): boot 70.7 s, build 34.8 s, test 75.8 s, total 195.3 s.
  **Warm run**: boot 0.3 s, build 3.9 s, test 18.3 s, total 30 s. `CHECK OK [en]: 3 cards`, zero redraws, six renders.
  `ready` (settle) per render: min 70 ms, median 112 ms, max 849 ms (the sheet scenario); the spike's figure was 1.2 s.
- **Reference comparison** (Pearson over 64 x 64 luminance, light / dark): scenario 1 1.0000 / 1.0000, scenario 16
  0.9999 / 0.9999. Scenario 11 has no board region left to compare (large detent), see the deviations.
- **Calibration (measure mode, scenarios 1, 11, 16)**: peek light-dark separation 0.195 (phone), 0.169 (regular width), capsule
  coverage 0.96 / 0.95, one component, nothing differing outside the capsule; sheet coverage 0.968 light / 0.934 dark.
- Memory (`vm_stat` active + wired + compressed, whole machine, other sessions running): 12.7 GB before the cold run,
  19.7 GB peak; too noisy to separate the simulator's share.
- Lifecycle tests: 10 mutation checks all red on the named cases. macOS tests: 68 pass. 0 warnings on both platforms.

Deviations in step 1:

- **No presented handler.** The iOS SDK has no `MTLDrawable.addPresentedHandler`. The readiness evidence is now
  *submitted/scheduled*: the frame of the expected state was submitted, its buffer scheduled (`addScheduledHandler`),
  completed without error, and two display-link ticks went by (bounded). Actual presentation is not proven.
- **Regular-width traits.** The sheet took the phone's compact class from the window: the window and the presented
  controller now carry `traitOverrides.horizontalSizeClass = .regular` too; the test asserts all four places.
- **Scroll verification.** SwiftUI builds no accessibility tree in a test and draws the Form's text itself, so "Rabbit" and
  "Clear Journal" cannot be found by label. The form is a `UICollectionView`; the presets row (the cell with the horizontal
  scroll view) and the last row (Clear Journal) are found structurally and verified visible. The large detent already shows
  almost the whole form (content 843 pt), so the scroll moves only 65 pt.
- **Content reference for sheets.** A scenario whose sheet leaves no board area (large detent) has no fractal region to
  compare; it is checked by the observed frame's state, the submitted/scheduled evidence and the sheet region only (no captured-content check of the board).
- **Lock location.** The gallery lock lives in the shared git directory (`rev-parse --git-common-dir`), not in the main
  checkout's `.build/`: xFractal is a submodule, where that path would land inside the parent's `.git`.
- **Metadata.** The simulator's PNGs carry an `eXIf` chunk (orientation, size); the import strips eXIf and text chunks
  (test added), so the images carry none.

### Step 2

All 17 scenarios render, 34 images, zero redraws, on two consecutive warm runs, `CHECK OK [en]: 17 cards` with the thresholds
enforced. `--only "replaying"` merges into the full manifest (17 entries, all with regions).

Calibration table (measure mode over every pair; the reference correlation is 0.9999 or better for every scenario that has
a board region, 1.0000 for most):

| pair | peek light - dark | capsule box (pt) | components | coverage | outside diff |
|---|---|---|---|---|---|
| 1 Mandelbrot first launch | 0.195 | 220 x 36 | 1 | 0.96 | 0 |
| 2 Julia | 0.168 | 172 x 36 | 1 | 0.95 | 0 |
| 3 Newton | 0.202 | 185 x 36 | 1 | 0.95 | 0 |
| 4 Multibrot | 0.180 | 204 x 36 | 1 | 0.96 | 0 |
| 5 Deep zoom | 0.181 | 234 x 36 | 1 | 0.96 | 0 |
| 6 Replay ready | 0.150 | 220 x 36 | 1 | 0.96 | 0 |
| 7 Replaying | 0.179 | 220 x 36 | 1 | 0.96 | 0 |
| 16 Regular width Julia | 0.169 | 172 x 36 | 1 | 0.95 | 0 |

Sheet coverage (light / dark): 10 first launch 0.928 / 0.939, 11 Julia 0.968 / 0.928, 12 bottom 0.969 / 0.935, 13 Newton
0.868 / 0.922, 14 Multibrot 0.978 / 0.942, 15 replaying 0.974 / 0.949.

Thresholds set: `PEEK_DELTA` = 0.075 (half of 0.150; the floor is 0.03); capsule coverage floor 0.70, outside ceiling 0.5 %
(measured 0.95 and 0); sheet coverage = 0.50 (half of the smallest measured, 0.868, would be 0.434: the floor wins).
Fractal regions: smallest mean 0.026 and smallest std 0.033 (the cold Julia boards, near black by palette: they pass the
0.02 rules narrowly).

Deviation: **translucent sheets.** In this iOS the opening-detent and medium sheets, and the regular-width form sheet,
are translucent glass over the board (the fractal and even the blurred peek capsule show through). A "lit background"
coverage rule cannot hold for them (measured 0.01 to 0.19). They get their own region kind `sheetGlass`: the region must read
lighter in the light render than in the dark one by at least 0.13 (half of the smallest measured, 0.262; floor 0.10), with
four contract tests. The large detent sheets are opaque and keep the coverage rule.

Visual findings (reported, not fixed): the peek capsule shows through the translucent sheets (blurred "Mandelbrot 512"
under the Iterations row at the opening detent and at medium); a disabled Replay or Clear Journal row (scenario 10, 15)
reads as plain black or white text, not dimmed, while its icon stays blue or red in some states; in the light controls
the Julia presets (`.bordered` buttons) have no visible capsule against the white row, in dark they do; the large detent
leaves a large empty area below the last section when the content is short (scenarios 10, 14, 15); the cold Julia board
is nearly black with a thin blue fractal. Nothing is blank, clipped or unreadable.

### Step 3

`.claude/skills/preview-gallery/SKILL.md` (the reference skill with xFractal's facts, limits and measured numbers) and the
AGENTS.md "Preview gallery" section are in. The simulator is shut down and the gallery lock and marker are gone. The
view-coverage report (`--coverage`) lists `FractalView` only (`ContentView` is named by the scenario builder). The parent
session registers the skill in its repo index.

### Codex code review, round 1

No shipping-code regression (the hydration guard, the lazy seam and the renderer extraction were fine). Seven findings, each
fixed with a test seen red first (or a mutation check):

1. **Blocker: a child that ignores TERM.** The cleanup sent TERM once and waited forever. It now sends TERM, waits up to
   `XFRACTAL_SNAPSHOT_KILL_GRACE` seconds (10 by default), sends KILL to the owned child only, then reaps it, and reaches the
   simulator shutdown. Three lifecycle cases (`signalled_term_{bootstatus,build,test}_ignoring_term`, a stub that traps TERM)
   were red, are green, and went red again with the KILL line removed in a scratch copy.
2. **Image sizes.** `--check` now requires the light and dark images to have equal decoded dimensions and the manifest's
   aspect (`image size mismatch`, `does not match the manifest size`); the scale comes from the decoded size.
3. **Truncated PNGs.** Every expected image is checked whole, whatever its region kinds: the PNG structure is walked in
   Python (signature, chunk lengths and CRCs, closing IEND: ImageIO decodes a truncated file without complaint, measured) and
   the pixels are decoded by the helper. Test: a truncated PNG with a valid IHDR.
4. **Presentation evidence.** Three terms are used everywhere: *submitted/scheduled* (a frame of the expected state was
   submitted, completed and scheduled, plus two display-link ticks), *captured content* (checked against the reference render)
   and *actual presentation*, which is not proven (the iOS SDK has no per-drawable presented handler). The content check
   proves the captured content only.
   Measured while adding the requested negative case: a capture can lag the explicit draw (once in about five runs the
   frame still showing was the previous one) and a committed frame whose present was suppressed was captured in one probe
   and not in another, so the capture of an unpresented frame is timing dependent and no test can assert either outcome. The
   suppression hook was therefore not kept in the app. `testStaleFrameIsRejected` is now the negative case: a different
   frame visible (Julia, with a redraw loop like the render's) fails the validation against the expected state, and
   the expected frame passes after a fresh draw. A scenario with no board region (large detent) has only the
   submitted/scheduled evidence and no captured-content check; stated in the skill.
5. **Absolute error.** The validation now also fits the sheet's scrim (captured = (1 - scrim) x reference, a black overlay)
   and bounds the mean absolute RGB error after it at 0.01, with the scrim inside [-0.02, 0.02] for the plain board and the
   opening detent and [-0.02, 0.5] for the medium and large detents. Measured over all 34 renders: RGB error at most 0.0007,
   scrim 0.000 to 0.001 everywhere except medium (light 0.154, dark 0.377 as first measured, mid-fade; settled values 0.200 and 0.479, round 2). `testBrightnessAndColourErrorsAreRejected`: a white
   15 % overlay, a red 20 % cast and an unexpected 30 % dimming fail; the same dimming passes where it is allowed; with the
   error bound relaxed in a scratch copy the test went red.
6. **Sparse glass difference.** The translucent-sheet rule also needs spatial coverage: at least 50 % of the region's pixels
   must be brighter in light than in dark by 0.05 (measured 0.955, 0.969, 0.973; half of the smallest is 0.477, the floor 0.50
   wins). Test: 14 % bright and dark pixels lift the mean past 0.13 and now fail.
7. **Paths with spaces.** The pixel jobs are JSON arrays on stdin (and the helper is compiled once into the temp directory,
   falling back to the interpreter), so any path works; test: an output directory with a space.

Gallery: two consecutive warm runs `CHECK OK [en]: 17 cards`, zero redraws. Suites: macOS 68, contract tests 42, lifecycle
suite green.

### Codex code review, round 2

1. **Scrim fit (should-fix).** The fit took its gain from the pixels it checks, so a capture at 0.7 x the reference had
   correlation 1, a fitted scrim of 0.3 and no residual. The fitted scrim is now bounded per scenario and appearance:
   [-0.02, 0.02] for every scenario but the medium detent (measured 0.000 to 0.001), and 0.200 +-0.03 (light) and 0.479 +-0.03
   (dark) at the medium detent, measured after the dimming has settled (`settleScrim` waits, bounded, for three equal
   fits: the first calibration, 0.154 and 0.377, had caught the fade in progress, and one run read 0.479 in dark); the large detent has no board region. `testMediumDetentScrimIsBounded` mounts the medium
   detent in both appearances: the capture passes, extra dimming (black 30 %, residual still under 0.01, so only the band
   rejects it) fails, and a brightening (white 10 %) fails. The validation is stated as "modulo the calibrated scrim band".
2. **Wording.** The reference to a test that does not exist is gone. Three terms are used in the harness, the skill and this
   Outcome: submitted/scheduled, captured content (what the validation proves) and actual presentation (not proven). The
   step 1 deviation and the large-detent text no longer say "presented".
3. **Skill glass rule.** It states both conditions: mean separation >= 0.13 **and** >= 50 % of the pixels separating by more
   than 0.05.

### Codex code review, round 3

1. **Settling decision.** `settleScrim` compared adjacent samples only, so a steady drift passed. The decision is now the pure
   `ScrimSettling.isSettled`: the last 3 fitted scrims must span (max - min) no more than 0.004. The end of the dimming
   animation is not observable from the test (no completion callback reaches it), so the fit is what is watched.
   `testScrimSettlingNeedsAFlatWindow` is deterministic: a flat sequence is settled, `[0.188, 0.192, 0.196, 0.200]` and a late
   step are not, and only the last window counts. With the check reduced to adjacent samples in a scratch copy it went red.
2. **Pure gain.** `testPureGainOutsideTheScrimBandIsRejected` builds captures that are the reference render times a
   constant (no offset): inside the band it passes; 0.1 below the lower limit (a brightening relative to the sheet's scrim)
   and 0.1 above the upper one it fails, with the fitted scrim on the wrong side and the RGB residual under 0.01, so only the
   band rejects it. With the lower-bound check removed in a scratch copy the test went red in both appearances.
3. **Load.** Under a loaded machine two waits timed out (the sheet frame stability, 5 s, now 10 s; the stale-frame test now polls
   the capture for up to 1.5 s per round, three rounds, redrawing between rounds). No expected value changed.

Gallery: `CHECK OK [en]: 17 cards`, zero redraws, scrim 0.200 / 0.479 at the medium detent again. Contract and lifecycle
suites green.
