# iPhone Duo: inspector controls, peek off the fold, gallery and App Store screenshots

Status: implemented on main 2026-10-25, revision 3. Branch `iphone-duo` (worktree `.claude/worktrees/iphone-duo`, from `main`).

Fixes the important findings of the iPhone Duo audit and extends the preview gallery and the App Store screenshots to
the Duo. Two steps land in `~/GitHub/maestro` (its own commits): a simulator spec and a device frame. Not in scope: the
hinge-angle API, arrangement views, Mac changes beyond keeping the Mac build green, the `/release` skill text.

## Revision history

- **Revision 3** (2026-10-25), Codex plan review round 2 (1 blocker, 2 should-fix, all accepted): the synthetic gained
  reference is placed at the MTKView's window frame so `testPureGainOutsideTheScrimBandIsRejected` holds beside a
  column too (B1); `PresentationForm` is a computed property of the current traits with a `settlePresentation()`
  refresh, asserted after every transition of test 13 (SF2); a hosted observable wrapper drives
  `[hinge] → [] → [hinge]` through the production placement path, test 16, so only the OS's delivery of real reserved
  regions stays manual (SF3).
- **Revision 2** (2026-10-25), Codex plan review round 1 (6 blockers, 4 should-fix, 2 simpler; all accepted but one
  part of blocker 6, rejected below): the peek offset is derived from the capsule's size and the container, never from
  its own shifted frame (B1); `peekShift` is a free function choosing among candidate placements validated against
  every region (B5, S11, S12); the harness follows the *actual* presentation (column or sheet) so the iPad pass keeps
  working and is part of the gate (B2); the reference comparison maps the window region into MTKView coordinates (B3);
  the slide-to-fixture mapping is complete, 26 scenarios (B4); no absolute path in the plan (B6, part); the Duo pass
  asserts the outer display before labelling captures (SF7); a hosted compact → regular → compact test with the
  controls open, and setters that only write for their own form (SF8); the compact test asserts the opening height and
  the undimmed detent (SF9); the capsule is judged by the rendered-image detector and a stability pass (SF10).

### Review findings rejected (with the rationale, so the next round does not re-raise them)

- **B6, "do not name the private maestro repository or its paths; keep sibling-repo details in a private companion
  document."** Rejected for the naming: xFractal's own `AGENTS.md` (public) already names `~/GitHub/maestro/bin/catalog-sync`
  and the maestro tools by path, and `.claude/skills/app-store-screenshots/SKILL.md` names `app-store-screenshots`; the
  repo's established practice is to name maestro and its `~/GitHub/maestro/...` paths, and the two maestro steps must
  stay in this plan because the gallery and screenshot steps depend on them. Accepted for hygiene: the working
  agreement forbids absolute `/Users/...` paths and personal data in a public repo; the one absolute path the draft
  carried (a CoreSimulator profile under `/Library/Developer/...`, not personal but absolute) is now described, not
  spelled; every other path is `~/GitHub/...` or repo-relative.

## Facts established while planning

- **Device.** `xcrun simctl list devicetypes`: `iPhone Duo` (`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`, model
  `iPhone19,4`, `minRuntimeVersionString` 27.1.0). Installed runtimes: iOS 26.5, 27.0, 27.1; only iOS-27-1 supports the
  Duo. Its device-type profile (`capabilities.plist` of the `iPhone Duo.simdevicetype` bundle in CoreSimulator's
  device-type profiles) lists two integrated displays, both `scale 3`: the outer `1398 x 2034` px (466 x 678 pt; corner radii UL 8, UR 59, LL 8,
  LR 59: the left edge is the hinge side) and the inner `2007 x 2853` px with `nativeOrientation 270` (669 x 951 pt, so
  951 x 669 pt in landscape). `DeviceSupportsDynamicIsland` is true; the island's position on either display is not
  in the profile. `simctl io <udid> enumerate` on a booted Duo shows both framebuffers powered on.
- **No fold command.** `xcrun simctl help` (Xcode 27.1, build 27A9275) has no posture, fold, hinge or display
  subcommand; `simctl ui` offers only appearance, increase_contrast and content_size; `strings` on `simctl` and
  `CoreSimulatorService` has no "posture"/"fold"/"hinge". Simulator.app (the GUI, where a posture menu would live) is not
  under `Xcode.app/Contents/Developer/Applications` on this Mac and is not running: it could not be inspected. The
  gallery therefore cannot fold or unfold a simulator; it uses fixed window sizes, as the "Regular width" cards do today.
- **The SwiftUI API.** iOS 27.1 SDK, `SwiftUICore.swiftmodule/arm64-apple-ios-simulator.swiftinterface`:
  `@available(anyAppleOS 27.1, *) public struct ReservedRegion : Equatable, Hashable, Identifiable, Sendable` with
  `id`, `kind`, `frame: CGRect`, `margins: EdgeInsets`, `isActive: Bool`; `ReservedRegion.Kind.occlusion` and
  `.division`; `ReservedRegion.QueryOptions.includeInactive`; on `GeometryProxy`:
  `@available(anyAppleOS 27.1, *) public func reservedRegions(kind: ReservedRegion.Kind, options: ReservedRegion.QueryOptions = [], layoutDirectionBehavior: LayoutDirectionBehavior = .mirrors) -> [ReservedRegion]`.
  UIKit mirrors it (`UIView.h:757-763`, `reservedRegionsOfKind:options:`, `API_AVAILABLE(ios(27.1))`,
  `NS_REFINED_FOR_SWIFT`): read-only, a test cannot inject a region. The frame "includes the margins" around the
  reserved rect "for interactive content" (`UIViewReservedRegion.h:32-35`). Deployment target is iOS 17.0
  (`project.yml:4-6`), so the call sits behind `if #available(iOS 27.1, *)`.
- **App Store Connect.** The legacy `ScreenshotDisplayType` enum (`appScreenshotSets`, which `app-store screenshots`
  uses, `~/GitHub/maestro/bin/app-store:553-582`) has no Duo value; Apple's OpenAPI spec (downloaded 2026-10-25) lists
  it only in the App Asset Library: `AppAssetLibraryDisplayClass` = `IPHONE_DUO` (with `IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY`
  and the other classes), placement type `APP_SCREENSHOT`, image category `APP_SCREENSHOTS_AND_PREVIEWS`; the specs
  (sizes, `specId`) come from `/v1/appAssetLibraryRefData`, which `app-store creative --refdata` already prints. The
  screenshot specifications page lists the Duo sizes `1398 x 2034` / `2034 x 1398` (outer) and `2007 x 2853` /
  `2853 x 2007` (inner), "required for apps using the iOS 27.1 SDK or later starting April 2027", with an
  "optimized for iPhone Duo" badge. The upload path is an open decision (below).

## Problem with evidence

1. **The controls are a sheet in every size class.** `xFractal/ContentView.swift:52-60`: `.sheet(isPresented: $showingSheet)`
   with `presentationDetents([.height(260), .medium, .large])` and `presentationBackgroundInteraction(.enabled(upThrough: .height(260)))`.
   On the Duo's inner display (regular width in every pose) and on iPad a sheet covers the board; Apple's HIG asks for
   the same controls across poses and a trailing column where the width allows. Nothing in `xFractal/` reads
   `horizontalSizeClass` (grep: no hit).
