# Hebrew and Arabic, right to left: the app and its App Store page (2.3)

Status: implemented on main 2026-10-28, revision 3 (two Codex plan rounds, two Codex code rounds). Branch `jean-bovet/2.3-hebrew-and-arabic-right-to-left` (Orca
worktree, from `main`). GitHub issue #2.

Adds Hebrew (`he`) and Arabic (`ar`; App Store Connect `ar-SA`) to the app and to its App Store page, following the
template of commit 918f50e (Spanish, Brazilian Portuguese, Japanese and Turkish), and makes the first right-to-left
pass over the UI: what mirrors, what must not (the fractal), and which digits the app shows. Two steps land in
`~/GitHub/maestro` (its own commits): the shared languages list and the screenshot renderer's right-to-left headlines.
Not in scope: 2.3's What's New (written at release time by `/release`), uploading anything to App Store Connect, new
gallery scenarios.

## Revision history

- **Revision 3** (2026-10-27), Codex plan review round 2 (0 blockers, 1 should-fix, accepted): the two assertions
  that stay in each mirrored test also mirror — `testColumnPresentsTheFormBesideTheBoard:201`'s containment
  (`listFrame.minX >= column.minX - 1`, trivially true once `column.minX == 0` under RTL) becomes `listFrame.maxX <=
  column.maxX + 1`, and `testFoldRegionChangeMovesAndRecentersTheCapsule:327`'s centre coverage (`first <= width / 2`,
  implied by `first < hinge.minX - 60` under RTL) becomes `last >= width / 2`; each test keeps one containment or
  coverage bound and one far-side bound in both directions (Design C).
