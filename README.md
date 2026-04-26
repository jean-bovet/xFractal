# Fractals

A SwiftUI + Metal fractal explorer for iOS and macOS. Reincarnation of the original 2008 Objective-C iOS app *xFractal*: same four families and palettes, now driven by a fragment shader that computes everything per pixel on the GPU. The CPU just uploads a small uniforms struct (and, for Mandelbrot perturbation, a reference orbit) per frame.

## Build

XcodeGen owns the project file — the `.xcodeproj` is generated and gitignored.

```sh
xcodegen generate
open Fractals.xcodeproj
```

Build & run on macOS or any iOS Simulator. No code signing needed for local development.

## Fractal families

Switch between four families from the HUD type picker. Each family keeps its own sensible default view; switching back preserves your palette/smooth choices.

| Family | Iteration | Per-type controls |
|---|---|---|
| **Mandelbrot** | `z ← z² + c`, `z₀ = 0` | iterations, perturbation toggle |
| **Julia** | `z ← z² + c`, `z₀ = pixel`, `c` fixed | iterations, `c.re`/`c.im` sliders, presets (Dendrite, Spiral, Rabbit, Galaxy, San Marco) |
| **Newton** | Newton's method for `p(z) = 0` | iterations, choice of polynomial: `z³ − 1`, `z³ − 2z + 2`, `z⁸ + 15z⁴ − 16` |
| **Multibrot** | `z ← zⁿ + c` | iterations, exponent `n` (2–8) |

## Palettes

Four color palettes ported from the original xFractal: **Hot**, **Cold**, **Gray**, **Chromatic**. A `Smooth` toggle enables the standard `nu = iter + 1 − log₂(½ log₂|z|)` smoothing for the escape-time families (Mandelbrot/Julia/Multibrot); Newton always uses integer iteration counts since it converges rather than escapes.

## Controls

| | macOS | iOS |
|---|---|---|
| Pan | drag | drag |
| Zoom | scroll wheel (cursor-anchored) or trackpad pinch | pinch |
| Iteration count | HUD slider | HUD slider |
| Family / palette / per-type knobs | HUD `…` panel | HUD `…` panel |
| Reset to family defaults | HUD button | HUD button |
| Replay journey | HUD button | HUD button |
| Clear journal | HUD trash button | HUD trash button |

## Persistence and replay

The full view state (family, center, scale, iterations, palette, smooth, julia c, multibrot n, newton flavor, perturbation toggle) is auto-saved to `UserDefaults` after every change and restored on launch. Every state change is also recorded into a **journal** of timestamped snapshots — drag deltas are coalesced (~50 ms throttle) so a long pan becomes a smooth path rather than thousands of stutters. The journal persists too, so `Replay` reanimates the entire exploration history (capped at 30 s; longer sessions are time-compressed). Scale interpolates logarithmically so zooms look natural during playback. Family/palette transitions snap rather than blend (interpolating across families would just look broken). Reset restores the family's default view but keeps the journal; the trash button clears the journal.

## Precision: deep-zoom (Mandelbrot & Julia)

The Mandelbrot set is a precision sink: every order of magnitude of zoom eats roughly one decimal digit out of the coordinate type. With single-precision `float`, banding appears around scale ≈ 1e-6. Apple's Metal Shading Language **does not support `double` in shaders** on any Apple GPU — there is no flag to flip. So deep zoom requires emulation or a different algorithm.

| Tier | Technique | Zoom floor | Status |
|---|---|---|---|
| 1 | Single-precision `float` | ~1e-6 | superseded |
| 2 | Double-float ("DD") emulation in MSL — pair of `float`s `(hi, lo)` per coordinate, ~14 decimal digits | ~1e-13 | shipped (default for Mandelbrot/Julia) |
| 3 | CPU reference orbit + per-pixel `float` perturbation deltas (Pauldelbrot, 2013) | with `Double` reference: ~1e-15. With future bignum reference: effectively unlimited | shipped — Mandelbrot only, toggleable |
| 4 | BLA (Bivariate Linear Approximation) + Pauldelbrot/Zhuoran glitch detection on top of tier 3 | same floor, 10–100× faster | future |

Multibrot/Newton run in single-precision `float` — the original xFractal used double on CPU and was much slower; for these families typical exploration depth doesn't need DD.

### Tier 2: double-float

Represent each coordinate as a pair `(hi, lo)` of `float`s where `lo` carries the rounding error of `hi`. Implement Dekker/Knuth `TwoSum` for add and `TwoProd` (using Metal's built-in `fma`) for multiply. Cost is ~10–20× slower per iteration but still fully GPU-parallel. CPU-side state (center, scale) moves to `Double`; the renderer splits each `Double` into `(hi, lo)` floats at upload time.

### Tier 3: perturbation theory (Mandelbrot only)

Pick one reference pixel, compute its full orbit on the CPU, upload it as an `MTLBuffer<float2>`, then per-pixel iterate the *delta* using `dz_{n+1} = 2·Z_n·dz_n + dz_n² + dc` — `dc` and `dz` stay in `float` because their magnitudes are ~scale. Toggle "Perturb" in the HUD.

**Reference selection.** Naive perturbation uses the screen center. If the center lands on a fast-escaping region, the reference orbit terminates early and *every* pixel using it is iteration-capped — detail near the view edges collapses to flat color (the "Type 1 glitch" / reference-escape problem). To avoid this, the renderer probes a 5×5 grid of candidates across the visible region and picks the one with the longest orbit; the shader offsets `dc` by `(center − C0)`.

**Caveats:** The reference orbit is computed in `Double`, so the precision floor stays at ~1e-15 — the same ballpark as DD. Reaching 1e-30+ zooms needs iteration extension (mantissa+exponent / floatexp). No glitch detection yet.

## Architecture

- `Shaders.metal` — full-screen triangle vertex shader; fragment shader dispatches on `fractalType` to one of four iteration kernels (Mandelbrot DD / Mandelbrot perturbation / Julia DD / Multibrot float / Newton float) and four palette functions (`hot`, `cold`, `gray`, `chromatic`).
- `FractalRenderer.swift` — Metal pipeline + per-frame uniform upload (`MTKViewDelegate`). Caches the Mandelbrot reference orbit and recomputes only when center/scale/iterations change.
- `FractalView.swift` — `MTKView` wrapped for SwiftUI on both platforms via `PlatformRepresentable` typealias. Custom `ZoomableMTKView` subclass on macOS handles cursor-anchored scroll-wheel zoom.
- `FractalState.swift` — `ViewState` (Codable), per-type defaults, journal, replay, debounced persistence.
- `ContentView.swift` — gestures, HUD, type/palette/per-type controls.
- `FractalsApp.swift` — `@main`.

## Inspiration

This rebuild draws from the retired 2008 Objective-C iOS app `xFractal` (Mandelbrot/Julia/Newton/Multibrot, Hot/Cold/Gray/Chromatic palettes, smooth-iteration coloring). The CPU iteration loops, palette curves, and Newton polynomials are direct ports; everything else is rewritten for SwiftUI + GPU.