2. **The peek capsule sits on the fold.** `ContentView.swift:33-50`: `ZStack(alignment: .bottom)`, the capsule is
   `iOSPeek.padding(.bottom, 12)`, centred only by the alignment. In the landscape inner display (951 x 669 pt) its
   centre is x = 475.5, the hinge. Apple: keep interactive elements out of the fold; custom views read
   `GeometryProxy.reservedRegions`. No `GeometryReader` or `#available` exists in `xFractal/` today.
3. **The gallery knows two sizes and one scale.** `GalleryTests/GalleryFixtures.swift:7-18` `GallerySize { phone, regularWidth }`
   (834 x 1210, "an approximation, not iPad coverage"); `GalleryHarness.swift:355` `format.scale = 2` (and
   `GalleryScenarioTests.swift:176`); `scripts/snapshot-gallery.sh:53-56` accepts `--device iphone|ipad` only, with the
   fallback runtime `iOS-27-0` (`:45`); `scripts/preview-gallery.py:445-459` requires the capsule within
   `PEEK_CENTER_TOLERANCE = 40` pt of the centre, so a capsule moved off the fold fails the check.
4. **No Duo screenshots.** `AppStore/screenshots.json` (`APP_IPHONE_67`, 1320 x 2868), `screenshots-ipad.json`,
   `screenshots-mac.json`. The renderer's frames (`~/GitHub/maestro/tools/app-store-screenshots/render.mjs:50-57`) are
   `.phone` 804 x 1748 px fixed, `.phone.ipad`, `.phone.window`; `layout.mjs:69-88` `phoneHTML` draws any unknown `device`
   as an iPhone. The `.screen` is `background-size: cover` (`render.mjs:58`), so a 466 x 678 pt capture (aspect 0.69) in
   the 804 x 1748 frame (0.46) would lose a third of its width: the existing iphone frame does **not** fit the outer
   display (checked, as asked).
5. **simpool has no Duo spec.** `~/GitHub/maestro/global/simpool.conf:15-19`: five specs, all iOS-27-0 or watchOS-27-0.
6. **The store build was compiled with the iOS 27.0 SDK**; Xcode Cloud's "Latest Release" is now 27.1. A new build is
   needed for the Duo optimisation and the badge; nothing in this work bumps the version.

## Design

### 1. Controls: one `.inspector`, two forms (ContentView.swift)

Replace `.sheet(isPresented: $showingSheet)` (`ContentView.swift:53`) with `.inspector(isPresented: $showingSheet)`
(iOS 17, no availability guard) carrying the **same** `iOSControlsSheet` content and the same three presentation
modifiers. SwiftUI presents an inspector as a trailing column in a regular horizontal size class and as a sheet in a
compact one, and applies `presentationDetents`, `presentationDragIndicator` and `presentationBackgroundInteraction` to
that sheet form (WWDC23 "Inspectors in SwiftUI"). One declaration gives:

