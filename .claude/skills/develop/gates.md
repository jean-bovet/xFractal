# /develop gates — build, test, red proof, warnings

The gates every `/develop` step and landing runs, in the worktree. An implementer reads this file only
(not `SKILL.md`). The simulator pool, `buildlock`, parallel-testing and four-minute-wait rules are the
global rules; this file adds what is specific to the gates.

## Two tiers

**Step gates** run after each plan step and each fix round: the build, the warnings check and the unit
tests, never the preview gallery: a step that adds or changes scenarios only checks that they compile,
and the look is shown to Jean at the landing gate. Step gates never run the UI tests, not even for a
step that touches what they drive (navigation, titles, accessibility identifiers, launch fixtures): the
landing gate catches what they would. A brief that asks a step gate or a fix round for them is
overruled: they wait for the landing gate.

The **landing gate** runs **once per plan**, on the tree handed back, on a fresh `<dd>`: the quick tier
(build, warnings check, unit tests) plus only the UI suites the change touches, on every device or
screen size the change affects; plus, before landing, the gallery shown to Jean (the scenarios
concerned, or in full) when the look changes. The plan's test list names the suites and devices. Step
gates never replace it. It starts only once the last implementation review round and its fixes are
committed, never while a round may still change the code. A later tree (a fix round, the rebase, the
squash on `main`) reruns the landing gate when it changed anything outside the docs-only paths
(`git diff --name-only <the commit the last landing gate passed on>` answers); a docs-only change runs
the docs-only checks below.

The **full run** (every test suite on every device, coverage, the full gallery) is not part of
`/develop`: it runs only in `/testflight` § Test gate, before every build (in a repo without
`/testflight`, in `/release` § Test gate). Send test builds often, so a red full run spans few plans.

## How the gates run

- **Build folders.** Step gates reuse ONE build folder for the whole plan (`<dd>`, e.g.
  `/private/tmp/<id-slug>-dd`, created once), so every build after the first is incremental. The
  landing gate uses a fresh `<dd>`, which also re-surfaces warnings an incremental build would not
  recompile. Logs go to a new scratch directory for every gate run.
- **Build once, test without building.** Where the platform allows it, a gate builds the tests once
  for a generic destination (`xcodebuild build-for-testing`) and runs them with `test-without-building`
  on the leased simulator, so the tree compiles once and the lease is held only while tests run. Any
  later run on the same tree (another test plan, a rerun) reuses those products. An app-hosted test
  target (a test bundle that runs inside the app, on the Mac too) follows the same rule:
  `build-for-testing` once per step, every rerun and red proof through
  `test-without-building -only-testing:<Target>/<Class>`, never a plain `xcodebuild test`. **A scheme
  with several test plans** names the gate's plan on both commands (`-testPlan <Plan>`): without it
  `build-for-testing` builds every plan, and `test-without-building` can fail with "Failed to create a
  bundle instance" before any test runs.
- **Locks.** Use the repo's scripts or build wrapper when it has them; otherwise every `xcodebuild`
  runs under `buildlock` (the global rules). A `test-without-building` run takes the folder's lock but
  no build slot: `buildlock --folder <dd> --no-slot -- xcodebuild test-without-building …`. An
  app-hosted Mac test run also holds `buildlock --folder ~/Library/Containers/<bundle id> --no-slot`,
  so two worktrees never host the real app (its sandbox container) at once.
- **Simulators.** Lease one from the pool for each gate run (the global rules; or the repo's scripts
  do it) and release it in a trap that also clears the app:
  `trap 'simpool release "$udid" --app <bundle id>' EXIT`, so the next holder doesn't inherit the
  running app. Don't hold a lease across gates. Every simulator test run passes
  `-parallel-testing-enabled NO -collect-test-diagnostics never`: without the second flag every
  failing test, so every red proof, collects a simulator diagnostics report for minutes; the gates
  read the log, never that report. To debug a failure nobody can explain, rerun that one test without it.
- **Keep the Mac awake.** Every long gate run holds a *system* sleep assertion (`caffeinate -s`; `-i`
  alone is not enough, and xcodebuild's own assertion lets a sleeping Mac stall UI tests into
  "Timed out while synthesizing event"). A gate script does it itself, in either form: it re-executes
  itself once under `caffeinate -is` (a guard variable such as `<REPO>_CAFFEINATED` so it happens once;
  `"$@"` and the exit status kept; no re-exec, one notice line, when `caffeinate` is missing), or it
  starts `caffeinate -dims -w $$` in the background for its own lifetime. Where the gate is a list of
  commands rather than a script, or a script that does neither, each long command runs as
  `caffeinate -is <command>` (`caffeinate -is buildlock --folder <dd> -- xcodebuild test …`). A script
  that re-executes itself has script tests for the re-exec, argument boundaries, the missing tool and
  signals.
