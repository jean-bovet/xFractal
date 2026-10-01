import XCTest
@testable import xFractal

final class SmoothCountTests: XCTestCase {
    /// Iterate zₙ₊₁ = zₙ^n + c from z₀ = 0 like the shader; returns (iter, |z|²) at escape.
    private func escape(c: SIMD2<Double>, exponent n: Int, maxIterations: Int = 256) -> (Int, Double)? {
        var z = SIMD2<Double>(0, 0)
        for i in 0..<maxIterations {
            var p = SIMD2<Double>(1, 0)
            for _ in 0..<n { p = SIMD2(p.x * z.x - p.y * z.y, p.x * z.y + p.y * z.x) }
            z = p + c
            let m = z.x * z.x + z.y * z.y
            if m > 4.0 { return (i, m) }
        }
        return nil
    }

    func testQuadraticMatchesClassicFormula() {
        // nu = iter + 1 - log2(log2|z|), the standard z² smoothing.
        let zMag2 = 9.0
        let expected = 7.0 + 1.0 - log2(0.5 * log2(zMag2))
        XCTAssertEqual(smoothEscapeCount(iter: 7, zMag2: zMag2, exponent: 2), expected, accuracy: 1e-12)
    }

    func testMultibrotOvershootIsNotNegative() {
        // c = 1.8, z⁵ + c: z₁ = 1.8 stays in, z₂ ≈ 20.7 overshoots far past the bailout.
        // A negative count is painted as "inside the set" (black band around the set).
        guard let (iter, zMag2) = escape(c: SIMD2(1.8, 0), exponent: 5) else { return XCTFail("should escape") }
        XCTAssertEqual(iter, 1)
        XCTAssertGreaterThanOrEqual(smoothEscapeCount(iter: iter, zMag2: zMag2, exponent: 5), 0)
    }

    func testEscapingPointsNeverCountAsInside() {
        for n in 2...8 {
            for x in stride(from: -6.0, through: 6.0, by: 0.05) {
                for y in stride(from: 0.0, through: 6.0, by: 0.25) {
                    guard let (iter, zMag2) = escape(c: SIMD2(x, y), exponent: n) else { continue }
                    let count = smoothEscapeCount(iter: iter, zMag2: zMag2, exponent: n)
                    XCTAssertGreaterThanOrEqual(count, 0, "n=\(n) c=(\(x), \(y))")
                    if count < 0 { return }
                }
            }
        }
    }

    func testCountIsContinuousAcrossIterationBoundaryForMultibrot() {
        // Smoothing should hide the integer bands: neighbouring points on either side of
        // an iteration boundary get nearly equal counts.
        let n = 5
        var previous: Double?
        var maxJump = 0.0
        for x in stride(from: 1.0, through: 1.6, by: 0.0005) {
            guard let (iter, zMag2) = escape(c: SIMD2(x, 0.3), exponent: n) else { previous = nil; continue }
            let count = smoothEscapeCount(iter: iter, zMag2: zMag2, exponent: n)
            if let p = previous { maxJump = max(maxJump, abs(count - p)) }
            previous = count
        }
        XCTAssertLessThan(maxJump, 0.2)
    }
}
