---
name: app-store-screenshots
description: Render xFractal's iPhone App Store screenshots (tilted phones, a headline in each of the nine store languages, a pair of screenshots sharing one phone) from the preview-gallery captures with the `app-store-screenshots` command, review them, and upload them once approved. Use when Jean asks for new or updated App Store screenshots, to change a headline, a slide or a phone's angle, or when `/release` says the screenshots must be retaken.
allowed-tools: Read, Edit, Bash, AskUserQuestion
---

# /app-store-screenshots: marketing screenshots from the gallery captures

The screenshots are rendered, never hand-made: the app's preview gallery captures every screen, and the
`app-store-screenshots` command (on PATH) lays the captures out on slides described in the repo's
`AppStore/screenshots.json`, renders each store language with headless Chromium, and writes a review page.
A public repo names the command, never where it comes from.

The app: xFractal, App Store product `xFractal-iOS` (`--app xFractal-iOS`). The captures come from
`scripts/snapshot-gallery.sh` (the `/preview-gallery` skill) and land in `previews/`. The slides file covers the iPhone
6.9" set (`APP_IPHONE_67`, 1320 x 2868). Store languages, in order: en-US, fr-FR, de-DE, it, es-ES, es-MX, pt-BR, ja, tr (both Spanish pages use the `es`
captures). What the captures cannot
show: the app's own text is in the store language only when the slides' captures were rendered in it, else English;
the captures are 2x (804 px wide). The localized captures, right before rendering the slides (the gallery itself stays
English): `scripts/snapshot-gallery.sh --only "board-julia,board-mandelbrot-deep-zoom-chromatic,board-mandelbrot-first-launch,board-multibrot,board-newton,controls-julia-large" --lang fr,de,it,es,pt-BR,ja,tr`
(`previews/fr/`, …), the same with `--device ipad` (`previews/ipad/fr/`, …), and `scripts/snapshot-mac.sh --lang
fr,de,it,es,pt-BR,ja,tr` (its four windows are the Mac slides: `previews/mac/fr/`, …). Keep the `--only` list in step with the
`capture` names in `AppStore/screenshots.json`.

## 1. Captures

Refresh the captures first when the UI changed since the last gallery run: the slides use the gallery's PNGs by
name (`"capture": "<slug>"` or `"<slug>.dark"`). A slide that needs a screen state the gallery does not have gets a
new gallery scenario (the `/preview-gallery` rules), never a hand-made capture. When the store pages show the app in
each language, re-render the slides' captures in those languages too (`--only` and `--lang`, see the slides file
below): stale localized captures show an older UI than the English one.

## iPad and Mac