- **Wait in slices** (the global four-minute rule): a build, a test run, the gallery or a Codex round
  starts in the background with its output in a log, checked every four minutes at most (a `Monitor`
  until-loop with that timeout, or a background command looked at on that cadence), reading the
  summary lines only.
- **Reading results.** Read the **exit status** and the summary line of every command; an empty grep
  is clean only if the command succeeded. The number of tests run is part of the result: zero is red,
  and a count that shrinks needs an explanation (a conditionally disabled test counts as skipped).
  Swift Testing app tests run through xcodebuild print `Executed 0 tests, with 0 failures`, which means
  nothing: read `Test run with N tests in M suites passed`. Only XCTest bundles print a real
  `Executed N tests`. A gate that refuses to run (Mac UI tests on a locked screen, say) is reported as
  not run, an owed check, never as green.

## Red proof

A regression test is proven red without its fix before it goes green: commit the fix first, revert
only the fix's lines, run the test and see it fail, restore with `git checkout -- <file>` (never a
hand-written inverse), then confirm `git status` is clean and grep the tree for any temporary marker.
A red-proof run builds incrementally in the step gates' `<dd>` and runs only the test class concerned,
never the whole suite: the step and landing gates run the rest. Build once applies: an Xcode test
target is rebuilt with `build-for-testing` and run with
`test-without-building -only-testing:<Target>/<Class>`; plain `xcodebuild test -only-testing:…` only
where the platform does not allow building once; a Swift package runs `swift test --filter <Class>`.
No version bump during feature work.

## Warnings

Fix every warning the branch touches or reveals, including ones that predate it. Deprecations are
fixed, never silenced (`@available`, `#warning`, suppression flags); if the fix conflicts with a
documented decision, update that decision's comment. A build-only warnings check uses
`xcodebuild -target <target>` with its own `SYMROOT` — never a scheme, so the shared build (or a
running app the scheme drives) stays untouched — and `COMPILER_INDEX_STORE_ENABLE=NO` on the command
line: without a derived-data path Xcode emits an empty `-index-store-path` and clang's hardening flag
turns into a bare warning. Keep that flag off the project files, so Xcode still indexes.

The warnings check compiles **every platform target that compiles the changed sources**, not only the
target whose folder changed: a shared package or framework change also builds the iOS (or other)
target, because a platform-conditional member called outside its `#if` passes every Mac gate and fails
only the CI archive of the other platform.

## Docs-only changes

No code: skip the build gates. `git diff --check`, every link and citation still resolves, and the
working agreement, plans index and README stay consistent.

## String Catalogs

