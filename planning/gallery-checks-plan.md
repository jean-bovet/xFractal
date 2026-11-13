# Gallery script: the newer preview-gallery checks

Status: Implemented on main 2026-11-13. Earlier: planned 2026-11-13, revision 2 (Codex plan round 1: test gate on every step, size/points agreement, settled size checked before capture validation, skipped-entry test, no `measured` field); round 2: one finding rejected (step 4 gates, rationale under Gates). Goes ahead. Branch `jean-bovet/gallery-checks` (Orca worktree, from
`main` b3cd125). GitHub issue #9.

Builds the three rules the shared preview-gallery process gained into xFractal's gallery script and harness, then
removes the "not yet in this repo's scripts" notes from `.claude/skills/preview-gallery/SKILL.md`. No app code, no
user-facing string, no change to the look of any screen.

## Problem, with evidence

1. **`--coverage` has the old name and no app coverage.** `scripts/preview-gallery.py:638`
   (`parser.add_argument("--coverage", action="store_true")`) runs `do_coverage()` (`:618-629`), which lists the view
   types no scenario names. The shared process calls that `--coverage-views` and uses `--coverage XCRESULT` to put the
   test run's app line coverage on the gallery page. The skill says it is missing: `.claude/skills/preview-gallery/SKILL.md:176-178`
   and `:196`. Nothing in `scripts/`, `project.yml` or `ci_scripts/` reads an `.xcresult` today, and the gallery's test
   run turns coverage off (`scripts/snapshot-gallery.sh:434-438`, `-enableCodeCoverage NO`).
2. **The manifest has no `points` or `scale`, and `--check` derives the render scale from the size.**
   `GalleryTests/SnapshotGalleryTests.swift:9-34` (`ManifestEntry`) writes `size` only (from
   `scenario.fixture.size.points`, `:79`). `scripts/preview-gallery.py:82-100` re-states `GallerySize.scale`
   (`GalleryTests/GalleryFixtures.swift:27`) as `RENDER_SCALE`, `DUO_INNER_SIZES`, `DUO_INNER_RENDER_SCALE` and
   `render_scale(entry)`, which `do_check` uses at `:462-466`. Two sources of the same fact: a new size at another scale
   would need both changed. The skill marks it: `SKILL.md:191-194`, `:279-283`.
3. **No settled-size failure.** `GalleryMount.init` (`GalleryTests/GalleryHarness.swift:135-136`) sets the window's
   frame to `scenario.fixture.size.points`, and `GalleryHarness.render` (`:794-847`) captures whatever the window settled
   at; nothing compares `window.bounds.size` with the requested size. The only such comparison is a test assertion for
   the Duo poses (`GalleryTests/GalleryScenarioTests.swift:169`, `testDuoInnerTraits`). A window the system resized
   would be captured at the wrong size and fail later, if at all, as an aspect or render-scale error that names the
   wrong cause. Skill: `SKILL.md:192-194`.

The Mac window capture (`Tests/MacWindowSnapshotTests.swift`, `scripts/snapshot-mac.sh:50-57`) writes no manifest and
is never passed to `--check`: none of the three rules applies to it.

## Design

### 1. `--coverage-views` and `--coverage XCRESULT` (`scripts/preview-gallery.py`)

- Rename the flag: `--coverage-views` (store_true) runs the existing `do_coverage()`, renamed `do_coverage_views()`,
  unchanged otherwise.
- `--coverage XCRESULT` (`type=Path`): `do_coverage(xcresult, lang)` runs `xcrun xccov view --report --json XCRESULT`,
  takes the target named `xFractal.app` (both apps' product name, so a Mac test-gate bundle and an iOS gallery bundle
  both work), and writes `previews/<lang>/coverage.json` (default `en`):
  `{"covered", "executable", "files": [{"path", "covered", "executable"}]}`, files least covered first.
  Every path is made relative to `ROOT`; a path outside the repo keeps its file name only (public repo: no absolute
  path in the page). A bundle without that target,
  unreadable JSON or a failed `xccov` prints `no app coverage in <bundle>: <why>` on stderr, exits 2 and writes nothing.
  When the folder already has a `manifest.json`, the page is rebuilt (`build_page(load_manifest(out), out, lang)`).
