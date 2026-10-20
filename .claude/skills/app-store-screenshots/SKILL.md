---
name: app-store-screenshots
description: Render xFractal's iPhone App Store screenshots (tilted phones, a headline in English, French, German and Italian, a pair of screenshots sharing one phone) from the preview-gallery captures with the `app-store-screenshots` command, review them, and upload them once approved. Use when Jean asks for new or updated App Store screenshots, to change a headline, a slide or a phone's angle, or when `/release` says the screenshots must be retaken.
allowed-tools: Read, Edit, Bash, AskUserQuestion
---

# /app-store-screenshots: marketing screenshots from the gallery captures

The screenshots are rendered, never hand-made: the app's preview gallery captures every screen, and the
`app-store-screenshots` command (on PATH) lays the captures out on slides described in the repo's
`AppStore/screenshots.json`, renders each store language with headless Chromium, and writes a review page.

The app: xFractal, App Store product `xFractal-iOS` (`--app xFractal-iOS`). The captures come from
`scripts/snapshot-gallery.sh` (the `/preview-gallery` skill) and land in `previews/`. The slides file covers the iPhone
6.9" set (`APP_IPHONE_67`, 1320 x 2868). Store languages, in order: en-US, fr-FR, de-DE, it. What the captures cannot
show: the gallery renders English only, so the Controls sheet is English in every language; there are no iPad or Mac
captures, so those sets come from elsewhere; the captures are 2x (804 px wide).

## 1. Captures

Refresh the captures first when the UI changed since the last gallery run: the slides use the gallery's PNGs by
name (`"capture": "<slug>"` or `"<slug>.dark"`). A slide that needs a screen state the gallery does not have gets a
new gallery scenario (the `/preview-gallery` rules), never a hand-made capture.

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
- `"panels": 2` makes a pair: one canvas two screenshots wide, cut in two, so one phone can lie across the seam. Its
  two titles read as one sentence ("A trillion times deeper" / "and every detail stays sharp").

## The universal creative asset (header and search results)

On iOS 27 and later the App Store shows a creative asset at the top of the product page and in search results
(without one, it falls back to screenshots and previews). One **universal** image serves both: 5244 x 2950 PNG, no
alpha, one per placement and localization. `AppStore/creative-assets.json` describes it, rendered by the same command:

```sh
scripts/snapshot-gallery.sh --only artwork                        # the full-size background, into previews/artwork/
app-store-screenshots --config AppStore/creative-assets.json      # -> .build/app-store-creative-assets/en-US/01-universal.png
```

- Simple, as Apple asks: one slide, no text (the image serves every language). The background is
  `GalleryFixtures.artwork` (`mandelbrot-yellow`: the whole set small on the left of a yellow-orange field) rendered at
  5244 x 2950 by the app's own Metal renderer: never upscale a screen capture to that size. An upright phone with its
  status bar and buttons (`"statusBar"`, `"buttons"`) shows the Multibrot in the middle; its top sits in Apple's art safe
  area (x 1921..3323, y 660..1622, drawn on the review page) and it runs down past it, like Apple's sample.
- Upload: `app-store creative --app xFractal-iOS FILE` puts it in the asset library (reused when the same file is
  already there); with `--version <v>` (an editable version) it is placed as the header and the search results asset on
  every locale, replacing the previous ones. It goes through App Review with that version.

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
