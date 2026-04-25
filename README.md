# Fractals

A SwiftUI + Metal Mandelbrot renderer for iOS and macOS. The fragment shader does all the work; the CPU just uploads ~24 bytes of uniforms per frame.

## Build

XcodeGen owns the project file — the `.xcodeproj` is generated and gitignored.

```sh
xcodegen generate
open Fractals.xcodeproj
```

Build & run on macOS or any iOS Simulator. No code signing needed for local development.

## Controls

| | macOS | iOS |
|---|---|---|
| Pan | drag | drag |
| Zoom | scroll wheel (cursor-anchored) or trackpad pinch | pinch |
| Iteration count | HUD slider | HUD slider |

## Precision roadmap

The Mandelbrot set is a precision sink: every order of magnitude of zoom eats roughly one decimal digit out of the coordinate type. With single-precision `float` (the current state), banding appears around scale ≈ 1e-6.

Apple's Metal Shading Language **does not support `double` in shaders** on any Apple GPU — there is no flag to flip. So deep zoom requires emulation or a different algorithm:

| Tier | Technique | Zoom floor (scale) | Status |
|---|---|---|---|
| 1 | Single-precision `float` | ~1e-6 | superseded |
| 2 | Double-float ("DD") emulation in MSL — pair of `float`s `(hi, lo)` per coordinate, ~14 decimal digits | ~1e-13 | shipped (default) |
| 3 | CPU reference orbit + per-pixel `float` perturbation deltas (Pauldelbrot, 2013) | with `Double` reference: ~1e-15. With future bignum reference: effectively unlimited | shipped — toggleable in HUD |
| 4 | Add BLA (Bivariate Linear Approximation) and Pauldelbrot/Zhuoran glitch detection on top of tier 3 | same floor, 10–100× faster | future |

### Tier 2: double-float (current target)

Represent each coordinate as a pair `(hi, lo)` of `float`s where `lo` carries the rounding error of `hi`. Implement Dekker/Knuth `TwoSum` for add and `TwoProd` (using Metal's built-in `fma`) for multiply. Cost is ~10–20× slower per iteration but still fully GPU-parallel. Drop-in replacement for `float2` complex arithmetic in the existing shader.

CPU-side state (center, scale) moves to `Double`; the renderer splits each `Double` into `(hi, lo)` floats at upload time.

### Tier 3: perturbation theory (current — toggleable)

Pick one reference pixel (the screen center), compute its full orbit on the CPU, upload it as an `MTLBuffer<float2>`, then per-pixel iterate the *delta* from the reference using `dz_{n+1} = 2·Z_n·dz_n + dz_n² + dc` — `dc` and `dz` stay in `float` because their magnitudes are ~scale.

Toggle "Perturb" in the HUD to switch between DD (default) and perturbation.

**Reference selection.** Naive perturbation uses the screen center as the reference. If the center happens to land on a fast-escaping region, the reference orbit terminates early and *every* pixel using it is iteration-capped — so detail near the view edges collapses to flat color (the "Type 1 glitch" / reference-escape problem; see [Wikibooks: Fractals/perturbation](https://en.wikibooks.org/wiki/Fractals/perturbation)). To avoid this, the renderer probes a 5×5 grid of candidates across the visible region and picks the one with the longest orbit; the shader offsets `dc` by `(center − C0)`. Cost is ~25 × `maxIterations` `Double` ops per orbit recompute (sub-millisecond).

**Caveats of the current implementation:**

- The reference orbit is computed in `Double`, so the precision floor stays at ~1e-15 — the same ballpark as DD. To reach 1e-30+ zooms, the reference orbit needs **iteration extension** (continue past `|Z|>2` using a mantissa+exponent / floatexp representation; see [mathr.co.uk on deep zoom](https://mathr.co.uk/blog/2021-05-14_deep_zoom_theory_and_practice.html)). This is the natural next step.
- No glitch detection. When `|dz| ≈ |Z|`, the linearization breaks (Pauldelbrot's "Type 2 glitch"). Detection and rebasing is tier 4.

## Architecture

- `Shaders.metal` — full-screen triangle vertex shader; fragment shader runs the Mandelbrot iteration with smooth-iteration coloring (Inigo Quilez cosine palette). Two iteration paths: DD (default) and perturbation.
- `MandelbrotRenderer.swift` — Metal pipeline + per-frame uniform upload (`MTKViewDelegate`). Caches the reference orbit and recomputes only when center or `maxIterations` changes.
- `MandelbrotView.swift` — `MTKView` wrapped for SwiftUI on both platforms via `PlatformRepresentable` typealias. Custom `ZoomableMTKView` subclass on macOS handles cursor-anchored scroll-wheel zoom.
- `ContentView.swift` — gestures, HUD, state.
- `MandelbrotApp.swift` — `@main`.