- iPad: `scripts/snapshot-gallery.sh --device ipad` (captures into `previews/ipad/`), then
  `app-store-screenshots --config AppStore/screenshots-ipad.json --captures previews/ipad` (2048 x 2732,
  `APP_IPAD_PRO_3GEN_129`: the iPhone's slides and headlines, `"device": "ipad"` frames).
- Mac: `scripts/snapshot-mac.sh` (the real window, into `previews/mac/`), then
  `app-store-screenshots --config AppStore/screenshots-mac.json` (2880 x 1800, `APP_DESKTOP`: `"device": "window"`
  under a centred headline, `textStyle`). Upload with `--app xFractal-iOS --platform MAC_OS --display-type
  APP_DESKTOP`; the Mac version is its own version in App Store Connect.

## 2. Render

```sh
app-store-screenshots                      # every language -> .build/app-store-screenshots/<locale>/NN-<slide>.png
app-store-screenshots --locale en-US       # one language
```

It checks the slides first and stops with one line per problem: a language without text, captions that do not match a
slide's panels, a missing capture, more than the App Store's 10 screenshots. It reports a headline shrunk to fit.

## 3. Review

The review page (`.build/app-store-screenshots/index.html`) opens with one row per language, in store order. Look at
the PNGs yourself first (Read a few, the longest language above all): the headline reads, a phone is not cut where it
should not be, a pair's two halves line up. Then show Jean and wait for his go. Never upload what he has not seen.

## 4. Upload

Only inside `/release`, or when Jean asks: one call per language and display type, the files in their numbered order
(a pair's two halves must stay neighbours):

```sh
app-store screenshots --app xFractal-iOS --version <v> --locale <locale> --display-type APP_IPHONE_67 \
  .build/app-store-screenshots/<locale>/*.png
```

## The slides file (`AppStore/screenshots.json`)

- `displayType`, `width`, `height`: the App Store set it renders (iPhone 6.9": `APP_IPHONE_67`, 1320 x 2868).
- `locales`: the store languages, in store order.
- `slides`: in display order. Each has an `id`, a CSS `background`, `phones` (a `capture` and a CSS `style` that places
  and tilts it: `left`, `top`, `transform: perspective(...) rotateX/Y/Z(...) scale(...)`) and `text`: per locale, one
  `{ "title", "sub" }` per panel; `\n` breaks the title.
- Captures in the app's own languages: a capture `X` (or `dir/X`) shows as `<locale>/X` or `<language>/X` (`dir/fr/X`)
  in the locale that has one; a locale without one shows the English capture. The gallery itself stays English: render
  only the slides' captures in each other store language, right before rendering the slides (`scripts/snapshot-gallery.sh
  --only <the slides' captures> --lang fr,de`, the same for each device family). Never a full gallery in another
  language.
- `"device"` per phone: `"iphone"` (the default), `"ipad"` (a thin uniform bezel, no island: the iPad set, 2048 x 2732,
  `APP_IPAD_PRO_3GEN_129`, from an iPad gallery pass) or `"window"` (a Mac window capture shown at its natural size with
  a shadow, no frame: the Mac set, 2880 x 1800, `APP_DESKTOP`). A config-level `"textStyle"` adds CSS to every headline
  block (e.g. centred above a Mac window). One slides file per set; upload each with its own `--display-type` (the Mac
  set with `--platform MAC_OS`).
- A phone can also carry its device chrome: `"statusBar": "dark"` or `"light"` (9:41, signal, Wi-Fi and battery in the
  color the screen under them needs) and `"buttons": true` (action, volume and side buttons).
- `"panels": 2` makes a pair: one canvas two screenshots wide, cut in two, so one phone can lie across the seam. Its
  two titles read as one sentence ("A trillion times deeper" / "and every detail stays sharp").

## The product page header and the search results asset

On iOS 27 and later the App Store shows a creative asset at the top of the product page and in search results
(without one, it falls back to screenshots and previews). xFractal gives each its own image (a universal 5244 x 2950
image could serve both, but each place wants a different layout): PNG, no alpha, no text, one per placement for every
language. The sizes: a **universal** image 5244 x 2950 (16:9), the **header** 3840 x 1646 (21:9), the **search
results** asset 3:2 (1920 x 1280 to 3840 x 2560). Each has a slides file (`"max": 1`, one slide, no `text`: a text-less
image serves every language), rendered by the same command into `.build/app-store-<slides file name>/`:

```sh
scripts/snapshot-gallery.sh --only artwork                       # the full-size backgrounds, into previews/artwork/
app-store-screenshots --config AppStore/header.json              # -> .build/app-store-header/en-US/01-header.png
app-store-screenshots --config AppStore/search-results.json      # -> .build/app-store-search-results/en-US/01-search-results.png
```

- **Header** (3840 x 1646, 21:9): only the yellow Mandelbrot, whole and centered, no phone. The iPhone product page keeps
  just the middle of the header, so the set sits inside the header template's art safe area (x 1097..2743,
  y 493..1154, drawn on the review page).
- **Search results** (3840 x 2560, 3:2): the Mandelbrot on the left, an upright phone with its status bar and buttons
  (`"statusBar"`, `"buttons"`) showing the Julia Spiral in Chromatic (colour, little black: the
  `board-julia-spiral-chromatic` scenario) on the right, vertically centered and whole. The search template's
  art safe area is x 836..3004, y 765..1795.
- Simple, as Apple asks: a plain field, one motif, no tilt; a phone showing the app is upright with its device chrome,
  the way Apple's own examples look. `"backgroundImage"` names the full-size render among the captures
  (`artwork/<name>`); `"guides"` draw the art safe areas above on the review page (the universal one is
  x 1921..3323, y 660..1622). The backgrounds are `GalleryFixtures.artwork`
  (`mandelbrot-header`, `mandelbrot-search`) rendered at their exact size by the app's own Metal renderer: never upscale a
  screen capture to that size.
- Upload: `app-store creative --app xFractal-iOS --placement header FILE` (then `--placement search` with the other
  file; `both` would upload a universal image) puts it in the asset library (reused when the same file is already there); with `--version <v>` (an editable
  version) it is placed on every locale, replacing the previous one. It goes through App Review with that version.

## Rules

- The screenshots must show the app's real UI (App Review): tilted is fine, a mock-up of a screen the app does not have
  is not. Keep the tilt moderate so the UI stays readable.
- Headlines in every store language, written in the tone of that language's store description (formal or informal
  address as it does). Keep claims to what the description already says.
- No Apple product artwork in the repo: the phone is drawn in CSS by the renderer.
- The output (`.build/`) and the captures are not committed; the slides file is.

The slides today: the hero (Mandelbrot, orange), the deep-zoom pair (the `board-mandelbrot-deep-zoom-chromatic`
scenario, which exists for it, on green), the four fractal families (Newton, Julia, Multibrot fanned out) and the
Controls sheet. French uses "vous", German "Sie", Italian "tu", as the store descriptions do.
