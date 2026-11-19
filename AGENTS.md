# xFractal — working notes for coding agents

Mandelbrot and Julia explorer for the Mac and iPhone/iPad, rendered with Metal.

## Layout

- **Pure logic** (math, state transitions, journal coalescing, double-float split, Mandelbrot kernel) →
  `xFractal/FractalMath.swift` or `xFractal/FractalState.swift`. Always testable.
- **Tests** → `Tests/*.swift`. Bundled into the `xFractalTests` macOS unit-test target (hosted by the Mac app).
- **SwiftUI views, gesture wiring, Metal pipeline glue** → not unit-tested. Cover the math the gestures use; verify
  the wiring manually.
- **Two app targets** share the `xFractal/` source tree: `xFractal-MAS` (the Mac app, sandboxed, shipped through the
  Mac App Store) and `xFractal-iOS` (iPhone/iPad). Both are product `xFractal` with bundle ID
  `ch.arizonasoftware.xfractal` (one universal purchase).
- `GalleryTests/` is the **iOS** test target (`xFractalGalleryTests`, hosted by the app): the preview-gallery scenarios
  (`GalleryFixtures.swift`, `GalleryScenarios.swift`) and their harness. `Tests/` stays the macOS logic tests.
- `xFractal.xcodeproj` is generated from `project.yml` by XcodeGen and is checked into git.
- `xFractal/Localizable.xcstrings`: one String Catalog for both apps. `AppStore/`: App Store descriptions, keywords,
  names, subtitles and screenshot slides. `scripts/`: gallery and Mac snapshot scripts. `planning/`: plans.

## Build and test

### Running the tests

```sh
buildlock --folder "$PWD/.build/DerivedData" -- \
  xcodebuild test -project xFractal.xcodeproj -scheme xFractal-MAS -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$PWD/.build/DerivedData"
```

The `xFractal-MAS` scheme's test action runs `xFractalTests` (82 tests, one of them the skipped Mac window capture;
hosted by the Mac app; no simulator). Tests must pass before any commit. Without a signing team the app is signed ad
hoc and the tests still run; if signing fails anyway, add `CODE_SIGNING_ALLOWED=NO`. Without `buildlock` on `PATH`,
run the `xcodebuild` part alone. The `/develop` skill's gates build once (`build-for-testing`) and run with
`test-without-building`, and add the warnings gate.

### Preview gallery

```sh
scripts/snapshot-gallery.sh                 # all 26 scenarios -> previews/en/index.html (gitignored), then CHECK OK
scripts/snapshot-gallery.sh --only "julia"  # a subset
scripts/snapshot-gallery.sh --device ipad   # the same scenarios on the iPad Pro 13-inch -> previews/ipad/en/ (Controls are columns there)
scripts/snapshot-gallery.sh --device duo    # all 26 scenarios on the iPhone Duo -> previews/duo/en/
scripts/snapshot-gallery.sh --only "…" --lang fr,de,it,es,pt-BR,ja,tr,ar,he # store captures only (/app-store-screenshots) -> previews/fr/, …
scripts/snapshot-mac.sh                     # the Mac window (Tests/MacWindowSnapshotTests, off screen, 2x) -> previews/mac/en/
python3 -m unittest discover -s scripts -p 'test_preview_gallery.py'   # page and check contract tests
scripts/test_snapshot_gallery.sh                                      # lifecycle tests with stub simctl, simpool and buildlock
```

