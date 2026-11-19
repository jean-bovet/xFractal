# App Store screenshots

The iPhone App Store screenshots are rendered from the preview-gallery captures by the `app-store-screenshots`
command: tilted phones, a headline per store language, and a pair of screenshots that share one phone lying across the
seam. The slides (captures, phone angles, backgrounds, headlines in the eleven store languages) are in
`AppStore/screenshots.json`; the `/app-store-screenshots` skill renders, reviews and uploads them.

```sh
scripts/snapshot-gallery.sh          # the captures, into previews/en/
app-store-screenshots                # -> .build/app-store-screenshots/<locale>/NN-<slide>.png + index.html
```

- 1320 x 2868 (`APP_IPHONE_67`), at most 10 per language; files are numbered in display order, and a pair
  (`"panels": 2`) must stay adjacent.
- The captures are 2x (804 px wide). Each store language shows the app in its own language: `/app-store-screenshots`
  renders the slides' captures with `--only … --lang fr,de,it,es,pt-BR,ja,tr,ar,he` (the Mac: `scripts/snapshot-mac.sh --lang fr,de,it,es,pt-BR,ja,tr,ar,he`)
  right before the slides; the gallery itself stays English.
- iPad: `app-store-screenshots --config AppStore/screenshots-ipad.json --captures previews/ipad` (2048 x 2732,
  `APP_IPAD_PRO_3GEN_129`, the same slides and headlines in iPad frames). Mac: `--config AppStore/screenshots-mac.json`
  (2880 x 1800, `APP_DESKTOP`: the real window under a centred one-line headline; the hero says "scroll", not "pinch").
- iPhone Duo: `--config AppStore/screenshots-duo-outer.json` and `AppStore/screenshots-duo-inner.json` with `--captures previews/duo`,
  both sets uploaded together per locale with `app-store screenshots --display-class IPHONE_DUO` (`/app-store-screenshots` has the commands).

## Header and search results artwork

The product page header and the search results asset (iOS 27, no text, one image each for every language) are the same
command with `--config AppStore/header.json` (3840 x 1646: the whole yellow Mandelbrot, centered, no phone) and
`--config AppStore/search-results.json` (3840 x 2560: the Mandelbrot on the left, an upright phone with its status bar
and buttons showing the Julia Spiral in colour on the right, vertically centered). Their backgrounds are rendered full size by the
gallery run into `previews/artwork/` (`GalleryFixtures.artwork`); `app-store creative --placement header|search` uploads
them.