- **Revision 2** (2026-10-27), Codex plan review round 1 (2 blockers, 5 should-fix, 1 simpler; all accepted):
  - B1 (`knownRegions` by hand breaks the generated-project invariant): accepted. Step 4 runs `xcodegen generate` and
    commits what it writes, schemes included; the scheme drift is explained in Facts (harmless: schemes are selected
    by name and bind their target by `BlueprintIdentifier`) and the gates of the same step drive both schemes. A new
    decision 5 offers `productName: xFractal` in `project.yml` to end the `BuildableName` flip-flop.
  - B2 (`testReferenceComparisonBesideAColumn:217` keeps `region.maxX <= column.minX`): accepted; Design C lists it
    among the direction-sensitive assertions (the region lies beside the column on the board's side).
  - SF1 (the centred fold override cannot show a mirroring disagreement, so "negate the offset" was unfounded):
    accepted. Risks now says the gallery cannot stand in for the production `reservedRegions` read (the override
    hinge is centred: `x: 455.5, width: 40` in a 951 pt window); the check is a real Duo half-folded under Hebrew,
    and the fix, if any, follows what it shows.
  - SF2 (no RTL capture of the Multibrot stepper, the Newton picker or the folded capsule): accepted; the one-time
    right-to-left review run of step 5 adds `controls-multibrot-large`, `controls-newton-large`,
    `board-replay-ready`, `controls-replaying` and, on the Duo, `duo-inner-landscape-board-folded-mandelbrot`.
  - SF3 (the device-inset tests inject `right: 84` under RTL too): accepted; they inject the inset on the trailing
    side, so `boardTrailingPadding`'s `safeAreaInsets.trailing` path is the one exercised.
  - SF4 (the "a mirrored fractal fails validation" claim had no test): accepted; `testMirroredCaptureFailsTheReference`
    flips a capture horizontally and runs it through `validate` on an asymmetric fixture.
  - SF5 (storefront order asserted without evidence; swapping captions cannot rejoin a phone split over fixed clips):
    accepted. Design D says the order is unverified until `/release` uploads, and the fallback that works with
    fixed clips is to swap the two captions *and* upload the pair's two files in reverse order for he and ar-SA.
  - S1 (`dir` on `.text`, not on `<html>`, which would also reverse the status bar's flex order): accepted.
- **Revision 1** (2026-10-27): first draft, written by the planning subagent from the issue and the code.

## Facts established while planning

- **The template.** `git show 918f50e --stat`: 28 files. Per language: the catalog (`xFractal/Localizable.xcstrings`),
  `Tests/LocalizationTests.swift` (`languages` and one sample assertion), `knownRegions` in
  `xFractal.xcodeproj/project.pbxproj` (edited by hand, +1 line per language), `AppStore/app-info.txt`,
  `AppStore/keywords.txt`, `AppStore/description-{ios,mac}-<locale>.txt`, the slide configs' `locales` and `text`,
  the `--lang` whitelist and `region()` of `scripts/snapshot-gallery.sh` and `scripts/snapshot-mac.sh`, the
  `pool_regions` case of `scripts/test_snapshot_gallery.sh`, `AGENTS.md` and the four skills. Since then two slide
  configs were added (`AppStore/screenshots-duo-inner.json`, `screenshots-duo-outer.json`): five configs carry
  headlines, nine locales each, four slides each (the Mac's are one-line titles; the others break with `\n`).
- **The catalog.** 31 keys, `sourceLanguage` en. 30 are translated into de, es, fr, it, ja, pt-BR, tr; `"San Marco"`
  has `shouldTranslate: false` and no translations (a proper name; `testCatalogIsFullyTranslated` skips it). No
  `InfoPlist.xcstrings`, no `CFBundleLocalizations`; `CFBundleDisplayName` is the unlocalized `xFractal` in both
  plists. Nothing but the catalog needs a translation.
- **xcodegen and `knownRegions`** (checked, then restored with `git checkout -- xFractal.xcodeproj`): `xcodegen
  generate` (2.46.0) leaves `project.pbxproj` unchanged, so it derives `knownRegions` from the catalog's languages
  (es, ja, pt-BR, tr survived). Once he and ar are in the catalog a regeneration adds them by itself: step 4
  regenerates and commits the project, as `AGENTS.md` § Project regeneration requires (918f50e edited the two lines
  by hand instead). The regeneration also rewrites both `.xcscheme` files: the checked-in ones are "as Xcode saves
  them" (commit 20bb060: Xcode rewrites a scheme on save with `version 1.3`, the real product `BuildableName
  xFractal.app`, no empty blocks), xcodegen writes `version 1.7`, `BuildableName` after the target
  (`xFractal-MAS.app`, `xFractal-iOS.app`; `project.yml` sets `PRODUCT_NAME: xFractal` in settings, :57 and :97, but
  no `productName`), `runPostActionsOnFailure`, `onlyGenerateCoverageForSpecifiedTargets` and empty
  `CommandLineArguments` blocks. Harmless: `xcodebuild -scheme` and Xcode Cloud select a scheme by its name, and a
  scheme binds its target by `BlueprintIdentifier` (unchanged); `BuildableName` is descriptive and Xcode rewrites it
  on the next save. The step's gates prove it (the test gate drives `xFractal-MAS`, the gallery `xFractal-iOS`).
  The flip-flop (xcodegen's form after each regeneration, Xcode's after each save) ends with `productName: xFractal`
  on both targets in `project.yml`: decision 5.
- **Digits** (a Swift probe against Foundation on this Mac):

  | locale | `250.formatted()` | `String(format: "%u", locale:)` | `String(format: "Iter %u")` through the localized key | numbering system |
  |---|---|---|---|---|
  | en_US, he_IL, ar, ar_AE | 250 | 250 | Iter 250 | latn |
  | ar_SA | ٢٥٠ | ٢٥٠ | Iter ٢٥٠ | arab |
  | ar_MA | 250 (grouping `.`) | 250 | Iter 250 | latn |

  Hebrew and most Arabic regions use Western digits; Saudi Arabia (the store locale) defaults to Eastern
  Arabic-Indic digits, and iOS lets the user pick either in Settings › Language & Region › Numbers.
- **Numbers the app shows** (`xFractal/ContentView.swift`): the Mac HUD iteration label `Text("Iter
  \(store.state.maxIterations)")` (285, catalog key `Iter %u`), which SwiftUI formats with the environment locale, is
  the **only** number that localizes. Every other one is verbatim or POSIX: the iOS peek capsule and sheet
  iterations `Text(verbatim: "\(…maxIterations)")` (432, 485), the Julia `c` parts `Text(String(format: "%.4f", …))`
  (354, 364 on the Mac; 557, 567 on iOS), the Multibrot exponent `Text(verbatim: "n = \(…)")` (391, 596), the Newton
  polynomials `Text(verbatim: "z³ − 1")` … (408-410, 608-610). No zoom, coordinate or frame rate is shown. No
  `Locale`, `NumberFormatter`, `.formatted` or `Text(_, format:)` anywhere under `xFractal/`.
- **What mirrors** (SwiftUI, `ContentView.swift`): every container is an `HStack`/`VStack`/`ZStack(alignment:
  .bottom)` with `.leading`/`.trailing` frames and paddings (223-255 the Mac HUD, 299-300 the panel, 423-441 the peek
  capsule, 481-593 the Controls sheet), `Slider`s (289, 353, 363, 489, 561, 571), `Stepper`s (387, 589), a
  horizontal `ScrollView` of presets (573), `.sheet` (89) and `.inspector` (90). No `.left`/`.right`, `UnitPoint`,
  `.position`, `Canvas` or `Path`. The one explicit x is `.offset(x: peekOffset)` (71) on the peek capsule, fed by
  `peekShift` (`FractalMath.swift:121-140`, "positive = trailing") from fold regions `proxy.reservedRegions(kind:
  .division)` (102; `layoutDirectionBehavior` defaults to `.mirrors`). SF Symbols in use: `slider.horizontal.3`,
  `arrow.counterclockwise` (Reset), `play.fill`/`stop.fill`, `trash`, `chevron.up`: none is a directional glyph
  that Apple mirrors (`chevron.up` is vertical; media controls stay left to right by design).
- **The fractal.** `FractalView.swift`: an `MTKView` (iOS) / `ZoomableMTKView` (macOS) in a representable, no UIKit
  gesture recognizers, `semanticContentAttribute` never set, only `view.bounds.size` read (92). The renderer draws a
  full-screen triangle in NDC (`FractalRenderer.swift:81, 177`; `Shaders.metal:17, 332-333`): nothing depends on a
  layout direction. The SwiftUI gestures (`ContentView.swift:162-207`) read `value.location` (drag, local space) and
  `value.startAnchor` (pinch, a `UnitPoint`) and convert through `panCenter` / `unitToNDC` (`FractalMath.swift:18-19,
  38-44`); the Mac scroll wheel uses `convert(event.locationInWindow, from: nil)` (`FractalView.swift:20-23`), AppKit
  coordinates that never flip. SwiftUI does not transform a hosted view's drawing, and gesture values are in the
  view's own (unmirrored) space; whether a `MagnifyGesture.startAnchor` is reported mirrored under RTL is the one
  thing only a device run shows (Risks).
- **The gallery under another language.** `scripts/snapshot-gallery.sh:423-427` runs the whole
  `xFractalGalleryTests` target with `-testLanguage <lang> -testRegion <region>`; the host app has that
  localization once the catalog does, so UIKit (and AppKit for `scripts/snapshot-mac.sh`) lays the UI out right to
  left for he and ar on its own. `region()` (414) maps `ja → JP`, `xx-YY → YY`, else upper-cases: it would send
  `he → HE` (no such region) and `ar → AR` (Argentina). The harness assumes the Controls column is on the right:
  `GalleryHarness.swift:190` (`columnOverlaysBoard`), 196-200 (`columnFrame` runs from the list's `minX` to the
  window's right edge), 288 (the slide-in wait, `maxX <= width`), 498 (`fractalRegion` is `0 … column.minX - 4`);
  `GalleryScenarioTests.swift:200, 217, 243, 327, 351` assert the same (`maxX == window width`; 217 `region.maxX <=
  column.minX`; the shifted capsule "lies trailing of the fold" at `x > hinge.maxX`), and the two device-inset tests
  (347, 365) inject `additionalSafeAreaInsets … right: 84` to stand for the Duo's trailing inset, which
  `boardTrailingPadding` reads as `safeAreaInsets.trailing` (`ContentView.swift:81, 152-158`). The App Store captures
  include a column scenario on the iPad (`controls-julia-large`), so a `--device ipad --lang he` run exercises those
  lines under RTL. `GalleryHarness.validate` (580-615) compares the captured fractal region with a reference render
  of the fixture's state by luminance correlation (≥ 0.95; mean difference for a flat reference) plus an RGB error
  bound after fitting the scrim. The gallery's Duo fold override is a centred hinge (`GalleryFixtures.swift:261`:
  `x: 455.5, width: 40` in a 951 pt window, centre 475.5): mirrored or not, the same rectangle.
- **The renderer** (`~/GitHub/maestro/tools/app-store-screenshots/`). `render.mjs:93-97` writes one
  `<html lang="<locale>">` page per slide and locale, the headline as `<div class="text" style="left:…"><h1>` with
  `white-space:nowrap`, `letter-spacing:-4px`, `font-weight:800`, the system font stack; the iPhone frame's status
  bar is a flex row (`.status`, `justify-content:space-between`: the time, then the glyphs), used by
  `AppStore/search-results.json`; `captionHTML`
  (`layout.mjs:71-73`) turns `\n` into `<br>`; `fitHeadlines` (`render.mjs:74-82`) shrinks every `h1` of a canvas until
  the widest fits (`scrollWidth`, direction-agnostic). No `dir` attribute and no notion of text direction anywhere;
  the Mac config centres its one-line headline with `textStyle: text-align:center`. `localizedCapture`
  (`layout.mjs:60-68`) tries `<locale>/`, then `<language>/`: `ar-SA` finds `previews/ar/`, `he` finds `previews/he/`.
  Tests: `layout.test.mjs` (`node --test`), pure functions only; the HTML rendering is not tested.
- **App Store Connect tools.** `~/GitHub/maestro/bin/app-store` validates `LOCALE=` arguments against the version's
  own locales after `--add-locale` (`per_locale`, `add_locales`); neither it, `asc.py` nor `release-check` holds a
  locale whitelist. App Store Connect's codes are `he` and `ar-SA`; the app's are `he` and `ar`.
- **The shared list.** `~/GitHub/maestro/global/languages.txt`: a base tier (en-US, fr-FR, de-DE, it) and a reach
  tier "in this order … follows reach" (es-ES, es-MX, pt-BR, ja, tr, then `ru` and `id` marked optional), format
  `<App Store Connect locale> <language> [optional]`, read by people and skills only (no parser).
- **The translation-check method** (Unit, `docs/plans/08zu-reach-languages.md` § 7 and
  `docs/reviews/08zu-translation-check.md`): Apple's glossary (the `.loctable` files of macOS and the iOS simulator
  runtime, loaded with `plistlib`; AppKit's carry `he` and `ar`), Wikidata/Wikipedia for the domain terms, a blind
  back-translation by Codex (read-only) with every drift read one by one. No script survived from it: it is
  scratchpad work, with the findings written into the plan's implementation log.

## Problem with evidence

1. The app has no Hebrew or Arabic: `LocalizationTests.languages` (`Tests/LocalizationTests.swift:7`) lists seven
   languages, the catalog's 30 translated keys carry seven `localizations`, `knownRegions`
   (`project.pbxproj:295-305`) has nine entries. The store page has nine locales (`AppStore/*.json` `locales`,
   `app-info.txt`, `keywords.txt`, 18 description files).
2. Right to left was never looked at. The layout is direction-aware by construction (Facts), but three things are
   not settled: the iteration count shows Eastern Arabic-Indic digits in the Mac HUD under ar-SA and Western digits
   everywhere else (`ContentView.swift:285` vs 432, 485); the Julia values `"-0.7000"` (354, 364, 557, 567) contain no
   strong character, so in a right-to-left paragraph the minus sign lands on the right of the number (Unicode bidi
   rules W5/N1: a leading separator takes the paragraph direction); and the peek capsule's fold shift (71, 109-116)
   mixes a mirrored `.offset(x:)` with fold frames whose mirroring is SwiftUI's default — correct only if both
   mirror together, which no test shows and the gallery cannot show (its override hinge is centred).
3. The gallery scripts refuse `--lang he` and `--lang ar` (`snapshot-gallery.sh:66`, `snapshot-mac.sh:25`) and would map
   the regions wrongly (`:414`, `:42`); the harness and seven scenario tests assume the Controls column on the right (or inject a right-hand inset for the trailing one).
4. The screenshot renderer writes every page left to right: a Hebrew or Arabic headline would be left-aligned under
   `<html lang="he">` with no `dir`, and `letter-spacing:-4px` pulls Arabic letters apart (Chromium applies
   letter-spacing to cursive scripts).
5. `~/GitHub/maestro/global/languages.txt` has neither language; the issue asks for both as reach languages marked
   right to left.

## Design

The smallest change that is correct is 918f50e's shape again, plus four right-to-left items, each the smallest fix:

### A. Western digits everywhere (the one code change in `xFractal/`)

Decision (left open below, default Western): the app is math notation (`z³ − 1`, `n = 4`, `c = -0.7000 + 0.2700i`),
Hebrew and most Arabic regions use Western digits, and every number but one is already verbatim. So the one
localizing number joins the others:

- `xFractal/FractalState.swift`, next to `Palette.label` (a `LocalizedStringResource`, :36): on `ViewState` (the type that holds `maxIterations`, :67),
  `var iterationsLabel: LocalizedStringResource { LocalizedStringResource("Iter \(String(maxIterations))") }`. The
  `String` interpolation makes the key `Iter %@` and keeps the digits as written; an `Int` interpolation (`%lld`)
  would be formatted in the resource's locale (Facts: `ar_SA` → `٢٥٠`).
- `ContentView.swift:285`: `Text(store.state.iterationsLabel)`.
- The catalog: `catalog-sync` adds `Iter %@` and marks `Iter %u` stale; the seven translations move to the new key
  (`Iter. %@`, `Itér. %@`, `反復 %@`, …), `--delete-stale` removes the old one. `LocalizationTests` fails on a stale
  key, so the move cannot be forgotten.
- The Julia values: `Text(String(format: "%.4f", …))` at 354, 364, 557, 567 get `.environment(\.layoutDirection,
  .leftToRight)` **only if** the `--lang he` captures show the minus sign on the right (Risks; the capture is the check,
  the fix is one modifier per `Text`). No LRM characters in strings.

### B. The two languages in the app

- 30 keys × 2 languages in `xFractal/Localizable.xcstrings`, `state: translated`, written as the develop skill says
  (Xcode MCP `StringCatalogEdit` on the worktree's project, or a scratchpad script writing the units; either way
  `catalog-sync --skip-build` re-sorts and `--check --skip-build` must print "catalog unchanged"). How they are
  written: one pass per language from the English key with the fr, de, it, es values as context; Hebrew in
  gender-neutral imperatives where the UI has a verb (Reset, Stop, Replay, Clear Journal, Done: Apple's own Hebrew
  forms), Arabic in Modern Standard Arabic with Apple's terms. `Julia c` keeps the Latin `c`; `San Marco` stays
  untranslated. Checked three ways before the step's commit (Facts: the Unit method): (1) Apple's glossary from the
  `.loctable` files for the interface words that Apple also has (Done, Reset, Stop, Controls, Appearance, Type,
  Palette, Replay, Gray, Smooth, Real, Imaginary, Iterations, Polynomial, Exponent), (2) Wikidata labels for the
  mathematical terms and the Julia preset names where they are concepts (Fractal, Polynomial, Exponent, Iteration,
  Real/Imaginary part, Dendrite, Spiral, Galaxy, Rabbit — the Douady rabbit), (3) a blind back-translation by
  Codex (read-only, `codex exec`) of the 60 strings, every drift read one by one. Findings and fixes go into the
  plan's implementation log, as Unit's review did.
- The project: `xcodegen generate` after the catalog has both languages, and the regenerated `xFractal.xcodeproj`
  committed with the step — `knownRegions` gains `ar` and `he` (code-point order), and both schemes take xcodegen's
  form (Facts: harmless, proven by the step's gates). `project.yml` is unchanged unless decision 5 adds
  `productName: xFractal` to the two targets, in which case the regenerated schemes keep `BuildableName xFractal.app`.
- `Tests/LocalizationTests.swift`: `languages` gains `"he"` and `"ar"` (the catalog test then demands both), the
  doc comment names them, `testPaletteLabelsAreTranslated` gains one Hebrew and one Arabic assertion (the sample
  pattern of the ja line), and `testIterationsLabelKeepsWesternDigits` (Test plan).

### C. The gallery under right to left

- `scripts/snapshot-gallery.sh:66` and `scripts/snapshot-mac.sh:25`: the whitelist gains `he|ar`; `region()` (:414) and the
  inline case (:42) gain `he) echo IL ;; ar) echo SA ;;` before the generic arms. Comments (`:16`, `:5`) list them.
- `scripts/test_snapshot_gallery.sh` `pool_regions` (622-629): two more `expect … called "-testLanguage he -testRegion
  IL"` / `"-testLanguage ar -testRegion SA"` lines on a `--lang ja,pt-BR,he,ar` run.
- `GalleryTests/GalleryHarness.swift` becomes direction-aware in the four places that assume the column on the right,
  through one computed property `var rightToLeft: Bool { window.effectiveUserInterfaceLayoutDirection ==
  .rightToLeft }` on the mount: `columnFrame` (196-200) runs from the window's edge on the column's side to the list's
  far edge (`0 … list.maxX` under RTL), `columnOverlaysBoard` (190) compares the board's `minX` with `column.maxX`,
  the slide-in wait (288) checks `minX >= -1`, `fractalRegion` (498) is the strip beside the column
  (`column.maxX + 4 … width`). The direction-sensitive assertions of `GalleryScenarioTests.swift` follow, each pair
  mirrored as a pair so that no bound turns vacuous: 200, 243 and 351 assert the list (or the board) at the window's
  edge on the column's side (a small helper on the mount, `columnEdge(of: CGRect) -> CGFloat` and `windowEdge`,
  replaces the four `maxX == width` comparisons), and 201's containment of the list in the column strip
  (`listFrame.minX >= column.minX - 1`, trivially true once `column.minX == 0`) becomes `listFrame.maxX <= column.maxX
  + 1` under RTL; 217 (`testReferenceComparisonBesideAColumn`) asserts the region beside the column on the board's
  side (`region.maxX <= column.minX` LTR, `region.minX >= column.maxX` RTL); 327-328
  (`testFoldRegionChangeMovesAndRecentersTheCapsule`) assert the centred capsule's differing columns reaching the
  window's centre and the shifted capsule beyond the fold on the trailing side — `first <= width / 2` and `last >
  hinge.maxX + 60` LTR, `last >= width / 2` and `first < hinge.minX - 60` RTL (keeping `first <= width / 2` under RTL
  would be implied by the far-side bound and prove nothing); the two device-inset
  tests (347, 365) inject the 84 pt inset on the trailing side (`rightToLeft ? left: 84 : right: 84`), so the
  production path they exercise is `boardTrailingPadding`'s `safeAreaInsets.trailing` in both directions. No
  production change: these tests then pass in every language the scripts accept, as they do today for fr … tr.
- One new test, `testMirroredCaptureFailsTheReference` (GalleryScenarioTests, the `quick` gate class): the capture
  of an asymmetric fixture (`board-julia-spiral-chromatic`) flipped horizontally through a `CGContext`
  (`scaleBy(x: -1, y: 1)`) and run through `validate` with the fixture's own state must not pass, while the unflipped
  capture does. It turns the claim "a mirrored fractal fails the reference comparison" into evidence: the he/ar
  captures then prove the fractal unmirrored by the same path the gallery check already runs.
- No new scenario and no language pass in the gallery: the right-to-left checks the issue lists are store captures
  plus a one-time review run of the same kind (`--only` with `--lang he,ar`, into `previews/he/` and `previews/ar/`,
  both gitignored; the gallery page stays English). The store captures: `--only "board-julia,board-mandelbrot-deep-zoom-chromatic,
  board-mandelbrot-first-launch,board-multibrot,board-newton,controls-julia-large" --lang he,ar` on the iPhone (the
  bottom bar, the Controls sheet with the iteration and Julia sliders, the presets' horizontal scroll, the digits),
  `--device ipad` (the column on the left), `--device duo` and `scripts/snapshot-mac.sh --lang he,ar` (the HUD, the
  panel, the sliders, the Mac under a Hebrew/Arabic system language). The review run adds what the store slides do
  not show: `controls-multibrot-large` (the exponent stepper and `n = 5`), `controls-newton-large` (the polynomial
  picker and its `z³ − 1` labels), `board-replay-ready` and `controls-replaying` (the play and stop icons, the
  Replay/Stop buttons) on the iPhone, and `duo-inner-landscape-board-folded-mandelbrot` with `--device duo` (the
  capsule off the centred fold under RTL). The fractal must look identical to the English capture of the same
  scenario: `GalleryHarness.validate` compares the captured fractal region with a reference render of the fixture's
  state, and `testMirroredCaptureFailsTheReference` shows that a mirrored fractal fails it.

### D. The App Store page (11 locales: en-US, fr-FR, de-DE, it, es-ES, es-MX, pt-BR, ja, tr, he, ar-SA)

- `AppStore/description-ios-he.txt`, `description-mac-he.txt`, `description-ios-ar-SA.txt`,
  `description-mac-ar-SA.txt`: translations of the English texts (the Mac one says scroll, not pinch), ≤ 4000
  characters, the same three checks as the catalog's strings (back-translation above all).
- `AppStore/keywords.txt`: `he=…` and `ar-SA=…`, ≤ 100 **bytes**: Hebrew and Arabic letters are 2 bytes in UTF-8,
  so about 45 characters including commas, roughly 7 keywords (fractal, Mandelbrot, Julia, zoom, mathematics,
  chaos, art, infinity, in that priority); checked with `LC_ALL=C awk '{ print length($0) - index($0, "=") }'`.
- `AppStore/app-info.txt`: `he|xFractal|<subtitle>` and `ar-SA|xFractal|<subtitle>`, ≤ 30 characters each (the
  name stays `xFractal`, Latin, as in ja).
- The five slide configs: `locales` gains `"he", "ar-SA"` after `"tr"`; every slide's `text` gains both, one caption
  per panel (the pair keeps two), titles broken with `\n` in two lines as the others (one line in
  `screenshots-mac.json`), subtitles translated from the English. The pair (`deep-zoom`, `"panels": 2`: one canvas
  two screenshots wide, the phone across the seam, cut into fixed clips `a` = left, `b` = right by `layout.mjs:plan`)
  is written as today: the first half of the sentence on `02-deep-zoom-a`, the second on `03-deep-zoom-b`. **Whether
  the Hebrew and Arabic storefronts show a locale's screenshots left to right or right to left is unverified** and
  cannot be checked before `/release` uploads them: an owed check of `/release` (open the live page on a device set
  to Hebrew, then Arabic). If the carousel runs right to left there, the phone's two halves meet only when `b` is
  displayed to the right of `a`, so the fallback is two-fold and needs no renderer change: swap the two captions in
  the he and ar-SA `text` arrays (the first half of the sentence then sits on clip `b`, read first) and upload the
  pair's two files in reverse order for those two locales (`03-deep-zoom-b.png` before `02-deep-zoom-a.png` in the
  `app-store screenshots` file list; the `/app-store-screenshots` skill's § 4 says so). The alternative — a
  per-locale pair order in the renderer — is not written until that check demands it.
- Rendered and reviewed, not uploaded: `app-store-screenshots --locale he,ar-SA` on each config (after the captures
  of C); the iPad and Duo configs with their `--captures` folders; the Mac config. Upload is `/release`'s job
  (its commands gain the two locales in G).

### E. Right-to-left headlines in the shared renderer (maestro)

- `layout.mjs`: `export const RTL_LANGUAGES = new Set(["ar", "he"]);` and `export function direction(locale) {
  return RTL_LANGUAGES.has(locale.split("-")[0]) ? "rtl" : "ltr"; }` — the second caller is the test; a store
  language is added here when a right-to-left one joins (fa, ur are not App Store locales today).
- `render.mjs:93-94`: the headline block becomes `<div class="text" dir="${direction(locale)}" style="left:…">`
  (the `<html lang>` stays as it is), and one CSS rule in `css()`: `.text[dir=rtl] h1 { letter-spacing:0; }`. The
  direction is set on the text alone, not on the page: a page-wide `dir=rtl` would also reverse the iPhone frame's
  status bar flex row (`.status`, the time and the glyphs swap sides) and the glyph order, a device-frame change
  nobody asked for (the search-results asset draws that status bar). With `dir=rtl` the `.text` block (absolute,
  `left:110px`, width `W - 220`, symmetric margins) aligns its lines to the right (`text-align: start`), `<br>` breaks
  hold, `fitHeadlines` keeps working (`scrollWidth`), the Mac's `text-align:center` is unchanged, and the phones stay
  where the config puts them (absolute positions do not mirror; the headline sits above the phone on every slide).
  The system font stack falls back to SF Hebrew / SF Arabic, which carry the 800 weight.
- The review page (`render.mjs:122-130`) needs no change: one row per locale, the files in display order, the
  Hebrew and Arabic headlines right-aligned inside their images. The log line "headline shrunk to Npx" tells when
  a Hebrew or Arabic title did not fit at 148 px.
- `~/GitHub/maestro/skills/app-store-screenshots/SKILL.md` (the reference) gets one sentence in its slides-file
  section: a right-to-left locale (`he`, `ar-SA`) is laid out right to left by the renderer; headlines are written
  as plain text, no marks. xFractal's copy says the same (G).

### F. The shared languages list (maestro)

`~/GitHub/maestro/global/languages.txt`, reach tier, after `tr Turkish` and before the optional `ru`/`id`:

```
ar-SA Arabic (Saudi Arabia), right to left: the App Store's one Arabic page, read across the Arab world
he Hebrew, right to left
```

Order (decision left open, default as shown): the tier's own rule is reach, and Arabic has many more readers than
Hebrew; the issue names Hebrew first only in its title. The exceptions paragraph gains: "xFractal ships he and ar in
the app too (since 2.3); the right-to-left checks a new language needs are in xFractal's
`planning/hebrew-arabic-rtl-plan.md`."

### G. Docs and skills (xFractal)

- `AGENTS.md` § Languages: "plus Spanish (`es`), …, Turkish (`tr`), Hebrew (`he`) and Arabic (`ar`)", "all nine
  translations", "The App Store page has eleven: … tr, he and ar-SA", every `--lang fr,de,it,es,pt-BR,ja,tr` becomes
  `--lang fr,de,it,es,pt-BR,ja,tr,he,ar` (lines 74, 87, 113); a sentence on right to left: the UI mirrors on its own
  (`.leading`/`.trailing`), the fractal never does (its view and gestures are in its own coordinates), numbers are
  Western digits everywhere (`iterationsLabel`, `Text(verbatim:)`), and `--lang he,ar` on the gallery scripts is how
  a right-to-left screen is checked.
- `.claude/skills/release/SKILL.md`: "Ten notes files … `-he.txt` and `-ar-SA.txt`" (Hebrew in gender-neutral
  forms, Arabic in Modern Standard Arabic, formal address), "The first release with Hebrew and Arabic (2.3) says so
  first", the `--notes`, `--add-locale`, `--description` lines gain the two locales, "2.3 adds `he` and `ar-SA` to
  the listing".
- `.claude/skills/app-store-screenshots/SKILL.md`: eleven store languages in order, every `--lang` list, the
  right-to-left sentence of E; `description:` says "each of the eleven store languages"; § 4 (upload) gains the
  storefront-order check of Design D and its fallback (he and ar-SA: the pair's files in reverse order and the
  captions swapped, only if the live page shows the carousel right to left).
- `.claude/skills/preview-gallery/SKILL.md:37` and `.claude/skills/develop/SKILL.md:186`: the language lists.
- `RELEASING.md:27` is stale already ("English, French, German and Italian"): it points at the `/release` skill's
  list instead of naming languages.
- `README.md` lists no languages: unchanged.

## Alternatives rejected

- **Locale digits everywhere** (`.formatted()` on the iOS iterations, the exponent and the Julia values): follows
  the user's Numbers setting under ar-SA, but mixes Eastern digits with the superscript Western digits of `z³`,
  `z⁸`, `z⁴` (no Arabic-Indic superscripts exist) and touches six call sites instead of one. Kept as the alternative
  of the decision below.
- **Pinning the fractal to `.environment(\.layoutDirection, .leftToRight)`** now: nothing in the fractal's drawing
  or coordinate math reads the layout direction (Facts), so the pin would guard against nothing shown; it is the
  one-line fallback if the device check finds a flipped pan or pinch anchor (Risks).
- **A language pass or an RTL scenario in the gallery**: the gallery is English only by rule
  (`/preview-gallery`); the store captures in `he` and `ar` already render the screens the issue names.
- **Restricting the `--lang` runs to `SnapshotGalleryTests`** so the right-side assertions never run under RTL:
  hides the harness's own column assumptions, which the iPad store capture needs anyway (`fractalRegion` under a
  left-hand column).
- **`Intl.Locale.prototype.getTextInfo()` for the direction**: not in every Node the renderer runs on, and a
  two-entry set states exactly which store locales are right to left.
- **An `InfoPlist.xcstrings`** for the display name: `xFractal` stays Latin in every language (as the store name).
- **The two `knownRegions` lines by hand** (918f50e's method, revision 1 of this plan): the project is generated
  from `project.yml` (`AGENTS.md` § Project regeneration); a hand edit that happens to match the generator is still a
  hand edit, and the scheme drift it avoided is harmless (Facts). Regenerate.
- **`dir` on `<html>`** (revision 1): simpler to write, but it mirrors the device frame's status bar too (Design E).
- **A per-locale pair order in the renderer** for right-to-left storefronts: not until the live page shows the
  carousel runs right to left (Design D); the upload-order fallback needs no code.

## Test plan (red first)

- `Tests/LocalizationTests.swift`
  - `testIterationsLabelKeepsWesternDigits`: `localized({ var s = ViewState.defaultState; s.maxIterations = 250; return s }().iterationsLabel, "ar-SA")`
    contains `"250"` and not `"٢٥٠"`; `localized(…, "en") == "Iter 250"`; `localized(…, "he")` ends with `" 250"`.
    Red proof: with `LocalizedStringResource("Iter \(maxIterations)")` (Int interpolation) the Saudi string reads
    `Iter ٢٥٠` (Facts: Foundation formats the arguments in the resource's locale); green with `String(maxIterations)`.
    Run and seen red for that reason before the key change; if `String(localized:)` turns out not to localize the
    argument in a test host, the test is dropped as proving nothing and the `--lang ar` Mac capture is the check.
  - `testCatalogIsFullyTranslated` with `languages` = nine: red while any of the 30 keys lacks `he` or `ar`, red on
    the stale `Iter %u` until `--delete-stale`; green at the end of step 4.
  - `testPaletteLabelsAreTranslated`: `Palette.gray.label` in `he` and `ar` (the sample pattern of the `ja` line).
- `scripts/test_snapshot_gallery.sh` `pool_regions`: red on `--lang ja,pt-BR,he,ar` until the whitelist and the two
  region arms exist (exit 2 before, `-testLanguage he -testRegion IL` and `-testLanguage ar -testRegion SA` called
  after). `python3 -m unittest discover -s scripts -p 'test_preview_gallery.py'` stays green (no language whitelist
  in `preview-gallery.py`).
- `GalleryScenarioTests` (iOS, run by `scripts/snapshot-gallery.sh --lang he`): the direction-sensitive tests (200,
  217, 243, 327, 351 and the two inset tests 347, 365) are red under Hebrew before the harness change (the list is at
  `minX == 0`, not `maxX == width`; the region lies right of the column; the capsule shifts left of the fold; the
  injected right inset is not the trailing one) and green after; still green in English (`scripts/snapshot-gallery.sh`,
  the full gallery, `CHECK OK`).
  - `testMirroredCaptureFailsTheReference`: red proof is the test's own negative — a horizontally flipped capture of
    `board-julia-spiral-chromatic` must fail `validate` (correlation below 0.95) while the unflipped one passes; if
    the flipped capture passed, the comparison would be too loose to prove the fractal unmirrored and the plan
    would need a tighter check (Risks).
- `~/GitHub/maestro/tools/app-store-screenshots/layout.test.mjs`: `direction("he") === "rtl"`, `direction("ar-SA") ===
  "rtl"`, `direction("en-US") === "ltr"`, `direction("it") === "ltr"`; red until `direction` exists. The `dir`
  attribute and the letter-spacing rule are in `render.mjs`, which has no test: checked on the rendered PNGs
  (`.build/app-store-screenshots/he/*.png`, `ar-SA/*.png`: right-aligned headline, joined Arabic letters, no
  "headline shrunk" line for a title that fits).
- The owed visual checks, through the captures of C and the renders of D, reviewed by the implementer and shown to
  Jean: bottom bar mirrored (type name on the right, chevron on the left), sliders filling from the right, the
  Controls sheet mirrored (the iteration and Julia sliders, the Multibrot stepper, the Newton polynomial picker, the
  presets' scroll, the Replay/Stop buttons and their icons), the iPad column on the left, the fractal identical to
  its English capture, Western digits, the Julia minus sign on the left of its number, the Duo capsule off the centred
  fold, the Mac HUD mirrored, the headlines right to left. On devices (no test can drive them): pan, pinch and the Mac
  scroll-wheel zoom under a Hebrew system language; the peek capsule on a real iPhone Duo half folded under Hebrew
  (the production `reservedRegions` read, off-centre by construction). After `/release` uploads: the storefront's
  screenshot order on a device set to Hebrew and Arabic (Design D).

Every new entity reaches its screen through the production path: `iterationsLabel` is written in `ViewState` (`FractalState.swift`)
and read by `ContentView.swift:285` (the Mac HUD, captured by `scripts/snapshot-mac.sh --lang ar`); the he/ar catalog
units are read by `Text(…)` in both apps (captured by `--lang he,ar`); `direction()` is read by `render.mjs` for the
`dir` of every headline block.

## Invariants (AGENTS.md and the develop skill)

- Pure logic in `FractalMath.swift`/`FractalState.swift`, tested: **holds** (`iterationsLabel` on `ViewState` in `FractalState.swift`
  with its test; `peekShift` unchanged).
- Math platform-agnostic, `#if os` only for UI: **holds** (no math changes).
- Product `xFractal`, bundle id, scheme names: **holds**.
- No `#Preview`, every screen state a scenario: **holds** (no new screen state).
- The project generated from `project.yml`: **holds**: step 4 runs `xcodegen generate` and commits its output
  (`knownRegions` from the catalog, the schemes in xcodegen's form); `project.yml` changes only if decision 5 adds
  `productName`.
- `docs/appcast.xml` frozen: **not applicable** (`git diff --exit-code main -- docs/appcast.xml` in the gate).
- Saved state (`Codable` in `UserDefaults`): **not applicable** (no stored property changes; `iterationsLabel` is
  computed).
- Numeric precision, Swift/Metal agreement: **not applicable**.
- Public-repo hygiene: **holds** (no absolute `/Users/…` path, no personal data; maestro named by `~/GitHub/maestro`
  as `AGENTS.md` already does).
- Strings: every user-facing string in the catalog with every translation: **holds** (nine languages; the gate
  `catalog-sync --check --skip-build` and `LocalizationTests`).
- The gallery English only: **holds** (`--lang` only for the store captures).

## Risks and rollout

- **Gesture mirroring.** If SwiftUI reported `MagnifyGesture.startAnchor` or `DragGesture.location` mirrored under
  RTL, a pinch would zoom about the mirrored point and a pan go the wrong way. Nothing in Apple's model suggests it
  (gesture values are in the view's own coordinate space), but only a device run shows it: step 5's owed check.
  Fallback: `.environment(\.layoutDirection, .leftToRight)` on the `FractalView` and its `.gesture(viewGestures)`
  (`ContentView.swift:53-55`), placed inside the `.padding(.trailing, boardTrailingPadding)` so the padding keeps
  following the inspector.
- **The peek capsule on a fold** (Duo). `.offset(x:)` mirrors under RTL; the fold frames from `reservedRegions`
  mirror by default too (`layoutDirectionBehavior: .mirrors`), so `peekShift`'s positive-is-trailing shift should
  land off the fold on the trailing (left) side. The gallery cannot confirm or refute this: its
  `foldRegionsOverride` bypasses the production `reservedRegions` read and its hinge is centred (Facts), so a
  mirrored frame equals the unmirrored one and the RTL-aware test 327 only shows that the shift goes to the trailing
  side. The check is a real iPhone Duo half folded under Hebrew (owed, step 5); the fix, if the capsule sits on the
  fold, follows what the device shows — reading the regions with `layoutDirectionBehavior: .fixed` and applying the
  shift in a left-to-right-pinned frame, or negating the offset — and is not written in advance.
- **Bidi of the Julia values.** `"-0.7000"` in a right-to-left paragraph may show as `0.7000-`: the `he` capture of
  `controls-julia-large` and the Mac panel show it; the fix is in Design A.
- **Headline typography.** Arabic letters pulled apart by `letter-spacing:-4px` (handled by the `[dir=rtl]` rule);
  a long Hebrew/Arabic title shrunk below 148 px (the renderer logs it; shorten the title); SF Hebrew/SF Arabic at
  weight 800 (checked on the PNGs).
- **The pair's reading order in right-to-left storefronts** (Design D): unverified until `/release` uploads and the
  live page is opened on a device in Hebrew and Arabic; the fallback (captions swapped, the pair's files uploaded in
  reverse order for those locales) needs no code.
- **The reference comparison too loose to see a mirror**: if `testMirroredCaptureFailsTheReference` passed a flipped
  capture (a correlation above 0.95 on a near-symmetric region), the fractal's non-mirroring would rest on eyes alone;
  the fixture is then changed to a more asymmetric one before loosening anything else.
- **Keyword budget.** 100 bytes is about 45 Hebrew/Arabic characters: fewer keywords than the other locales; the
  byte count is checked before the commit (Design D).
- **Translation quality.** Thirty short strings and four page texts per language, written by the implementer and
  checked three ways (Design B); Jean reads neither language, so the back-translation is the review. Anything the
  checks flag goes into the plan's implementation log with its decision.
- **Both platforms.** The catalog is shared; the Mac build is in the test gate; `scripts/snapshot-mac.sh --lang he,ar`
  shows the Mac HUD and panel mirrored and the slider labels on the left.
- **Xcode Cloud** (`ci_scripts/ci_post_clone.sh`): unaffected (catalog and metadata only; no dependency).
- **Rollout.** Nothing ships from this plan. 2.3's What's New says first that the app is now available in Hebrew and
  Arabic (`/release`, G); the store page gains the two locales at release time (`app-store metadata --add-locale he
  --add-locale ar-SA --name he=xFractal --name ar-SA=xFractal …`), then their screenshots (`/app-store-screenshots`
  § 4) for the iPhone, the iPad, the Duo and the Mac.

## Decisions left open for Jean

1. **Digits** (Design A). Default: **Western digits everywhere**, also under ar-SA (a math tool; `z³`, `n = 4`,
   `c = -0.7000` are notation; Hebrew and most Arabic regions use Western digits; one call site changes). Alternative:
   locale digits everywhere (`.formatted()` on six call sites, Eastern digits beside Western superscripts under
   ar-SA).
2. **Pin the fractal's layout direction now?** Default: **no** — nothing in it reads the direction; add the one
   line only if the device check (Risks) shows a flipped pan or pinch anchor.
3. **Order in `languages.txt` and in every locale list** (Design F). Default: **ar-SA before he** (the reach tier's
   own rule: reach order; Arabic has far more readers). Alternative: he first, as the issue's title names them. The
   choice fixes the order in `locales`, `app-info.txt`, `keywords.txt`, the skills and the store page's
   screenshot upload order; the plan writes "he, ar" in prose only where the issue does.
4. **Translator.** Default: the implementation subagent writes the he and ar strings and page texts, checked by the
   three methods (glossary, Wikidata, blind back-translation by Codex). Alternative: Jean has a native reader look
   at the 30 strings and the subtitle before 2.3 ships (the back-translation report lists what to show them).
5. **`productName: xFractal` on both targets in `project.yml`** (Facts: the schemes). Default: **add it** in step 4 —
   two lines, so the regenerated schemes keep `BuildableName xFractal.app` / `xFractal.app` as Xcode saves them and
   the checked-in schemes stop flipping between xcodegen's and Xcode's form (the remaining differences, the scheme
   `version` and the empty blocks, are Xcode's to rewrite and harmless). Alternative: leave `project.yml` alone and
   commit xcodegen's `BuildableName xFractal-MAS.app` / `xFractal-iOS.app`; both build (the gates), Xcode rewrites
   them on its next save.

## Decisions taken (Jean, 2026-10-27, go)

All five defaults: (1) Western digits everywhere, also under ar-SA; (2) no layout-direction pin on the fractal unless
the device check shows a flipped gesture; (3) `ar-SA` before `he` in the shared list and in every locale list;
(4) the implementation subagent translates, checked with Apple's glossary, Wikidata and a blind back-translation;
(5) `productName: xFractal` on both targets in `project.yml` before the regeneration.

## Steps

1. **[maestro] languages.txt: Arabic and Hebrew, right to left** — the two reach lines of Design F and the
   exceptions sentence; committed in `~/GitHub/maestro` (`global/languages.txt` only).
2. **[maestro] app-store-screenshots: right-to-left headlines** — `direction()` and `RTL_LANGUAGES` in `layout.mjs`
   with the four assertions in `layout.test.mjs` (red first, `node --test tools/app-store-screenshots/`), `dir` on
   each `.text` block and the `.text[dir=rtl] h1` rule in `render.mjs`, one sentence in the reference
   `skills/app-store-screenshots/SKILL.md`; committed in `~/GitHub/maestro`.
3. **Western digits for the iteration label** — `testIterationsLabelKeepsWesternDigits` red, `ViewState.iterationsLabel`,
   `ContentView.swift:285`, `catalog-sync` (`Iter %@` with the seven translations moved, `Iter %u` deleted with
   `--delete-stale`, `--check --skip-build` clean); test gate green.
4. **Hebrew and Arabic in the app** — the 60 catalog units with the three checks (findings in the implementation
   log), `productName: xFractal` in `project.yml` (decision 5), `xcodegen generate` with the regenerated project and
   schemes committed, `LocalizationTests` (`languages`, the two sample assertions); test gate green (the catalog test
   now covers nine languages; the gate drives the regenerated `xFractal-MAS` scheme), `catalog-sync --check
   --skip-build` clean.
5. **The gallery scripts and harness under right to left** — the `--lang` whitelists, `he → IL` / `ar → SA`,
   `pool_regions` (red first), the direction-aware harness, the seven direction-sensitive scenario tests and
   `testMirroredCaptureFailsTheReference`; then the store captures in `he,ar` on the iPhone, the iPad, the Duo and the
   Mac plus the review run (Design C), reviewed against the owed-check list (Test plan); the Julia `Text`s pinned only
   if those captures demand it (the plan's log says what was seen); the full English gallery still `CHECK OK` (it
   drives the regenerated `xFractal-iOS` scheme); `scripts/test_snapshot_gallery.sh` and the Python contract tests
   green.
6. **The App Store page in Hebrew and Arabic** — four descriptions, two keyword lines (byte-checked), two app-info
   lines, `he`/`ar-SA` in the five slide configs with headlines for every slide; `app-store-screenshots --locale
   he,ar-SA` on each config rendered and reviewed (right-aligned headlines, joined letters, nothing shrunk), nothing
   uploaded.
7. **Docs and skills** — `AGENTS.md`, the four skills, `RELEASING.md:27` (Design G); docs-only gate.

## Implementation log

(Filled in by the implementation: the translation checks' findings and decisions, what the right-to-left captures
showed and which of the conditional fixes of Design A and Risks were needed.)

### Step 3 (Western digits)

- Red proof: `ViewState.iterationsLabel` first written with the integer interpolation (`\(maxIterations)`, a `UInt32`);
  `testIterationsLabelKeepsWesternDigits` failed with `XCTAssertFalse failed - Iter ٢٥٠` (the ar-SA string), the right
  reason. Green with `String(maxIterations)`.
- Deviation: `catalog-sync` now refuses a project whose catalog targets do not set `SWIFT_EMIT_LOC_STRINGS = YES`
  (maestro's tool changed after the plan was written). `project.yml` gained `SWIFT_EMIT_LOC_STRINGS: YES` in the base
  settings; `xcodegen generate` regenerated the project (pbxproj plus both schemes in xcodegen's form; decision 5's
  `productName` follows in step 4 as planned).
- `catalog-sync` (with build): `Iter %@` added, `Iter %u` stale; the seven translations moved to `Iter %@` by a
  scratchpad script, `--skip-build`, `--delete-stale --skip-build` and `--check --skip-build` all print "catalog
  unchanged". The macOS suite counts 81 tests (AGENTS.md still says 73).
- Warnings check: both targets build with exit 0; the only `warning:` lines are the toolchain's (appintentsmetadataprocessor
  "Metadata extraction skipped" and "ONLY_ACTIVE_ARCH=YES requested with multiple ARCHS"), none in our sources.

### Step 4 (Hebrew and Arabic in the app)

- Written by `catalog_he_ar.py` (scratchpad, 30 keys x 2 languages, `translated`); `catalog-sync --skip-build` and
  `--check --skip-build` print "catalog unchanged". Red proof: with the new tests and the pre-step catalog,
  `testCatalogIsFullyTranslated` failed 60 times with "<key> has no he/ar translation" (and the Hebrew/Arabic
  `Palette.gray` assertions).
- Apple's glossary (the AppKit `.loctable` files, `plistlib`): Done he סיום / ar تم, Reset איפוס / إعادة تعيين, Stop עצירה /
  إيقاف, Type סוג / النوع, Gray אפור / رمادي, Exponent חזקה / الأس, Hot חם / حار, Cold קר / بارد: all adopted except ar Hot,
  where `حار` is the weather word (spicy, hot weather): `ساخن` is used for a colour temperature. The glossary has
  nothing for Controls, Appearance, Palette, Replay, Smooth, Real, Imaginary, Iterations, Polynomial: the forms used are
  Apple's usual ones (פקדים / عناصر التحكم, מראה / المظهر, לוח צבעים / لوحة الألوان, הפעלה חוזרת).
- Wikidata labels (the API rate-limits; the terms it answered): polynomial פולינום / متعددة الحدود (ar adopted in the
  noun form `متعددة الحدود`), exponentiation חזקה / رفع أسي (ar `الأس` for the field label, as Apple), real part חלק ממשי /
  جزء حقيقي, imaginary part חלק מדומה / جزء تخيلي, dendrite דנדריט (Wikidata's ar `زائدة شجرية` is the neuron's; the
  fractal preset uses the transliteration `دندريت`), galaxy גלקסיה / مجرة, Douady rabbit ar أرنب دوادي (rabbit adopted),
  Julia set קבוצת ז'וליה / مجموعة جوليا (the `Julia c` strings use ז'וליה / جوليا). No Wikidata label for fractal in he or
  ar, nor for spiral: `פרקטל`, `ספירלה` (usual), `كسيري`, `حلزون` (Arabic Wikipedia's title for the geometric spiral).
- Blind back-translation by Codex (read-only), 60 strings, drifts read one by one. Kept, with reason: he Done "Finish"
  (Apple's own `סיום`); he Exponent "Power" (Apple's `חזקה`, also Wikidata's exponentiation); both Perturb and
  Perturbation "Disturbance" (`הפרעה` / `اضطراب` are the standard perturbation-theory terms); he Smooth "also means
  part" (an adjective `חלק` for a toggle, fine in context); he "Iter. %@" unrecognised without context (the same
  abbreviation convention as the other languages); ar Dendrite and Chromatic "specialised loanwords" (the names
  of the presets and the palette, as in the other languages); ar Spiral "also snail" (the geometric term). Changed: ar
  Replay `إعادة التشغيل` read as "Restart", so it is now `إعادة العرض` and Stop Replay `إيقاف إعادة العرض`.
- Both schemes and the project regenerated with `productName: xFractal` on both app targets (decision 5): the pbxproj
  gains `ar` and `he` in `knownRegions`, the app product references become `xFractal.app`; the schemes keep
  `BuildableName xFractal.app`. Gate: macOS suite 81 tests (1 skipped) green on the regenerated `xFractal-MAS`; the
  warnings build of both targets exit 0 (the `xFractal-iOS` scheme is driven by step 5's gallery).
- `testIterationsLabelKeepsWesternDigits` checks the Saudi string by Unicode scalar: `String.contains("٢٥٠")` matched
  the Western `250` once the Arabic unit existed (the comparison folds the digit forms), a false failure.

### Step 5 (gallery scripts and harness under right to left)

- Red proofs. `pool_regions` on `--lang ja,pt-BR,he,ar`: exit 2 before (6 FAIL lines), green after the whitelist and the
  `he -> IL`, `ar -> SA` arms. The harness under Hebrew before the change (`scripts/snapshot-gallery.sh --lang he --only
  board-julia`): `testColumnPresentsTheFormBesideTheBoard` (:200, :203), `testControlsSurviveSizeClassChange` (:243),
  `testOverlayColumnIsRecognisedDespiteADeviceInset`, `testReferenceComparisonBesideAColumn` failed; green after (the
  `GalleryMount` gains `rightToLeft`, `trailingWindowEdge`, `trailingEdge(of:)`; `columnFrame`, `columnOverlaysBoard`,
  the slide-in wait and `fractalRegion` follow the direction; the seven tests mirror as pairs; the two inset tests inject
  the 84 pt inset on the trailing side). `testMirroredCaptureFailsTheReference` (new): the flipped capture of
  `board-julia-spiral-chromatic` fails `validate` in `corr` mode with correlation below 0.95, the unflipped passes.
- Deviation 1, `scripts/preview-gallery.py`: the Duo folded scenario failed the gallery's own check under `he`
  ("peek capsule not on the trailing side of the fold"): the check assumed the capsule right of the fold. Under he and ar
  it now requires the capsule to end before the fold's left edge (and off the fold); three contract tests added. The
  distance from the fold is not judged right to left: the capsule lands 84 pt (one device inset) further from the fold than
  the minimal position, because the gallery's override rect is physical while the peek's `.offset(x:)` mirrors (the
  production `reservedRegions` mirror too: owed device check on a real half-folded Duo). It is still off the fold, on the
  trailing (left) side.
- Deviation 2, the Julia minus sign: the Mac panel showed "0.1230-" under he (minus on the right); iOS showed "-0.1230".
  `.environment(\.layoutDirection, .leftToRight)` on the `Text` did not change it (bidi base direction comes from the
  window), so a pure function `juliaValueLabel` (FractalState.swift, tested) wraps the number in a left-to-right isolate
  (U+2066 ... U+2069); the four Julia value `Text`s use `Text(verbatim: juliaValueLabel(...))`. The Mac capture then shows
  "-0.1230". The macOS suite counts 82 tests.
- Captures (he and ar, iPhone, iPad, Duo, Mac; the review run included), what was seen:
  - bottom bar (peek capsule): mirrored, the play button on the left and the type name on the right, the iteration count
    between; digits Western.
  - sliders: filled from the right (minimum on the right) on the iPhone sheet, the iPad column and the Mac HUD and panel.
  - icons: play, stop, reset arrow and trash unmirrored, on the leading (right) side of their rows.
  - Controls sheet: mirrored (labels right, values left, Done button on the left, preset chips scrolling from the right,
    Multibrot stepper and "n = 5", Newton picker "z8 + 15z4 - 16" in its own order).
  - iPad: the column on the left, the board to its right, sliders mirrored.
  - Duo: capsule off the centred fold, on its left (trailing) side.
  - Mac: HUD and panel mirrored, the title on the right, the iteration label "איט׳ 512" / "تكرار 512" in Western digits.
  - the fractal is not mirrored: `magick compare` of the top 1400 px of he and ar against the English capture of
    board-mandelbrot-first-launch, board-julia, board-multibrot, board-newton, board-mandelbrot-deep-zoom-chromatic:
    RMSE 0 (identical pixels).
  - the Julia minus sign: iOS "-0.1230" without help; Mac fixed as above.
- Gates: macOS suite 82 tests green; warnings builds of both targets exit 0 (toolchain lines only); the full English
  gallery ends `CHECK OK [en]: 26 cards, light and dark complete and correctly rendered`; he and ar CHECK OK on the
  iPhone, iPad and Duo; `scripts/test_snapshot_gallery.sh`: all lifecycle checks passed; `test_preview_gallery.py`: 62 OK.

### Step 6 (the App Store page in Hebrew and Arabic)

- Files: four descriptions (1250 to 1420 characters), `keywords.txt` (`he` 94 bytes, `ar-SA` 97, checked with
  `LC_ALL=C awk '{ print length($0) - index($0, "=") }'`), `app-info.txt` (subtitles 23 characters each, name `xFractal`),
  `he` and `ar-SA` in the five slide configs (`locales` after `tr`, a caption per panel). `header.json` and
  `search-results.json` are English-only assets and unchanged. Order: `ar-SA` before `he` everywhere (decision 3), after `tr`: fix 1 applied it to the
  locale lists, files and configs, which step 6 had first written he-first.
- Blind back-translation by Codex of the subtitles, both descriptions and all headlines. Read one by one. Changed:
  Arabic gender (the intro makes the app feminine, so "resumes" and "free and open source" are now `تكمل`,
  `مجانية ومفتوحة المصدر`); Arabic `وحدة GPU` ("GPU unit") became `معالج الرسومات` in the headlines (the description keeps
  the full term with `(GPU)`); the Arabic families title `أربع عائلات من الأشكال الكسيرية` shrank to 128 px, shortened to
  `أربع عائلات كسيرية` (no "headline shrunk" line afterwards). Kept: palette names masculine singular (they are the
  app's fixed labels, Hot/Cold = `חם/קר`, `ساخن/بارد`), `San Marco` and `Multibrot` in Latin script (the app's own names),
  `צבטו` / `اقرص` for pinch (the verb the platform's own Hebrew and Arabic use), `Mac` scroll as `גללו` / `مرّر`.
  Hebrew addresses the user in the masculine plural (the usual generic form) and the app in the feminine.
- Rendered, reviewed, not uploaded: `app-store-screenshots --locale he,ar-SA` on all five configs (iPhone, iPad, Mac,
  Duo inner, Duo outer; the English iPad, Duo and Mac captures were rendered with `--only` first, the Mac config needs
  `--captures previews`). Read: iPhone he deep-zoom-a, ar-SA hero and families; Mac ar-SA controls; Duo inner he
  deep-zoom-b. Headlines are right-aligned, Arabic letters are joined (no letter-spacing), nothing shrunk, the phones
  sit where the config puts them. The pair's two captions are in reading order (first half on `a`); the storefront's
  carousel direction stays an owed check of `/release` (Design D).

### Step 7 (docs and skills)

- `AGENTS.md` (nine translations, eleven store languages, `--lang ... ,he,ar` everywhere, a right-to-left paragraph, the
  test count now 82), the `/release`, `/app-store-screenshots`, `/preview-gallery` and `/develop` skills (Design G, the
  storefront-order check and its fallback in the screenshots skill § 4), `RELEASING.md` (points at the skill's list).
  Docs-only gate: `git diff --check` clean, no absolute home path or email in the touched files.

### Fix 2 (Codex implementation review, no blockers)

- Accepted: `preview-gallery.py` judges a peek capsule beside a fold with one rule in both directions (x mirrored into the
  left-to-right frame under he/ar); right to left the 40 pt tolerance is widened by the scenario's device inset (84 pt),
  so a capsule far from the fold fails again (contract test: 60 pt out passes with the inset, fails without; 180 pt out
  fails). The column test's containment now compares the list with the board's frame (independent of the list), both
  directions. `testIterationsLabelKeepsWesternDigits` also covers `he`.
- Rejected: sharing the `--lang` whitelist and `region()` between the two scripts (self-contained since 918f50e; two
  four-arm case statements); no cheap Mac-script mapping test exists in `test_snapshot_gallery.sh`, none added.