- The plain gallery tests run with every gallery run.
- The simulator is leased from the machine-wide pool (`simpool acquire --spec iphone`: iPhone 17 Pro, iOS 27.0) and given
  back with `simpool release` when the script ends, on success, failure or interrupt; both `xcodebuild` commands run under
  `buildlock`. The script never boots or shuts down a simulator itself. Without `simpool`/`buildlock` on PATH (a
  contributor's Mac) it falls back to its own **xFractal Agent** simulator, which it creates, boots and shuts down.
- An `--only` run checks every scenario: in a fresh checkout run the whole gallery once first.
- The gallery is English only; `--lang fr,de,it,es,pt-BR,ja,tr,ar,he` exists for the App Store screenshots alone, which
  render just the slides' captures (`--only`: the script refuses another language without it) into `previews/fr/`, …
  iPhone by default; `--device ipad` renders every scenario on the pool's iPad Pro 13-inch (M5) into its own gallery
  (`previews/ipad/en/`, its own simulator without the pool). The "iPhone Duo · inner display" group (9 scenarios) and the
  `--device duo` pass (`previews/duo/en/`, all 26 scenarios, folded outer display) are explained in the
  `/preview-gallery` skill.
- The Mac app has no simulator: `scripts/snapshot-mac.sh` runs `MacWindowSnapshotTests` (skipped in normal runs), which
  mounts the real `ContentView` in a window never put on screen and draws it with `CARenderer` at 2x (title bar, HUD,
  panel). The fractal is a `CAMetalLayer`, which `CARenderer` skips, so it is painted with the app's own `encodeFrame`.
  The sandboxed host's container is closed to other processes: the PNGs come back as base64 on stdout. Needs a Retina
  display.
- The plan and its outcome (measurements, thresholds, findings): `planning/gallery-scenarios-plan.md`.

### String Catalog

```sh
catalog-sync              # builds both apps, adds new keys, marks unused ones stale
catalog-sync --delete-stale
catalog-sync --check --skip-build   # "catalog unchanged" before committing
```

## Conventions

- **TDD by default.** For any change that touches non-trivial logic, red → green → refactor:
  1. **Red.** Write a failing test in `Tests/` that captures the desired behavior. Run the test target and confirm it
     fails for the right reason.
  2. **Green.** Write the smallest production-code change that makes the new test pass. Don't generalize ahead of the test.
  3. **Refactor.** Once green, clean up — extract helpers, simplify, dedupe — keeping the suite green between each step.

  When fixing a bug, the failing test must reproduce the bug *before* the fix is applied. When a behavior is hard to
  express as a test (UI gestures, Metal rendering), say so explicitly and fall back to manual verification — but check
  first that the underlying logic isn't actually pure math that *could* be lifted into `FractalMath.swift` and tested.
- **Project regeneration.** After editing `project.yml`, run `xcodegen generate` and commit the regenerated project with
  it; never edit the project in Xcode without carrying the change into `project.yml`. If Xcode applies new build
  settings (e.g. "Update to Recommended Settings"), bake them into `project.yml` so they survive regeneration.
- **Platforms.** Xcode Cloud workflows use the scheme names `xFractal-MAS` and `xFractal-iOS`: never rename them. Use
  `#if os(macOS)` / `#if os(iOS)` for platform-specific UI; keep math platform-agnostic.
- **Languages.** English (source), French, German and Italian (the Swiss four), plus Spanish (`es`), Brazilian
  Portuguese (`pt-BR`), Japanese (`ja`), Turkish (`tr`), Arabic (`ar`) and Hebrew (`he`). Every user-facing string goes
  in `xFractal/Localizable.xcstrings` with all nine translations; `LocalizationTests` fails on a key that misses one,
  and on a stale key. Math notation and bare numbers use `Text(verbatim:)` so they stay out of the catalog. After
  adding or changing strings, sync the catalog headless (`catalog-sync`, above) and translate the new keys.
- **App Store page languages.** Eleven: en-US, fr-FR, de-DE, it, es-ES, es-MX, pt-BR, ja, tr, ar-SA and he (both
  Spanish pages share the `es` text and captures). Descriptions, keywords, names and subtitles are in `AppStore/` (the
  `/release` skill loads them).
- **Preview gallery, no `#Preview`.** The iOS app has no `#Preview`: every screen state is a scenario in
  `GalleryTests/GalleryFixtures.swift` and `GalleryScenarios.swift`, rendered light and dark by one hosted snapshot test
  (`SnapshotGalleryTests`, skipped unless `XFRACTAL_SNAPSHOT_DIR` is set, so normal runs and Xcode Cloud skip it).
  Never add a `#Preview`. A new or changed screen needs a scenario; the `/preview-gallery` skill has the rules, the
  limits and the calibrated checks.

## Release

`RELEASING.md`: `/testflight` sends both apps to TestFlight, `/release` publishes to the App Store. There is no Sparkle
and no DMG any more. App Store screenshots, header and search-results artwork (`app-store-screenshots`,
`/app-store-screenshots`): [docs/app-store-screenshots.md](docs/app-store-screenshots.md).

## Don't touch

- `docs/appcast.xml` is frozen for the installed 1.0 DMG copies: never edit it (see `RELEASING.md`).
- The scheme names `xFractal-MAS` and `xFractal-iOS` (Xcode Cloud uses them).