- compact width (every iPhone, the Duo's outer display): today's sheet, detents 260/medium/large, board interactive
  under the opening detent;
- regular width (the Duo's inner display in every pose, iPad): a trailing column holding the same `Form`, the board
  pannable beside it;
- fold/unfold while open: SwiftUI re-presents the same content in the other form; `showingSheet` stays true, nothing
  is torn down by us, no second binding to keep in step.

Same hierarchy in both forms: `NavigationStack { Form … }` with the inline "Controls" title and the "Done" button
(`ContentView.swift:443-449`), which closes either form. The `sheetProbe` background (`:55`) stays where it is. Column
width: SwiftUI's default first; the portrait inner card (669 pt wide) decides whether `.inspectorColumnWidth(…)` is
needed (a decision for the implementer, recorded as a deviation if set).

**Fallback, decided by step 2's red tests (test 9), not by taste:** if the compact inspector does not honour the
custom `.height(260)` opening detent (sheet height) or the background interaction (`largestUndimmedDetentIdentifier`),
or the harness cannot drive its detents through `host.presentedViewController.sheetPresentationController`
(`GalleryHarness.swift:131-135, 196-203`), keep `.sheet` for compact and add `.inspector` for regular with two derived
bindings over the one `showingSheet` (`@Environment(\.horizontalSizeClass)`, iOS only). Each binding's setter writes
only while its own form is current: `Binding(get: { showingSheet && horizontalSizeClass == .compact }, set: { if horizontalSizeClass == .compact { showingSheet = $0 } })`
and the regular twin. Without that guard the outgoing presentation's dismissal during a size-class change would write
`false` into the shared state and close the controls in the new form. Test 13 (a hosted compact → regular → compact
transition with the controls open) is red against the unguarded setters and holds for both designs.

No persisted state changes: `showingSheet` is view `@State` (`ContentView.swift:11`), `StateStore` keys
`fractals.viewState.v2` / `fractals.journal.v2` (`FractalState.swift:170-171`) are untouched.

### 2. Peek off the fold: pure math in FractalMath, one GeometryReader in the view

**Math** (`xFractal/FractalMath.swift`, a free function beside `panCenter` and `anchoredZoomCenter` — there is no
`FractalMath` namespace, the file holds free functions; platform-agnostic, CoreGraphics only):

```swift
/// The horizontal shift that places `capsule` (its unshifted frame, container coordinates) clear of every rect in
/// `regions`: 0 when it already is; else the smallest trailing (positive) shift whose placement stays inside
/// `container` and overlaps no region; else the smallest leading (negative) such shift; else 0 (nothing fits:
/// the capsule stays where it is, no worse than today).
func peekShift(capsule: CGRect, clearing regions: [CGRect], in container: CGSize) -> CGFloat
```

Candidate evaluation, no retry loop: the candidates are `0` and, for every region, `region.maxX - capsule.minX`
(placed just past its trailing edge) and `region.minX - capsule.maxX` (just before its leading edge). A candidate is
valid when the shifted capsule lies within `0...container.width` and overlaps no region with positive area (touching
edges are clear). Pick `0` if valid; else the smallest valid positive candidate; else the valid negative candidate of
smallest magnitude; else `0`. Every candidate is checked against *every* region, so a placement can never land in a
region already cleared (the review's case: container 100, capsule x 40...60, regions x 45...55 and 70...95 → the
trailing candidates 15 and 55 and the leading candidate 10 are invalid, the leading candidate −15 (x 25...45) is
valid → −15; test 6). RTL: regions come mirrored by `layoutDirectionBehavior: .mirrors` and the offset is applied in
the same mirrored space, so "trailing = +x" holds in both directions without a special case.

**View** (`ContentView.swift`, inside `#if os(iOS)`): the input to the math is the capsule's **unshifted** frame,
derived — never measured through the offset it feeds (a measured frame would include the shift: 130 on the first pass,
then "clear" → 0, then back onto the hinge, an oscillation). `iOSPeek` gets
`.onGeometryChange(for: CGSize.self, of: \.size) { peekSize = $0 }` (iOS 16+; a size does not change with an offset)
and `.offset(x: shift)`; the ZStack's `.background { GeometryReader { proxy in Color.clear … } }` publishes
`proxy.size` (the ZStack's frame: the safe area, inside which the ZStack bottom-centres the capsule) and the active
regions in that same space. The unshifted frame is then
`CGRect(x: (container.width - peekSize.width) / 2, y: container.height - 12 - peekSize.height, size: peekSize)` (the
12 pt is the existing bottom padding, `ContentView.swift:49`), and `shift = peekShift(capsule:clearing:in:)`. With
no region the function returns 0 and the capsule is exactly where it is today; when the regions go inactive (fully
open) the input changes only through the region list, so the shift returns to 0 in one pass.

```swift
private func activeFoldRegions(_ proxy: GeometryProxy) -> [CGRect] {
    if let foldRegionsOverride { return foldRegionsOverride }          // gallery hook, nil in the app
    if #available(iOS 27.1, *) {
        return proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
    }
    return []
}
```

`.division` is the kind Apple describes for a fold ("a region where an element should divide into two"); an inactive
region (fully open) is filtered out, so the capsule stays centred on the open inner display and on every non-folding
device. The implementer may instead put one `GeometryReader` at the root if the background approach proves awkward;
the gallery scenarios are the arbiter. Animate the offset with the default animation so a fold does not snap the
capsule.

**Gallery hook, like `sheetProbe`:** `ContentView.init(…, foldRegions: [CGRect]? = nil)` stored as
`foldRegionsOverride`, nil in the app (`xFractalApp.swift` passes nothing). Only the *source* of the rects is
injected; the offset math, the frame reading and the placement are the production path. The `reservedRegions` call
itself is verified by hand (owed check: a Duo simulator folded through Simulator.app, or a device), because no test
can produce an active region and `simctl` cannot fold.

### 3. Gallery: Duo sizes, a Duo pass, the shifted peek in the check

**Sizes** (`GalleryFixtures.swift:7-18`). `GallerySize` becomes `phone`, `duoInnerLandscape` (951 x 669),
`duoInnerPortrait` (669 x 951); `regularWidth` is **removed** (Jean allowed it): its two scenarios had one job, a
regular-width window on the phone simulator, and the Duo inner sizes do that job with real numbers. A computed
`forcesRegularWidth` (the two Duo inner cases) replaces the `== .regularWidth` tests in `GalleryHarness.swift:127-130`
and `:191-194` only where they **apply** the trait overrides (host, window, presented controller); nothing else in the
harness branches on the fixture size — the presentation form is read from the host's resulting trait (below), which
is also what the iPad's `.phone` mounts report. `scale`: 3 for the Duo inner sizes
(their store screenshots are edge to edge at 2853 x 2007), 2 otherwise; `capture()` (`:353-359`) and the blank image in
`GalleryScenarioTests.swift:176` read it. No `duoOuter` case: on a Duo simulator (booted folded) `.phone` **is** the
outer display, 466 x 678 pt from `UIScreen.main.bounds`, with its real safe areas, so every phone scenario doubles as an
outer-display scenario in the Duo pass — the "board + sheet on the outer display" cards are the existing Controls
scenarios there.

**Fixtures** (`GalleryFixtures.swift:179-219`): the two "Regular width (approximation)" entries become nine in group
"iPhone Duo · inner display". The six landscape ones are exactly the captures `AppStore/screenshots.json` uses
(`board-mandelbrot-first-launch`, `board-mandelbrot-deep-zoom-chromatic`, `board-newton`, `board-multibrot`,
`board-julia`, `controls-julia-large.dark`), so the inner screenshot set (Design 4) has every capture it names:

| scenario (slug) | size | state / journal | sheet | regions | fold |
|---|---|---|---|---|---|
| Duo inner · Landscape · Board · Mandelbrot · First launch | duoInnerLandscape | nil (default) | none | peek, fractal | — |
| Duo inner · Landscape · Board · Mandelbrot · Deep zoom · Chromatic | duoInnerLandscape | deepZoomChromatic | none | peek, fractal | — |
| Duo inner · Landscape · Board · Newton | duoInnerLandscape | newton | none | peek, fractal | — |
| Duo inner · Landscape · Board · Multibrot | duoInnerLandscape | multibrotHot | none | peek, fractal | — |
| Duo inner · Landscape · Board · Julia | duoInnerLandscape | juliaCold | none | peek, fractal | — |
| Duo inner · Landscape · Controls · Julia | duoInnerLandscape | juliaB, pair(julia, juliaB) | opening | sheet, fractal | — |
| Duo inner · Portrait · Board · Mandelbrot · Deep zoom | duoInnerPortrait | deepZoom | none | peek, fractal | — |
| Duo inner · Portrait · Controls · Mandelbrot | duoInnerPortrait | mandelbrotA | opening | sheet, fractal | — |
| Duo inner · Landscape · Board · Folded · Mandelbrot | duoInnerLandscape | mandelbrotA | none | peek, fractal | `CGRect(x: 455.5, y: 0, width: 40, height: 669)` |

17 phone scenarios + 9 = **26 scenarios, 52 images per pass** (the phone ones also render on the iPad and Duo passes
at those devices' screen sizes, as today). `GalleryFixture` gets `foldRegion: CGRect? = nil`; `GalleryScenario.build`
(`GalleryScenarios.swift:28-45`) passes `foldRegions: fixture.foldRegion.map { [$0] }`. The fold rect is a stand-in
(hinge at x = 475.5, 40 pt wide including margins); the real geometry is read off a device later and the fixture
updated then.

**Harness: follow the actual presentation, not the fixture size** (`GalleryHarness.swift`). With `.inspector`, a
Controls scenario presents a sheet in compact width and a column in regular width — and `.phone` is regular on the
iPad pass (`UIScreen` 1032 x 1376 pt there), so the eight existing Controls scenarios become columns on
`--device ipad`. `GalleryMount` therefore exposes `form: PresentationForm` (`.sheet` or `.column`) as a **computed**
property of the current `host.traitCollection.horizontalSizeClass` — never cached, so a trait override changed after
mount (test 13) is seen on the next read — and a `settlePresentation()` (the presentation part of `settleLayout()`:
wait for the sheet, or for the column and no `presented`, then the stable frame) that the harness calls at mount and
a test calls after each transition. Every sheet-specific path branches on `form`:

- `settleLayout()` (`:176-206`): `.sheet` as today (wait for `presented`, detents, stable frame). `.column`: assert
  `presented == nil` (a sheet where a column is due fails with the reason), wait (5 s) for the Form's
  `UICollectionView` (`formRows()` already finds it, `:272`) laid out at the trailing edge beside a narrower MTKView,
  then `waitStableSheetFrame()` on the column's window frame (the "sheet frame" accessor returns the column's frame in
  `.column`). Detent requests (`.medium`, `.large`) are no-ops in `.column` and the manifest diagnostics record
  `detent: "column"`.
- `scrollSheetToEnd()` (`:244-275`): collects scroll views from the column's view instead of `presented?.view` in
  `.column` (the "whole form fits" branch at `:272` already exists for the iPad's large sheet).
- `settleScrim()` (`:223-235`) and the `scrimBand` (`:435-439`): `.column` has no scrim; skipped, band `0 ± 0.03`.
- `measureRegions()` (`:479-500`): `.sheet`/`.sheetGlass` use the column's frame in `.column`, inset 16 and clamped
  below the navigation bar as today. Kinds in `.column`: `.sheetGlass` is mapped to the column's kind (`.sheet` if the
  column is opaque, else `.sheetGlass`), one constant decided by `--measure` on the iPad and Duo passes and written to
  the manifest `kinds`, so the check judges what was rendered.
- `fractalRegion()` (`:364-377`): in `.column`, for every `sheet` value, the window minus the column
  (`x: 0 … column.minX - 4`) minus the bottom 140 pt (the board stays visible beside a column, also at `.large`).
- `validate()` (`:451-452`) scales the MTK-sized reference by `reference.width / window.bounds.width`, which is only
  right while the MTKView spans the window. It now converts the sampled window region into MTKView coordinates
  (`mtk.convert(region, from: window)`) and scales the reference by `reference.width / mtk.bounds.width`; today's
  scenarios are unchanged by this (MTKView == window), and a column no longer breaks the comparison (test 12).
- `gainedReference(of:gain:)` (`:237-250`, the synthetic image of the scrim tests) returns the MTK-sized reference
  with `scale = reference.width / window.bounds.width`, i.e. it assumes the MTKView spans the window too. It now
  composes a **window-sized** image at the capture scale, draws the gained reference into the MTKView's window frame
  (`mtk.convert(mtk.bounds, to: window)`) and leaves the rest black, so `validate` samples the same geometry from the
  synthetic image as from a capture. `testPureGainOutsideTheScrimBandIsRejected` (`GalleryScenarioTests.swift:278-299`,
  on `controls-mandelbrot-medium`) is kept for **both** forms: in `.sheet` as today; in `.column` (the iPad pass) the
  band is `0 ± 0.03`, so the inside gain is 1 and the brightening/dimming cases are ±0.1 around it; its assertions
  are unchanged.
- `GalleryScenarioTests`: the detent and scrim tests (`testDetentSelectionSettles`, `testMediumDetentScrimIsBounded`,
  the new test 9) run only when the mount's form is `.sheet` (`XCTSkip` otherwise, with the form in the message);
  `testScrollFindsVerticalForm` runs in both forms.

**Fold hook with an update path (test target only).** `ContentView(foldRegions: [CGRect]?)` stays a plain value in
the app. In `GalleryTests`, `BuiltScenario.makeView` takes the regions as well as the probe, and the mount hosts
`ContentView` inside a tiny wrapper `FoldHost: View { @ObservedObject var box: FoldRegionsBox; … body { make(probe, box.regions) } }`
(`FoldRegionsBox: ObservableObject` with `@Published var regions: [CGRect]?`, seeded from the fixture). Rebuilding
`ContentView(...)` from the same wrapper keeps its structural identity, so `@StateObject store`, `@State showingSheet`
and the peek state persist while `foldRegionsOverride` changes — the production `activeFoldRegions` → `peekShift` →
`.offset` path runs on every change. Two callers: the mount and test 16.

`GalleryRegionKind` and `GallerySheet` gain nothing; `PresentationForm` is the one new type, with two callers (the
harness and the manifest diagnostics). The iPad pass (`--device ipad`, `CHECK OK` and `--measure`) is part of step
2's gate, not an afterthought.

**Duo pass: assert the outer display before calling it that.** A leased Duo may be reused from the pool and the
lease does not establish posture. The script passes `TEST_RUNNER_XFRACTAL_SNAPSHOT_DEVICE="$DEVICE"`;
`SnapshotGalleryTests.testRenderGallery` reads `XFRACTAL_SNAPSHOT_DEVICE` and, for `duo`, fails before rendering
unless `UIScreen.main.bounds.size == 466 x 678` and a `.phone` mount's host trait is `.compact` ("the Duo simulator is
not folded: screen W x H"); the script prints the screen size with the timings. Other devices stay unchecked, as
today. The `pool_duo` stub test proves routing and lease cleanup only; this assertion covers the production capture
path.

**Manifest and check.** `SnapshotGalleryTests.ManifestEntry` (`:9-26`) gets `fold: {x,y,w,h}?` (pt) from the fixture.
`scripts/preview-gallery.py` peek rule (`:445-459`): when the entry has `fold`, the found capsule box (the existing
light-dark difference detector, `scripts/preview-luminance.swift`) must not intersect the fold rect, must lie on its
trailing side, and its centre must be within `PEEK_CENTER_TOLERANCE` of the minimal trailing position
(`fold.maxX + bw/2`); otherwise the centre rule stays as it is. New contract tests in
`scripts/test_preview_gallery.py`: a capsule clearing the fold on the trailing side passes; a centred capsule over a
fold fails ("capsule on the fold"); a capsule shifted twice the minimum fails. The scale is derived from the image
width as today (`:316`), so 3x images need no change there.

**Script** (`scripts/snapshot-gallery.sh`): `--device duo` joins `iphone|ipad` (`:53-56`, usage `:5`); a `duo` block
mirrors the iPad one (`:73-80`): `DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`,
`RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-1` (the fallback only; the runtime variable moves into the device
blocks), `SIM_NAME="xFractal Agent Duo"`, its own marker, `PREVIEW_GALLERY_OUT=…/previews/duo`. With the pool the
device name is already the spec (`simpool acquire --spec "$DEVICE"`, `:329`), so the Duo lease needs only the spec of
step 3. Artwork stays iPhone-only (`:383`). Lifecycle test `pool_duo` in `scripts/test_snapshot_gallery.sh` beside
`pool_ipad` (`:551-560`): leases `--spec duo`, page in `previews/duo/index.html`, no iPhone page, lease released;
the stub `simctl list` gains an iOS 27.1 runtime line only if the fallback path is tested for the Duo (it is not: the
pool path is).

**Skill and working agreement** (`.claude/skills/preview-gallery/SKILL.md`, `AGENTS.md`): 26 scenarios, groups Board /
Controls / iPhone Duo · inner display (fixed-size windows with the regular trait, on every pass; the Duo pass adds the
iOS 27.1 runtime and the real outer display for the phone scenarios, asserted before rendering; nothing folds), the
iPad pass's Controls cards are columns, `--device duo`, `previews/duo/`, the owed manual fold check. The "Regular width
is an approximation" paragraph is replaced.

### 4. App Store screenshots for the Duo

**Captures:** `scripts/snapshot-gallery.sh --device duo --only "<slides' captures>" --lang fr,de,it,es,pt-BR,ja,tr`
into `previews/duo/<lang>/`, the iPad path (`.claude/skills/app-store-screenshots/SKILL.md:33-40`).

**Configs** (two: the renderer has one `displayType`, `width` and `height` per config, `render.mjs`; a config per
display type is the existing convention):

- `AppStore/screenshots-duo-inner.json`: `"displayType": "IPHONE_DUO"` (the asset-library display class, shown only in
  the review page title, `render.mjs:126`), 2853 x 2007, the nine locales and the four slides of `screenshots.json`
  with the same headlines, each capture replaced by its landscape twin from Design 3 (every one exists, so
  `layout.mjs` `validate` passes): `hero` → `phones: []`,
  `backgroundImage: "duo-inner-landscape-board-mandelbrot-first-launch"` (the fractal edge to edge; the capture is
  2853 px wide at 3x; `art()` already localises a background image, `render.mjs:35-37`) with the headline over it;
  `deep-zoom` (`panels: 2`) → one `"device": "duo"` frame of `duo-inner-landscape-board-mandelbrot-deep-zoom-chromatic`
  lying across the seam; `families` → three `duo` frames of `duo-inner-landscape-board-newton`,
  `duo-inner-landscape-board-multibrot`, `duo-inner-landscape-board-julia`; `controls` → one `duo` frame of
  `duo-inner-landscape-controls-julia.dark`. New `style` transforms for a landscape canvas; `textStyle` narrows the
  text block for the landscape page.
- `AppStore/screenshots-duo-outer.json`: `"displayType": "IPHONE_DUO"`, 1398 x 2034, the same slides with the phone
  slugs from `previews/duo/` (`board-mandelbrot-first-launch`, …: the outer display is `.phone` there) and
  `"device": "duo-outer"` frames.

**Frames** (`~/GitHub/maestro/tools/app-store-screenshots/layout.mjs:69-88`, `render.mjs:50-69`): `phoneHTML`'s
generic branch emits `class="phone ${device}"` and draws the `.island` only for `iphone`; the `ipad` branch collapses
into it (it is already a class without an island: one branch fewer). Two CSS classes: `.phone.duo` — an open book,
screen 1902 x 1338 px (2x of 951 x 669), padding 24, radius 48 (the inner display's 55 pt radius at 2x, rounded to the
frame), a `.hinge` child: a 1-px vertical line at the centre with a faint gradient, drawn over the screen; and
`.phone.duo-outer` — the iphone rim with screen 932 x 1356 px (2x of 466 x 678), radii `16px 118px 118px 16px` (the
profile's 8 / 59 pt at 2x: hinge side left), no island. Tests in `layout.test.mjs` (next to `:88-92`): "an iPhone Duo
open book has a thin bezel, a hinge and no Dynamic Island"; "the Duo's outer display has its own frame class and no
island"; the existing iPad and iPhone tests stay green. `validate` (`layout.mjs:23-43`) additionally rejects an unknown
`device` (the set `iphone, ipad, window, duo, duo-outer`), with a test, so a typo no longer silently draws an iPhone.

**Upload:** not in this plan (open decision). `app-store screenshots --display-type` posts to `appScreenshotSets`,
whose enum has no Duo; the Duo lives in the App Asset Library, which `app-store creative` already drives for the header
and search assets (`bin/app-store:585-704`). A later maestro change teaches `app-store` an `APP_SCREENSHOT` placement
with display class `IPHONE_DUO` (spec ids from `appAssetLibraryRefData`); until then the two sets are rendered and
reviewed, not uploaded.

**Skill text:** `.claude/skills/app-store-screenshots/SKILL.md` gains the Duo commands and the "rendered, not uploaded
yet" note.

### 5. Release note (no code)

The next store build must be compiled with the iOS 27.1 SDK (Xcode Cloud "Latest Release" is 27.1 now, so `/testflight`
then `/release` of a new version does it). No version bump in this work (`CFBundleShortVersionString` stays 2.1, build
204, `project.yml`).

## Alternatives rejected

- **Two modifiers (`.sheet` + `.inspector`) with derived bindings as the first design.** Two presentations of one
  state to keep in step; SwiftUI's inspector already adapts. Kept only as the fallback if step 2's tests show the
  compact inspector ignoring the custom detent or background interaction.
- **A `NavigationSplitView` for the regular layout.** A split view changes the whole hierarchy (a sidebar, a detail);
  the HIG asks for the same controls, not a different app.
- **Reading `reservedRegions` from UIKit (`UIView.reservedRegions(ofKind:)`).** The app's root is SwiftUI; the
  GeometryProxy call is the documented SwiftUI route and shares the view's coordinate space.
- **Shifting the capsule by a fixed amount on the Duo (device check) instead of the regions.** Wrong when fully open
  (the region is inactive; the capsule should be centred) and wrong on the next foldable.
- **Measuring the capsule's frame in the container space and feeding it to the math** (revision 1). The frame includes
  the offset the math produces: an oscillation (review B1). Replaced by the derived unshifted frame.
- **Measuring the frame and subtracting the applied offset.** Exact only if the state read in the geometry callback
  is the one the layout used; the derivation from size and container has no such ordering dependency.
- **A union-then-retry collision loop** (revision 1). Could step back into a region already cleared (review B5);
  candidate evaluation against every region has no retry.
- **Branching the harness on the fixture size (`isRegularWidth`)** (revision 1). `.phone` is regular on the iPad pass:
  the harness would wait for a sheet that is now a column (review B2). The harness reads the host's size class.
- **Keeping `GallerySize.regularWidth` beside the Duo sizes.** 834 x 1210 approximated an iPad that now has its own
  pass; the inner Duo sizes carry the regular-width trait with a real device's numbers. One case fewer.
- **A `duoOuter` fixed size on the iPhone pass.** The Duo pass renders the outer display from `UIScreen` with real
  insets; a 466 x 678 window on the iPhone 17 Pro would be a second approximation nobody needs.
- **Capturing at 2x and upscaling the hero 1.5x in the renderer.** The edge-to-edge 2853 x 2007 hero would be soft;
  the display is 3x, the captures are too.
- **One Duo config with two display types.** `render.mjs` has one `W`, `H` and `displayType` per config; the Mac and
  iPad already use one config per set.
- **Folding the simulator from the script.** No `simctl` command exists (Facts); GUI automation of Simulator.app is
  not headless and the app could not even be located.
- **A manifest `platform` field and `previews/<platform>/` folders** (the generic skill text, `SKILL.md:136-160`):
  xFractal's script already separates passes by `PREVIEW_GALLERY_OUT`; nothing reads a platform field.

## Test plan (red first)

Pure math, `Tests/PeekShiftTests.swift` (macOS `xFractalTests`, run with the test gate; 73 tests today → 80):

1. `testNoRegionsNoShift`: a 220 x 36 capsule centred in 951 x 669, `[]` → 0.
2. `testRegionNotIntersectingNoShift`: a region rect that does not touch the capsule → 0 (the view filters inactive
   regions before the call; this proves a non-intersecting rect is ignored).
3. `testHingeOnCentreShiftsTrailingByTheMinimum`: capsule `(365.5, 621, 220, 36)`, region `(455.5, 0, 40, 669)` →
   `495.5 - 365.5 = 130`, and the shifted capsule overlaps no region.
4. `testTrailingBlockedFallsBackToLeading`: a capsule near the trailing edge where every trailing candidate leaves
   the container → the negative candidate `region.minX - capsule.maxX`.
5. `testNeitherFitsReturnsZero`: a region wider than the free space on both sides → 0 (the capsule stays, nothing
   worse than today).
6. `testCandidateInsideAnotherRegionIsRejected` (the review's case): container 100 wide, capsule x 40...60, regions
   x 45...55 and x 70...95 → −15 (x 25...45): the trailing move to 55...75 would enter the second region, the move
   clearing the second to the left would re-enter the first; the result overlaps neither.
7. `testTouchingEdgeIsClear`: a capsule whose edge coincides with a region's edge → 0 (positive-area overlap only).

Each fails before `peekShift` exists (a compile error on the symbol is the right red; the implementer commits the
stub returning 0 first if a compiling red is wanted) and 3, 4 and 6 fail against the stub.

Gallery, `GalleryTests/GalleryScenarioTests.swift` (run by every gallery run, on the iPhone, iPad and Duo passes):

8. `testDuoInnerTraits` (replaces `testRegularWidthTraits`, `:148-161`): both inner sizes report `.regular` on the host,
   the outer probe and the window size 951 x 669 / 669 x 951; the mount's form is `.column`. Red: the sizes do not exist.
9. `testCompactSheetKeepsOpeningDetentAndBackgroundInteraction` (sheet form only; `XCTSkip` on a regular host): the
   phone "Controls · Mandelbrot · Opening detent" scenario exposes exactly `[.height(260), .medium, .large]` through
   `sheetPresentationController`, its presented frame is 260 pt high plus the bottom safe-area inset (± 2 pt), and
   `largestUndimmedDetentIdentifier` equals the first (custom) detent's identifier — the executable form of "the board
   stays interactive at the opening detent"; the medium scrim band is covered by `testMediumDetentScrimIsBounded`.
   Green before and after if the single inspector works; red → the fallback design (Design 1).
10. `testColumnPresentsTheFormBesideTheBoard`: the landscape Duo Controls scenario (and, on the iPad pass, the phone
    "Controls · Julia · Large") has `presentedViewController == nil`, a Form `UICollectionView` whose window frame is at
    the trailing edge, an MTKView narrower than the window by that column's width, and the sheet probe reads
    `.regular`. Red today: a sheet is presented and the MTKView spans the window.
11. `testFoldedPeekIsStableAcrossLayoutPasses`: the Folded scenario is rendered, laid out again
    (`window.layoutIfNeeded()`, a second `drawFrame()`), and rendered again; the bottom 140 pt band of both captures is
    byte-identical (no oscillation), and the band differs from the unfolded Landscape scenario's band (the capsule did
    move). Clearance itself is judged by the rendered-image detector in the check (manifest `fold`), not by an offset
    read from the hierarchy: the harness has no accessor for the `Capsule`'s hosting view. Red against the
    feedback design (the band alternates) and against today's code (the bands are equal).
12. `testReferenceComparisonBesideAColumn`: on a `.column` mount of a non-uniform fractal (the landscape Duo Controls
    scenario, Julia), `validate` passes for the expected state and fails for `.defaultState` with the board region
    beside the column. Red before the MTKView-coordinate conversion: the region is sampled against a reference scaled
    to the window width.
13. `testControlsSurviveSizeClassChange`: a phone Controls scenario mounted compact (sheet present), then
    `host.traitOverrides.horizontalSizeClass = .regular` and `window.traitOverrides…` (the column appears, no
    `presented`), then back to `.compact` (a sheet again); after each change the test calls `settlePresentation()`
    and asserts `form` (`.column`, then `.sheet`) and its geometry (the column's `UICollectionView` at the trailing
    edge beside a narrower MTKView; then a presented sheet whose frame spans the window's width), that the controls
    are open and that the store's state is the fixture's (a value edited through the Form before the change —
    `maxIterations` set via the store the Form binds to — is still shown by the Form's row). Trait overrides stand in
    for a fold; no physical folding. Red against unguarded fallback setters and against a cached `form`; holds for the
    single-inspector design.
14. `testDuoCaptureScaleIsThree`: the landscape board capture is 2853 x 2007 px. Red: 1902 x 1338.
15. `testDuoPassRequiresTheOuterDisplay` (in `SnapshotGalleryTests`, skipped unless `XFRACTAL_SNAPSHOT_DEVICE=duo`):
    the screen is 466 x 678 pt and a `.phone` mount is compact, else the run fails with the screen size.
16. `testFoldRegionChangeMovesAndRecentersTheCapsule`: the Folded scenario is mounted once; through `FoldRegionsBox`
    the regions go `[hinge]` → `[]` → `[hinge]` on the same view identity, each step followed by a bounded settle
    (`drawFrame()`, then up to 2 s until two successive captures are byte-identical: the offset animation has ended).
    Captures A (hinge), B (none), C (hinge) of the bottom 140 pt band: A == C byte for byte (recentering and
    re-shifting are deterministic); A != B; the columns where A and B differ form exactly two runs, one containing
    the window's centre x (B's centred capsule) and one lying entirely trailing of `fold.maxX` (A's shifted capsule),
    neither overlapping the fold rect's x-range. This is the production placement path reacting to a changed region
    list; the store's state is unchanged throughout. Red today (the capsule never moves: A == B).

Scripts: `scripts/test_preview_gallery.py` gains the three fold contract tests of Design 3; `scripts/test_snapshot_gallery.sh`
gains `pool_duo` (lease, folder, release, and `TEST_RUNNER_XFRACTAL_SNAPSHOT_DEVICE=duo` in the test command). Both
red before the script and check changes.

Screens (the scenarios are the proof for every new entity): `foldRegion` is written in `GalleryFixtures.all`
(the Folded fixture), passed by `GalleryScenario.build` into `ContentView(foldRegions:)`, read by
`activeFoldRegions`, turned into the offset by `peekShift`, drawn on the card
`duo-inner-landscape-board-folded-mandelbrot(.dark).png`, and checked through `manifest.json`'s `fold` by
`preview-gallery.py` (the production read path from the override on; the `reservedRegions` source is the owed manual
check). The inspector's path: `showingSheet` → `.inspector` → the column on `duo-inner-landscape-controls-julia`,
`duo-inner-portrait-controls-mandelbrot` and, on the iPad pass, the eight phone Controls scenarios, light and dark,
judged by the column's region rule. `PresentationForm` reaches the manifest as `diagnostics.detent: "column"`.

maestro: `node --test tools/app-store-screenshots/layout.test.mjs` with the three new tests (red before the frame
classes and the device validation). simpool: `simpool specs` lists `duo  iPhone Duo (iOS 27.1) [extra]`; a
`simpool acquire --spec duo --pid $$` followed by `simpool release` in the gallery's first Duo run is the live proof.

Owed (no test can cover): the operating system's delivery of real reserved regions on a real Duo or a
Simulator.app-folded Duo (`reservedRegions(kind: .division)` returning an active frame while partially folded and
none when open — the reaction to a changed list is test 16, the source is this check; the controls switch column ↔
sheet while open without losing state, test 13 covers the trait change); a Mac run (the Mac tree is untouched but
shares the file); the full gallery read in both appearances on the iPhone, iPad and Duo passes.

## Invariants (AGENTS.md and the develop skill)

- Pure logic in `FractalMath.swift`, tested: **holds** (`peekShift`, a free function like its neighbours, + 7 tests).
- Math platform-agnostic, `#if os(iOS)` only for UI: **holds** (`peekShift` uses CoreGraphics; the GeometryReader,
  `.inspector` and the availability check are inside the existing `#if os(iOS)` blocks). The Mac build is unchanged
  in behaviour; the test gate proves it.
- Product `xFractal`, bundle ID, scheme names: **holds** (nothing touches them).
- No `#Preview`; every screen state a scenario: **holds** (nine new scenarios, two removed; 26 in all).
- `.xcodeproj` generated from `project.yml`: **holds**; no target or file-list change is expected (`Tests/PeekShiftTests.swift`
  is picked up by the `Tests` source folder; verify with `xcodegen generate` producing no diff, else commit it).
- `docs/appcast.xml` frozen: **n.a.** (untouched; the gate's `git diff --exit-code main -- docs/appcast.xml` runs).
- Saved state compatibility: **holds** (no `Codable` change; `ViewState`, `Snapshot`, the keys are untouched).
- Numeric precision / shader agreement: **n.a.**
- String catalog: **holds**, no new user-facing string (the inspector reuses the Form); `catalog-sync --check --skip-build`
  confirms "catalog unchanged".
- Public-repo hygiene: **at risk** in the new configs and plan: no absolute paths, no team id; the manifests and PNGs
  carry none (as today).

## Risks and rollout

- **Both platforms.** The Mac shares `ContentView.swift`; all changes sit in `#if os(iOS)`. The macOS test gate (73 → 80
  tests) and the warnings gate on `xFractalTests` and `xFractalGalleryTests` run at every step.
- **The iPad pass changes shape.** Its eight Controls scenarios become columns; step 2 runs `--device ipad` with
  `--measure` and reads every changed card, and the column's region kind is fixed from that measurement.
- **iOS 27.1-only API behind availability.** Compiles only with the iOS 27.1 SDK: Xcode 27.1 locally
  (`project.yml` `xcodeVersion: "27.1"`) and Xcode Cloud "Latest Release" (27.1). `ci_scripts/ci_post_clone.sh` is
  untouched. If Xcode Cloud were pinned to 27.0 the build would fail on the symbol: check the workflow's Xcode version
  before `/testflight`.
- **The compact inspector's behaviour** (custom detent, background interaction, harness driving): decided by test 9 in
  step 2; the fallback is written above, so the step cannot stall.
- **Fixed windows larger than the folded Duo's screen.** The same technique as the retired regular-width cards
  (834 x 1210 on a 402 x 874 screen drew fine); if the Duo runtime clips an oversized window, the inner scenarios on the
  Duo pass are marked a finding and the iPhone pass remains their home.
- **A reused Duo lease in another posture.** Test 15 fails the Duo pass before rendering if the screen is not the
  outer display, so no capture is mislabelled "outer".
- **Calibration.** The new cards run `preview-gallery.py --check --measure` first (the plan's rule: fixed floors, no
  threshold derived from the measurement); the column's `.sheet` coverage and the 3x peek numbers go into the
  implementation log below.
- **Scripts changed** → `python3 -m unittest discover -s scripts -p 'test_preview_gallery.py'` and
  `scripts/test_snapshot_gallery.sh` in the step gate.
- **Pool budget.** A Duo simulator is one more booted simulator (about 6 GB); the spec is `extra`, so it is evicted
  first and never holds a slot idle beyond 30 minutes. A non-pool "iPhone Duo" simulator is booted on this Mac today
  (`simpool status`: "not in the pool"); the pool creates its own `simpool duo 1` and never touches that one.
- **Xcode Cloud** skips the gallery (`XFRACTAL_SNAPSHOT_DIR` unset) and runs the macOS tests: the new `Tests/` file runs
  there.
- **Rollout:** nothing ships from this work. After landing, `/testflight` then `/release` of a new version produce the
  27.1-SDK build; the Duo screenshots wait for the upload path (open decision 1).

## Decisions left open for Jean

1. **Uploading the Duo screenshots.** The legacy screenshot API has no Duo display type; the App Asset Library has
   (`IPHONE_DUO`, `APP_SCREENSHOT`). Options: (a) extend maestro's `app-store` with an asset-library screenshot upload
   (a later maestro plan; `app-store creative` is the template), (b) upload the two rendered sets by hand in App Store
   Connect for this release. The plan renders and reviews them; it does not upload.
2. **The outer frame's Dynamic Island.** The profile says the Duo has one but not where it sits on the outer display
   (the status bar is on the right side). The `duo-outer` frame draws no island; say if a cutout should be drawn once
   its position is known (a one-line CSS change in maestro).
3. **The inner display's inspector width.** Default SwiftUI width first; if the portrait inner card (669 pt wide)
   leaves too little board, `.inspectorColumnWidth(280)` or similar — read the card and say.
4. **The fold region stand-in** (`455.5, 0, 40 x 669`): replace with the real `ReservedRegion.frame` read on a device
   when one is at hand; until then the Folded card shows the behaviour with a plausible hinge.

## Steps

1. **Peek shift math** — the free function `peekShift(capsule:clearing:in:)` in `FractalMath.swift` with
   `Tests/PeekShiftTests.swift` (tests 1-7), red then green; the macOS test gate 80 tests.
2. **Inspector controls and the Duo inner sizes in the gallery** — `.inspector` replaces `.sheet` (or the fallback with
   guarded setters, decided by test 9); `GallerySize` {phone, duoInnerLandscape, duoInnerPortrait, scale},
   `regularWidth` removed; the harness follows the actual presentation (computed `PresentationForm` and
   `settlePresentation()`: column wait, scroll, scrim, regions, fractal region beside the column, `validate` and
   `gainedReference` in MTKView geometry, 3x capture); the eight
   unfolded Duo fixtures replace the two regular-width ones; tests 8, 9, 10, 12, 13, 14; the iPhone gallery and the
   iPad gallery (`--device ipad`) both to `CHECK OK` with `--measure`, the column's region kind fixed from the
   measurement, every changed card read.
3. **Peek off the fold** — the `GeometryReader`, the derived unshifted frame, `activeFoldRegions` behind
   `#available(iOS 27.1, *)`, the `foldRegions` hook, `GalleryFixture.foldRegion`, the Folded fixture, manifest `fold`,
   the check's fold rule with its three contract tests in `scripts/test_preview_gallery.py`; `FoldRegionsBox` and
   `FoldHost` in the test target; tests 11 and 16; the full iPhone gallery `CHECK OK`.
4. **simpool spec `duo` (in ~/GitHub/maestro)** — `spec duo "iPhone Duo" iOS-27-1 extra` in `global/simpool.conf`; the
   spec list in `README.md` ("Simulators and builds"); `simpool specs` shows it. Committed in maestro.
5. **Gallery `--device duo`** — `scripts/snapshot-gallery.sh` (the duo block, usage, fallback device type and runtime,
   `TEST_RUNNER_XFRACTAL_SNAPSHOT_DEVICE`, the screen size in the timings), test 15, `pool_duo` in
   `scripts/test_snapshot_gallery.sh`, both script test suites green; a first `--device duo` run to `CHECK OK` (its
   measurements into the log below); `.claude/skills/preview-gallery/SKILL.md` and `AGENTS.md` updated (26 scenarios,
   groups, the Duo pass and what it does and does not prove, the iPad pass's columns).
6. **Duo device frames (in ~/GitHub/maestro)** — `phoneHTML` generic branch with `class="phone ${device}"`, island for
   `iphone` only, the `ipad` branch folded in; `.phone.duo` (open book, hinge) and `.phone.duo-outer` (asymmetric radii)
   in `render.mjs`; `validate` rejects an unknown device; three tests in `layout.test.mjs`; `node --test` green.
   Committed in maestro.
7. **Duo App Store screenshot configs** — `AppStore/screenshots-duo-inner.json` (2853 x 2007, hero edge to edge) and
   `AppStore/screenshots-duo-outer.json` (1398 x 2034), rendered from `previews/duo/` after
   `--device duo --only … --lang fr,de,it,es,pt-BR,ja,tr`; the review pages read in every locale;
   `.claude/skills/app-store-screenshots/SKILL.md` updated (commands, "rendered, not uploaded"). The plan's
   implementation log and the release note (a new version ships via `/testflight` and `/release`; no bump here).

## Implementation log

Status: implemented on main 2026-10-25. Deviations from the plan, as found while building it:

- **Controls: the fallback design, not the single inspector.** Step 2's test 9 was red against `.inspector` alone: with `isPresented`
  true from the start, the compact inspector presented no sheet at all (10 s wait, `presented` nil). So `.sheet` serves the compact
  width and `.inspector` the regular one, over the one `showingSheet`. The setters' guard reads a reference (`WidthGuard`), not a
  captured copy of the view: a binding kept from an earlier body wrote `false` during the size-class change with a captured value.
  Test 13 is red against unguarded setters.
- **The board stops at the column.** Beside an inspector column the main content gets a trailing safe-area inset (280 pt) and the
  board's `.ignoresSafeArea()` ran under it: at regular width the board ignores top, bottom and leading only.
- **The column's own content is compact** (280 pt wide): the sheet probe reads `.compact` there, not `.regular` (tests 8 and 10
  assert that). In the 669 pt portrait window the system lays the column **over** the board with the sheet's dimming (scrim 0.200
  light, 0.479 dark, as the medium detent) instead of beside it: that card is judged as `.sheetGlass` with that scrim band, and
  `columnOverlaysBoard` tells the cases apart. `columnFrame` comes from the Form's list, not from the board's narrowing.
  An opaque column beside the board measured sheet coverage 0.82 to 0.95 (floor 0.50) on the iPhone and iPad passes: `.sheet`.
- **Test 9** asserts the custom detent `Height:260.0` plus medium and large (their order is not first-custom), the opening height
  between 260 and 260 + bottom inset (measured 282 pt on the iPhone 17 Pro), and `largestUndimmedDetentIdentifier` = the custom one.
- **Test 13** resizes the window to 951 x 669 as well as overriding the size class (a regular override at 402 pt wide shows no
  column), and checks the store, not the Form's row text (SwiftUI draws it; no accessibility tree).
- **Test 16**: the shifted and the centred capsule overlap, so the differing columns form one run, not two; the test asserts the
  run starts at or before the centre and ends past the fold's trailing edge. Test 11 has no red for the "measured frame" oscillation
  design (never built); it is red against no offset.
- **`testStaleFrameIsRejected`** drives the Julia frame through the store: a SwiftUI update copies the store's state into the
  renderer and resumes the view, which undid the hand-set `renderer.state`/`isPaused` once the inspector wrapper exists.
- **The Folded card is captured after the offset animation ends** (`settlePeek`, two identical captures), else the capsule is
  caught mid-move.
- **The check**: the cold Julia on the wide inner display measures mean 0.016: `FRACTAL_MEAN` floor 0.02 -> 0.01. The capsule is
  centred between the safe-area insets (the Duo's outer display has unequal ones: 42 pt off the window centre), recorded as
  `safeArea` in the manifest; new contract tests.
- **The Duo pass renders all 26 scenarios** (the plan's design). The first implementation excluded the inner windows after they
  failed the reference comparison on the Duo's outer display (correlation 0.03 to 0.69), blaming the windows being wider than the
  screen. Codex traced it to the geometry instead, and the fix confirmed it: the Duo screen has a trailing device inset (84 pt), the
  board kept that inset at regular width even with the controls closed and stopped short of the window edge, `validate` sampled
  the whole window against a narrower reference (two different areas stretched to 64 x 64), and `columnOverlaysBoard` required the
  board to reach the window's edge, so an overlapping column looked like a side-by-side one (scrim band 0, measured 0.200/0.479).
  Now the board ignores the trailing safe area unless the inspector is shown, the region is cut to the board before sampling, and
  the overlay rule is "the board reaches under the column". `AppStore/screenshots-duo-inner.json` reads `previews/duo/` again.
- **Review fixes (round 1)**: `Signing.xcconfig` moved to `Config/` (XcodeGen wraps a root-level config file in a group named after
  the checkout's directory, so the project differed between a worktree and `xFractal`; `main`'s own copy carried the name
  `localization` from such a checkout). The generated pbxproj is now identical in any directory. The shared schemes are left as
  committed: this Mac's XcodeGen 2.46 writes a newer scheme format than the one in git (version 1.7, `xFractal-MAS.app` build names),
  which is a tool-version difference, not a directory one. `WidthGuard` stays: test 13 is red against bindings that capture the width
  as a value (the controls never come back as a column). Test 13 now also checks the displayed board follows the store after each
  transition (the renderer receives the store's state and an edit), and that closing the sheet stays closed. The fixture's
  presentation prediction (`expectedForm`, `measuredKinds`, a hard-coded overlay width) is gone: manifest kinds are the measured
  regions' kinds, and there is one overlay rule. `settled` is shared by `settlePeek` and the band tests. The maestro frame tests
  parse the Duo CSS (screen sizes at 2x, bezel, hinge, corner radii).
- **`scripts/test_snapshot_gallery.sh`**: the xcodebuild stub logs the `TEST_RUNNER_XFRACTAL_SNAPSHOT_DEVICE` it receives.
- Environment: a failing `xcodebuild test` runs `simctl diagnose` for up to 10 minutes before it exits; one Duo run stalled for 17
  minutes under a load average of 400 (another session's work) and was rerun.
- The renderer's Playwright wanted a Chromium build that is not installed (the download hung); the screenshots were rendered
  with the installed headless shell through a scratch shim (no maestro change).

Owed (no test covers them): `reservedRegions(kind: .division)` on a folded Duo (Simulator.app or a device); the Duo screenshots
are rendered and reviewed, not uploaded (open decision 1); the next store build needs the iOS 27.1 SDK (Xcode Cloud's "Latest
Release" is 27.1; nothing here bumps the version: 2.1, build 204).
