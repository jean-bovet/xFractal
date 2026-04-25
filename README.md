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
| 1 | Single-precision `float` | ~1e-6 | initial commit |
| 2 | Double-float ("DD") emulation in MSL — pair of `float`s `(hi, lo)` per coordinate, ~14 decimal digits | ~1e-13 | **next** |
| 3 | CPU high-precision reference orbit + per-pixel `float` perturbation deltas (Pauldelbrot, 2013) | ~1e-30 routinely, effectively unlimited | future |
| 4 | Add BLA (Bivariate Linear Approximation) and Pauldelbrot/Zhuoran glitch detection on top of tier 3 | same floor, 10–100× faster | future |

### Tier 2: double-float (current target)

Represent each coordinate as a pair `(hi, lo)` of `float`s where `lo` carries the rounding error of `hi`. Implement Dekker/Knuth `TwoSum` for add and `TwoProd` (using Metal's built-in `fma`) for multiply. Cost is ~10–20× slower per iteration but still fully GPU-parallel. Drop-in replacement for `float2` complex arithmetic in the existing shader.

CPU-side state (center, scale) moves to `Double`; the renderer splits each `Double` into `(hi, lo)` floats at upload time.

### Tier 3: perturbation theory (future)

Pick one reference pixel, compute its full orbit on the CPU at high precision, upload it as an `MTLBuffer`, then per-pixel iterate the *delta* from the reference using `z_{n+1} = 2·Z_n·z_n + z_n² + c` — `c` and `z` stay in `float` because they're tiny. Powers Kalles Fraktaler and reaches zoom 1e1000+.

## Architecture

- `Shaders.metal` — full-screen triangle vertex shader; fragment shader runs the Mandelbrot iteration with smooth-iteration coloring (Inigo Quilez cosine palette).
- `MandelbrotRenderer.swift` — Metal pipeline + per-frame uniform upload (`MTKViewDelegate`).
- `MandelbrotView.swift` — `MTKView` wrapped for SwiftUI on both platforms via `PlatformRepresentable` typealias. Custom `ZoomableMTKView` subclass on macOS handles cursor-anchored scroll-wheel zoom.
- `ContentView.swift` — gestures, HUD, state.
- `MandelbrotApp.swift` — `@main`.
