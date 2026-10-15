# Gallery capture spike (iOS, Metal)

Question: can the no-`#Preview` gallery method (one app-hosted snapshot test renders every screen light and dark)
photograph xFractal, whose fractal is drawn by an `MTKView`?

Verdict: **GO** for iOS (the Mac target is out of scope).

## What works

Host `ContentView` in a `UIWindow` on the app's scene (as the reference does), then:

1. Find the `MTKView` in the hierarchy, set `isPaused = false` and call `draw()` once. In a test window the view
   starts paused (the scene phase is not active, so `FractalView` pauses it), and a paused view has never drawn:
   it photographs blank white.
2. `window.drawHierarchy(in:afterScreenUpdates: true)` at 2x. This captures the Metal layer together with the
   SwiftUI chrome and the presented sheet. No readback, no renderer change.

What does not work: `window.layer.render(in:)` (always blank where the Metal layer is, even unpaused), and any
capture of a paused `MTKView`. A drawable readback composited under the UI also works but is not needed.

`ContentView` gets a small seam: `init(store:showingSheet:)`, so a scenario can inject an in-memory `StateStore`
(own `UserDefaults` suite, any fractal type) and open the controls sheet. Defaults keep the app unchanged.

## Measured (iPhone 17 Pro simulator, iOS 27, 393x852 at 2x)

- 16 captures (4 fractal types, board and controls sheet, light and dark), two consecutive runs, all correctly
  lit; the fractal region is lit by the fractal, not black.
- About 1.2 s per capture, of which 1.0 s is deliberate settle sleep; `drawHierarchy` itself is 0.1 to 0.2 s.
- A first run without the explicit `draw()` produced one blank fractal (race with the sheet presentation); with it
  the 32 captures of two runs were all good.
- Warm `xcodebuild test` on a booted simulator: about 110 s total including the build of the test target.

## What an install needs

- The `xFractalGalleryTests` target (iOS unit tests hosted by the app, in `project.yml`) and the snapshot test,
  skipped unless a snapshot-directory variable is set.
- The reference scripts (`snapshot-gallery.sh`, `preview-gallery.py`, `preview-luminance.swift`) and the agent
  simulator.
- About 12 to 16 scenarios, because the app is one screen with one sheet: the board for each of the 4 fractal
  types, the controls sheet for each type (Julia, Newton and Multibrot add their own sections), the sheet at its
  large detent, the replay state, and an iPad size. The luminance check must judge the UI region only (the sheet
  and the HUD), since the fractal region is legitimately bright or dark.