A repo with a String Catalog: `catalog-sync --delete-stale`, then translations via the Xcode MCP
`StringCatalogEdit` (open the worktree's project in Xcode first, not the main checkout's), then
`catalog-sync --skip-build` once (it re-sorts the keys the editor wrote) and `catalog-sync --check
--skip-build`; commit the catalog with the step. This replaces an Xcode GUI build. A repo adopts it only
after `catalog-sync --check` on its main reports "catalog unchanged"; it needs the repo's
`catalog_project`/`catalogs` registered in the repos manifest catalog-sync reads, a scheme named like the target, an iOS Simulator
destination and `SWIFT_EMIT_LOC_STRINGS = YES` on each catalog target (it refuses otherwise). `--check`
still builds, and `--skip-build` reuses a possibly stale build. catalog-sync builds into its own private
folder and takes no `buildlock` slot, but it is still a build: never run it alongside another one. A
right-to-left language (Hebrew, Arabic) also runs through `docs/right-to-left.md`, next to the tools the global
rules name (digits, the minus sign, what must not mirror, the gallery's direction-aware tests).

## This repo's gates

- **Tests first (TDD, `AGENTS.md`):** red → green → refactor. A failing XCTest in `Tests/` (the macOS
  `xFractalTests` target) first, run and seen failing for the right reason, then the smallest change,
  then refactor with the suite green. A bug fix starts with a test that reproduces it. Logic that seems
  untestable (gestures, Metal) is first checked for pure math that can move into `FractalMath.swift`;
  what truly is not testable is named in the plan and verified by hand (an owed check).
- **Project:** `xcodegen generate` after any `project.yml` change, and commit the regenerated
  `xFractal.xcodeproj` with it (the project is checked in). Settings Xcode applies go into `project.yml`.
- **Test gate:** the scheme, project and destination of `AGENTS.md` § Running the tests, built once and run
  without building (that section shows a plain `xcodebuild test`, which re-links and relaunches the host app
  on every run), with `<dd>` as the build folder. `xFractalTests` is hosted by the sandboxed Mac app, so the
  run also holds the app's container lock (`buildlock --folder ~/Library/Containers/ch.arizonasoftware.xfractal --no-slot`):

  ```sh
  caffeinate -is buildlock --folder <dd> -- \
    xcodebuild build-for-testing -project xFractal.xcodeproj -scheme xFractal-MAS -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath <dd>
  caffeinate -is buildlock --folder ~/Library/Containers/ch.arizonasoftware.xfractal --no-slot -- \
    buildlock --folder <dd> --no-slot -- \
    xcodebuild test-without-building -project xFractal.xcodeproj -scheme xFractal-MAS -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath <dd>
  ```

  The build is green on `** TEST BUILD SUCCEEDED **`; the run is green on `** TEST EXECUTE SUCCEEDED **` with
  the test count (82 today, one of them skipped, more with each new test); a `FAILED`
  line, a lower count or zero tests is red. macOS only, no simulator. Without a signing team the
  app is signed ad hoc; if signing still fails, add `CODE_SIGNING_ALLOWED=NO`. Red proof: the same two
  commands, the second with `-only-testing:xFractalTests/<Class>` added.
- **Warnings gate:** zero warnings in our own sources (Swift and `Shaders.metal`), both platforms, each
  target built with `-target` (never a scheme):

  ```sh
  caffeinate -is buildlock --folder <dd> -- xcodebuild -project xFractal.xcodeproj -target xFractalTests -configuration Debug SYMROOT=<dd>/build-mac COMPILER_INDEX_STORE_ENABLE=NO build
  caffeinate -is buildlock --folder <dd> -- xcodebuild -project xFractal.xcodeproj -target xFractalGalleryTests -sdk iphonesimulator -configuration Debug SYMROOT=<dd>/build-ios COMPILER_INDEX_STORE_ENABLE=NO build
  ```

  (each test target builds its host app: `xFractal-MAS`, `xFractal-iOS`). Read `grep -E '(warning|error):'`
  of each log, after checking the exit status.
- **Landing gate:** the test gate and the warnings gate above on a fresh `<dd>`; no UI suites (xFractal has
  none, so no device to pick); the gallery when the look changes (below).
- **Full run:** the test gate and the full `scripts/snapshot-gallery.sh`: `/testflight` § Test gate only. No
  coverage command.
- **Running-app check:** `xFractalTests` and `scripts/snapshot-mac.sh` are hosted by the Mac app: the check
  is `pgrep -x xFractal`.
- **Gallery:** `scripts/snapshot-gallery.sh` (the `/preview-gallery` skill), never in a step gate (a step only
  checks that its scenarios compile); when the look changes, the landing gate renders the scenarios concerned
  (`--only <scenarios>`, or in full: a fresh checkout needs one full run first) and shows them to Jean before
  landing; the full gallery runs in `/testflight`. A new or changed screen state needs its scenario
  in `GalleryTests/GalleryFixtures.swift` and `GalleryScenarios.swift`. It leases its simulator from the
  pool and runs its builds under `buildlock` (its own DerivedData): never call `xcodebuild` or `simctl`
  around it. It keeps the Mac awake on its own (`caffeinate -dims -w $$`, bound to the script's process), so it
  runs without a `caffeinate` prefix. Must end with `CHECK OK`. Never add a `#Preview`.
- **Script tests:** a change under `scripts/` also runs
  `python3 -m unittest discover -s scripts -p 'test_preview_gallery.py'` and
  `scripts/test_snapshot_gallery.sh`.
- **Frozen appcast:** `git diff --exit-code main -- docs/appcast.xml` must be clean.
- **String Catalog:** `xFractal/Localizable.xcstrings` (one catalog for both apps); the `catalog-sync`
  commands are in `AGENTS.md` § Languages. The translations are French, German, Italian, Spanish, Brazilian
  Portuguese, Japanese, Turkish, Hebrew and Arabic. `LocalizationTests` (in the test gate) fails on a key
  missing a translation and on a stale key.
