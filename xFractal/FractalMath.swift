import Foundation
import simd

@inline(__always)
func splitDouble(_ d: Double) -> (hi: Float, lo: Float) {
    let hi = Float(d)
    let lo = Float(d - Double(hi))
    return (hi, lo)
}

/// Convert a y-up unit-square coordinate (x, y in [0,1] with y=0 at the bottom)
/// to renderer NDC space (x scaled by aspect, y in [-1, 1]).
///
/// For inputs that arrive y-down (e.g. SwiftUI's `UnitPoint`), callers should
/// flip y at the call site: `unitToNDC(SIMD2(unit.x, 1 - unit.y), aspect: a)`.
@inline(__always)
func unitToNDC(_ unit: SIMD2<Double>, aspect: Double) -> SIMD2<Double> {
    SIMD2<Double>((unit.x * 2.0 - 1.0) * aspect, unit.y * 2.0 - 1.0)
}

@inline(__always)
func worldFromAnchor(center: SIMD2<Double>, scale: Double, anchorNDC: SIMD2<Double>) -> SIMD2<Double> {
    center + anchorNDC * scale
}

/// New center after scaling so the world point under `anchorNDC` stays fixed.
@inline(__always)
func anchoredZoomCenter(center: SIMD2<Double>, scale: Double,
                        anchorNDC: SIMD2<Double>, newScale: Double) -> SIMD2<Double> {
    let world = worldFromAnchor(center: center, scale: scale, anchorNDC: anchorNDC)
    return world - anchorNDC * newScale
}

/// New center after panning the view by (dxPx, dyPx) screen pixels.
/// Screen y is down; world y is up — y delta is inverted.
@inline(__always)
func panCenter(center: SIMD2<Double>, scale: Double, viewHeight: Double,
               dxPx: Double, dyPx: Double) -> SIMD2<Double> {
    let h = max(viewHeight, 1)
    let pxToWorld = (2.0 * scale) / h
    return SIMD2<Double>(center.x - dxPx * pxToWorld,
                         center.y + dyPx * pxToWorld)
}

/// One step of the Mandelbrot iteration: zₙ₊₁ = zₙ² + c.
@inline(__always)
func mandelbrotStep(z: SIMD2<Double>, c: SIMD2<Double>) -> SIMD2<Double> {
    SIMD2<Double>(z.x * z.x - z.y * z.y + c.x,
                  2.0 * z.x * z.y + c.y)
}

/// Iteration count before |z|² exceeds 4, capped at `maxIterations`.
func mandelbrotEscapeIter(c: SIMD2<Double>, maxIterations: Int) -> Int {
    var z = SIMD2<Double>(0, 0)
    for k in 0..<maxIterations {
        if z.x * z.x + z.y * z.y > 4.0 { return k }
        z = mandelbrotStep(z: z, c: c)
    }
    return maxIterations
}

/// Pick a Mandelbrot reference point inside the current view: the probe-grid
/// point with the highest iteration count (or the first probe that doesn't
/// escape within `maxIterations`).
func pickMandelbrotReference(center: SIMD2<Double>, scale: Double, aspect: Double,
                             maxIterations: Int, probes: Int = 5) -> SIMD2<Double> {
    let denom = max(probes - 1, 1)
    var best = center
    var bestIter = -1

    for j in 0..<probes {
        for i in 0..<probes {
            let u = (Double(i) / Double(denom)) * 2.0 - 1.0
            let v = (Double(j) / Double(denom)) * 2.0 - 1.0
            let c = SIMD2<Double>(center.x + u * aspect * scale,
                                  center.y + v * scale)
            let iter = mandelbrotEscapeIter(c: c, maxIterations: maxIterations)
            if iter > bestIter {
                bestIter = iter
                best = c
                if iter == maxIterations { return best }
            }
        }
    }
    return best
}

/// Mandelbrot orbit at reference c. Always starts with (0,0); stops early when
/// |z|² > 4. Length ≤ maxIterations + 1.
func mandelbrotOrbit(referenceC c: SIMD2<Double>, maxIterations: Int) -> [SIMD2<Float>] {
    var orbit: [SIMD2<Float>] = []
    orbit.reserveCapacity(maxIterations + 1)
    orbit.append(SIMD2<Float>(0, 0))

    var z = SIMD2<Double>(0, 0)
    for _ in 0..<maxIterations {
        if z.x * z.x + z.y * z.y > 4.0 { break }
        z = mandelbrotStep(z: z, c: c)
        orbit.append(SIMD2<Float>(Float(z.x), Float(z.y)))
    }
    return orbit
}
