# xFractal — working notes for coding agents

## Use TDD by default

For any change that touches non-trivial logic, follow red → green → refactor:

1. **Red.** Write a failing test in `Tests/` that captures the desired behavior. Run the test target and confirm it fails for the right reason.
2. **Green.** Write the smallest production-code change that makes the new test pass. Don't generalize ahead of the test.
3. **Refactor.** Once green, clean up — extract helpers, simplify, dedupe — keeping the suite green between each step.

When fixing a bug, the failing test must reproduce the bug *before* the fix is applied. When a behavior is hard to express as a test (UI gestures, Metal rendering), say so explicitly and fall back to manual verification — but check first that the underlying logic isn't actually pure math that *could* be lifted into `FractalMath.swift` and tested.

## Where things live

- **Pure logic** (math, state transitions, journal coalescing, double-float split, Mandelbrot kernel) → `xFractal/FractalMath.swift` or `xFractal/FractalState.swift`. Always testable.
- **Tests** → `Tests/*.swift`. Bundled into the `xFractalTests` macOS unit-test target.
- **SwiftUI views, gesture wiring, Metal pipeline glue** → not unit-tested. Cover the math the gestures use; verify the wiring manually.

## Running the tests

```sh
buildlock --folder "$PWD/.build/DerivedData" -- \
  xcodebuild test -project xFractal.xcodeproj -scheme xFractal-MAS -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$PWD/.build/DerivedData"
```

The `xFractal-MAS` scheme's test action runs `xFractalTests` (71 tests, hosted by the Mac app; no simulator). Tests must
pass before any commit. Without a signing team the app is signed ad hoc and the tests still run; if signing fails
anyway, add `CODE_SIGNING_ALLOWED=NO`. Without `buildlock` on `PATH`, run the `xcodebuild` part alone.

## Project regeneration

`xFractal.xcodeproj` is generated from `project.yml` by XcodeGen and is checked into git. After editing `project.yml`, run `xcodegen generate` and commit the regenerated project with it; never edit the project in Xcode without carrying the change into `project.yml`. If Xcode applies new build settings (e.g. "Update to Recommended Settings"), bake them into `project.yml` so they survive regeneration.

## Platforms

Two app targets share the `xFractal/` source tree: `xFractal-MAS` (the Mac app, sandboxed, shipped through the Mac App
Store) and `xFractal-iOS` (iPhone/iPad). Both are product `xFractal` with bundle ID `ch.arizonasoftware.xfractal`
(one universal purchase). Xcode Cloud workflows use the scheme names `xFractal-MAS` and `xFractal-iOS`: never rename
them. Use `#if os(macOS)` / `#if os(iOS)` for platform-specific UI; keep math platform-agnostic.

There is no Sparkle and no DMG any more. `docs/appcast.xml` is frozen for the installed 1.0 DMG copies: never edit it
(see `RELEASING.md`).

## Languages

English (source), French, German and Italian, as Departure. Every user-facing string goes in
`xFractal/Localizable.xcstrings` (one catalog for both apps) with all three translations; `LocalizationTests` fails on a
key that misses one, and on a stale key. Math notation and bare numbers use `Text(verbatim:)` so they stay out of the
catalog. After adding or changing strings, sync the catalog headless and translate the new keys:

```sh
~/GitHub/maestro/bin/catalog-sync              # builds both apps, adds new keys, marks unused ones stale
~/GitHub/maestro/bin/catalog-sync --delete-stale
~/GitHub/maestro/bin/catalog-sync --check --skip-build   # "catalog unchanged" before committing
```

The App Store page has the same four languages: descriptions, keywords and names in `AppStore/` (the `/release`
skill loads them).

## Preview gallery (no `#Preview`)

The iOS app has no `#Preview`: every screen state is a scenario in `GalleryTests/GalleryFixtures.swift` and
`GalleryScenarios.swift`, rendered light and dark by one hosted snapshot test (`SnapshotGalleryTests`, skipped unless
`XFRACTAL_SNAPSHOT_DIR` is set, so normal runs and Xcode Cloud skip it). Never add a `#Preview`. A new or changed screen
needs a scenario; the `/preview-gallery` skill has the rules, the limits and the calibrated checks.

```sh
scripts/snapshot-gallery.sh                 # all 19 scenarios -> previews/index.html (gitignored), then CHECK OK
scripts/snapshot-gallery.sh --only "julia"  # a subset
python3 -m unittest discover -s scripts -p 'test_preview_gallery.py'   # page and check contract tests
scripts/test_snapshot_gallery.sh                                      # lifecycle tests with stub simctl, simpool and buildlock
```

- `GalleryTests/` is the **iOS** test target (`xFractalGalleryTests`, hosted by the app); `Tests/` stays the macOS logic tests
  (`xcodebuild test -scheme xFractal-MAS`, 71 tests). The plain gallery tests run with every gallery run.
- The simulator is leased from the machine-wide pool (`simpool acquire --spec iphone`: iPhone 17 Pro, iOS 27.0) and given
  back with `simpool release` when the script ends, on success, failure or interrupt; both `xcodebuild` commands run under
  `buildlock`. The script never boots or shuts down a simulator itself. Without `simpool`/`buildlock` on PATH (a
  contributor's Mac) it falls back to its own **xFractal Agent** simulator, which it creates, boots and shuts down.
- An `--only` run checks every scenario: in a fresh checkout run the whole gallery once first.
- iPhone and English only; the "Regular width" cards are an 834 x 1210 pt phone-simulator approximation, not iPad coverage.
- The plan and its outcome (measurements, thresholds, findings): `planning/gallery-scenarios-plan.md`.

## App Store screenshots

The iPhone App Store screenshots are rendered from the preview-gallery captures by the `app-store-screenshots`
command: tilted phones, a headline per store language, and a pair of screenshots that share one phone lying across the
seam. The slides (captures, phone angles, backgrounds, headlines in the four languages) are in
`AppStore/screenshots.json`; the `/app-store-screenshots` skill renders, reviews and uploads them.

```sh
scripts/snapshot-gallery.sh          # the captures, into previews/
app-store-screenshots                # -> .build/app-store-screenshots/<locale>/NN-<slide>.png + index.html
```

- 1320 x 2868 (`APP_IPHONE_67`), at most 10 per language; files are numbered in display order, and a pair
  (`"panels": 2`) must stay adjacent.
- The captures are English and 2x (804 px wide): the Controls sheet shows English UI in every language.

The product page header and the search results asset (iOS 27, no text, one image each for every language) are the same
command with `--config AppStore/header.json` (3840 x 1646: the whole yellow Mandelbrot, centered, no phone) and
`--config AppStore/search-results.json` (3840 x 2560: the Mandelbrot on the left, an upright phone with its status bar
and buttons showing the Julia Spiral in colour on the right, vertically centered). Their backgrounds are rendered full size by the
gallery run into `previews/artwork/` (`GalleryFixtures.artwork`); `app-store creative --placement header|search` uploads
them.