- `build_page` adds an "App coverage" section (total percentage, a table of files) when `coverage.json` exists in the
  folder, nothing otherwise, so a gallery without it looks as today.
- A full import already keeps `coverage.json`: `do_import`'s stale list (`:171`) names `*.png`, `manifest.json`,
  `index.html` and `calibration.json` only. A test pins it.
- Docstring (`:8-10`): both flags, plus the way to produce a bundle (the test gate of `AGENTS.md` with
  `-enableCodeCoverage YES -resultBundlePath .build/app-coverage.xcresult`). `snapshot-gallery.sh` does not collect
  coverage (`.claude/skills/develop/SKILL.md` § Gates: "No coverage command" in the full run).

### 2. `points` and `scale` in the manifest

- `ManifestEntry` gains `points: [Double]` (`[w, h]`, the shared process's shape) and `scale: Double`, filled for
  **every** entry, skipped ones included, from `scenario.fixture.size.points` and `scenario.fixture.size.scale`
  (`GallerySize.scale`, reused, not restated). `size` stays (the aspect rule, the regions and the page read it).
- `scripts/preview-gallery.py`: `render_scale(entry)` becomes `expected_pixels(entry)`: `(round(w*scale), round(h*scale))`
  from `points` and `scale`, or `None` when either is missing, not a list of two finite positive numbers, or not a
  finite positive number. `RENDER_SCALE`, `DUO_INNER_SIZES` and `DUO_INNER_RENDER_SCALE` are deleted.
- `do_check` checks every manifest entry's geometry first, skipped entries and entries without an image pair included:
  `points` must equal `size` (within 0.5 pt) or fail `points do not match size: <slug>`; an entry whose `expected_pixels` is `None` fails `no points and scale in the manifest: <slug> (run the full
  gallery)` — always, also with `check_render_scale=False` (that switch only exists for the contract tests' synthetic
  pixel sizes). The render-scale rule (`:462-466`) compares the light image with `expected_pixels` (within 1 px, as
  today), message `image not at the render scale: <slug> (W x H for w x h pt at Nx: W' x H' expected)` unchanged.
- The region scale (`:484`, `sizes[light_file][0] / width_pt`) stays: it is the measured scale the regions are mapped
  with, already guarded by the render-scale rule.
- A partial import keeps an old entry for every scenario it did not render (`do_import`, `:150-170`): a gallery built
  before this change fails the new rule on an `--only` run until a full run. The message says so; the landing gate
  runs the full gallery.

### 3. Settled window size (Swift harness, as the shared reference places it)

- `GalleryHarness.settledSizeFailure(requested: CGSize, settled: CGSize) -> String?` (static, pure): nil when equal,
  otherwise `the window settled at W x H, requested w x h`.
- `GalleryHarness.render` calls it inside the capture loop, after the layout settles and **before** `mount.validate()`
  (so a resized window is reported as such, not as a validation failure it caused), with `fixture.size.points` and
  `mount.window.bounds.size`, and throws `GalleryFailure(reason)`; `testRenderGallery` already turns a thrown render
  into `XCTFail("<slug> <appearance>: …")` (`SnapshotGalleryTests.swift:94-96`), so the run fails and names the scenario.

## Alternatives rejected

- **Settled size checked by `--check` from a `settled` manifest field.** The shared reference puts it in the harness;
  a field would be written only to be compared with another field of the same entry, and a bad capture would still be
  written to disk.
- **Keep deriving the scale in Python as a fallback.** That is the second source of truth the rule removes; the shared
  process fails an entry without `points`/`scale`.
- **Refresh `points`/`scale` of old entries during a partial import.** Saves one full run after upgrading; not worth a
  merge rule nobody else has. The failure message names the remedy.
- **`snapshot-gallery.sh` collects coverage itself** (`-enableCodeCoverage YES -resultBundlePath`). Slows every gallery
  run, and the full run has no coverage command by decision (develop § Gates).
- **A coverage hint section on every page.** Adds noise to every gallery that never ran `--coverage`.

## Test plan

Python (`scripts/test_preview_gallery.py`, proven red before each change, then green):

- `CoverageTests.test_coverage_views_lists_view_types` — the renamed flag prints the "view types appear" line (red: unknown flag).
- `CoverageTests.test_coverage_without_bundle_is_an_error` — `--coverage` with no argument exits 2 (argparse) (red: today it is a plain flag and runs).
- `CoverageTests.test_coverage_stores_app_coverage_and_shows_it` — a stub `xcrun` on `PATH` (prints a fixed
  `xccov` report with an `xFractal.app` target, one file under `ROOT`, one outside it, and another target) → exit 0,
  `previews/en/coverage.json` holds the `xFractal.app` totals and relative paths only (the outside file by name), the
  page has the "App coverage" section with the percentage, and no `/Users/` or `ROOT` string appears in either file.
  This is the production writer (`do_coverage`) and reader (`build_page`) end to end.
- `CoverageTests.test_bad_bundle_writes_nothing` — the stub exits 1 / prints no `xFractal.app` target → exit 2, message
  `no app coverage in`, no `coverage.json`.
- `CoverageTests.test_full_import_keeps_coverage` — `coverage.json` survives `--import` without `--partial`, and the
  rebuilt page still shows it.
- `RenderScaleTests` rewritten to write `points`/`scale` in the entry: `test_phone_at_2x_passes`,
  `test_phone_at_1x_and_3x_fail` ("at 2x: 46 x 100 expected"), `test_duo_inner_pose_at_3x_passes_and_at_2x_fails`
  (now driven by `scale: 3` in the entry, not by the size), plus
  `test_scale_comes_from_the_manifest_not_the_size` — a 951 x 669 pt entry with `scale: 2` passes at 2x (red: today
  the size forces 3x).
- `ManifestGeometryTests.test_entry_without_points_or_scale_fails` — each of: no `points`, no `scale`, `points` of one
  number, `scale: 0`, `scale: "2"` → exit 1, `no points and scale in the manifest: <slug>`; also with the render-scale
  check off, and for a skipped entry (no image pair), which must fail too (red: today these pass).
- `ManifestGeometryTests.test_points_disagreeing_with_size_fails` — `size` 402 x 874, `points` 804 x 1748 (same
  aspect), `scale` 1, images 804 x 1748 → exit 1, `points do not match size: <slug>`: `do_check` requires `points == size`
  (within 0.5 pt), so the regions (mapped from `size`) and the scale rule (from `points`) cannot disagree.
- `entry()` (`:95`) gains `"points": [W, H], "scale": 2`, so every existing test keeps its own reason to pass or fail.

Shell (`scripts/test_snapshot_gallery.sh`): the stub manifest for `badcheck` (`:127-128`) gains `points`/`scale`, so it
keeps failing for its own reason (missing images); the existing suite stays green.

Swift (`GalleryTests/GalleryScenarioTests.swift`, the iOS `xFractalGalleryTests` target; these plain tests run with
every gallery run):

- `testSettledSizeFailure` — equal sizes → nil; 951 x 669 requested, 951 x 600 settled → a reason containing
  `settled at 951 x 600, requested 951 x 669` (red: the function does not exist, so the red proof is the compile error
  plus the assertion with a stub returning nil). Run alone on a leased simulator:
  `udid=$(simpool acquire --spec iphone --pid $$)`, `trap 'simpool release "$udid" --app ch.arizonasoftware.xfractal' EXIT`,
  `buildlock --folder <dd> -- xcodebuild build-for-testing -scheme xFractal-iOS -destination 'generic/platform=iOS Simulator' -derivedDataPath <dd>`,
  then `buildlock --folder <dd> --no-slot -- xcodebuild test-without-building -scheme xFractal-iOS -destination "id=$udid" -derivedDataPath <dd> -only-testing:xFractalGalleryTests/GalleryScenarioTests/testSettledSizeFailure -parallel-testing-enabled NO -collect-test-diagnostics never`.
- The call site in `render` and the `points`/`scale` writer are covered by the landing gate's full gallery run: every
  scenario must settle at its size (the Duo inner poses at 951 x 669 / 669 x 951 on the iPhone pass) and `--check`
  must read `points`/`scale` from the Swift-written manifest (it fails without them), ending `CHECK OK`. Not unit-tested:
  forcing UIKit to resize a gallery window mid-render (named here as the gap).

Gates:

- Step 1: script tests (`python3 -m unittest discover -s scripts -p 'test_preview_gallery.py'`,
  `scripts/test_snapshot_gallery.sh`) and the test gate (`AGENTS.md`: tests pass before every commit). No warnings
  gate (no Swift change).
- Steps 2 and 3: script tests, the warnings gate (both `-target` builds; the iOS one compiles `xFractalGalleryTests`)
  and the test gate (82 Mac tests, unchanged count). Step 3 also the one-test simulator run above (red, then green).
- Step 4: docs-only checks (`git diff --check`, citations resolve). Codex round 2 asked for the test gate here: rejected — the develop skill's docs-only rule skips build gates for
  a change confined to `.claude/skills/`, and the code is the tree step 3's test gate passed on.
- Landing gate (fresh `<dd>`): test gate, warnings gate, script tests, and the **full** `scripts/snapshot-gallery.sh`
  (the harness and the manifest changed for every scenario), ending `CHECK OK [en]`. `--device ipad` and
  `--device duo` are not run: same code, every window there is the screen's size; the iPhone pass already holds the
  non-screen Duo inner sizes.

## Invariants

- Pure logic in `FractalMath.swift` / `FractalState.swift`: not applicable (test tooling only).
- Math platform-agnostic, `#if os` for UI only: not applicable.
- Product `xFractal`, bundle ID, scheme names: hold (no `project.yml` change, no new file, so no `xcodegen`).
- No `#Preview`: holds (no scenario added).
- `.xcodeproj` generated from `project.yml`: holds (untouched).
- `docs/appcast.xml` frozen: holds (`git diff --exit-code main -- docs/appcast.xml`).
- Public repo, no absolute path in the manifest or the page: at risk with `coverage.json` (xccov reports absolute
  paths); held by relative paths and the test asserting no absolute path.

## Risks and rollout

- **Both platforms:** the Mac capture has no manifest and no `--check`: unaffected. iPad and Duo passes use the same
  writer (`GallerySize` for every entry).
- **Existing galleries on disk** fail `--check` until a full run (old manifest entries lack `points`/`scale`). Message
  says so; one full run fixes it.
- **Other readers of the manifest** (the `app-store-screenshots` tool reads the captures): the fields are additive; `size`
  is kept.
- **Xcode Cloud:** the `xFractal-iOS` scheme's test action holds `xFractalGalleryTests` (`project.yml:67-69`); where a
  workflow runs it, the new pure test runs too and needs nothing (no files, no environment). The snapshot test stays
  skipped there.
- **Precision, saved state:** not applicable.

## Decision left open for Jean

None.

## Steps

1. **--coverage-views and --coverage XCRESULT** — rename the flag, add the `xccov` import into `coverage.json` and the page's coverage section, update the script docstring; Python tests first.
2. **points and scale in the manifest** — `ManifestEntry` writes `points`/`scale` from `GallerySize`; `--check` reads them for the render-scale rule and fails an entry without them; the Python derivation goes; test helpers and the shell stub carry the fields.
3. **Settled window size** — `GalleryHarness.settledSizeFailure` and its call in `render`, proven by `testSettledSizeFailure` on a leased simulator.
4. **Skill notes** — remove the "not yet in this repo's scripts" notes from `.claude/skills/preview-gallery/SKILL.md` (`:176-178`, `:191-194`, `:196`, `:279-283`) and describe the rules as implemented.
