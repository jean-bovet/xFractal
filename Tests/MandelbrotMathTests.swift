import XCTest
import simd
@testable import xFractal

final class MandelbrotOrbitTests: XCTestCase {
    func testFirstEntryIsZero() {
        let orbit = mandelbrotOrbit(referenceC: SIMD2<Double>(0, 0), maxIterations: 8)
        XCTAssertEqual(orbit.first, SIMD2<Float>(0, 0))
    }

    func testLengthBoundedByMaxIterPlusOne() {
        let orbit = mandelbrotOrbit(referenceC: SIMD2<Double>(-0.75, 0.1), maxIterations: 50)
        XCTAssertLessThanOrEqual(orbit.count, 51)
        XCTAssertGreaterThanOrEqual(orbit.count, 1)
    }

    func testExternalPointEscapesQuickly() {
        let orbit = mandelbrotOrbit(referenceC: SIMD2<Double>(2, 2), maxIterations: 50)
        // c = (2, 2): z₁ = (2, 2), |z|² = 8 → escape immediately.
        XCTAssertEqual(orbit.count, 2)
        XCTAssertEqual(orbit[1], SIMD2<Float>(2, 2))
    }

    func testInteriorPointFillsBuffer() {
        // c = (-0.1, 0): orbit converges, never escapes.
        let orbit = mandelbrotOrbit(referenceC: SIMD2<Double>(-0.1, 0.0), maxIterations: 32)
        XCTAssertEqual(orbit.count, 33)
    }

    func testKnownEarlyOrbitAtMinusThreeQuarters() {
        // c = (-0.75, 0): z₁ = -0.75, z₂ = 0.5625 - 0.75 = -0.1875, ...
        let orbit = mandelbrotOrbit(referenceC: SIMD2<Double>(-0.75, 0), maxIterations: 4)
        XCTAssertEqual(orbit.count, 5)
        XCTAssertEqual(orbit[0], SIMD2<Float>(0, 0))
        XCTAssertEqual(orbit[1].x, -0.75, accuracy: 1e-6)
        XCTAssertEqual(orbit[2].x, -0.1875, accuracy: 1e-6)
        XCTAssertEqual(orbit[3].x, -0.71484375, accuracy: 1e-5)
    }
}

final class PickReferenceTests: XCTestCase {
    func testPicksInsideSetWhenAvailable() {
        let r = pickMandelbrotReference(center: SIMD2<Double>(-0.5, 0), scale: 1.5,
                                        aspect: 1.0, maxIterations: 64)
        XCTAssertEqual(mandelbrotEscapeIter(c: r, maxIterations: 64), 64,
                       "Should pick a probe that does not escape within maxIter")
    }

    func testReturnsAProbeFromTheView() {
        // Way outside the set: every probe escapes at iter 1, so the function
        // returns the first probe encountered. It must lie inside the probed
        // window: (10 ± aspect·scale, 10 ± scale) = (10 ± 0.1, 10 ± 0.1).
        let r = pickMandelbrotReference(center: SIMD2<Double>(10, 10), scale: 0.1,
                                        aspect: 1.0, maxIterations: 32)
        XCTAssertEqual(r.x, 10, accuracy: 0.10001)
        XCTAssertEqual(r.y, 10, accuracy: 0.10001)
    }

    func testAspectExpandsXProbes() {
        // With aspect 2, the x-extent of the probe grid doubles.
        let r = pickMandelbrotReference(center: SIMD2<Double>(100, 0), scale: 1.0,
                                        aspect: 2.0, maxIterations: 1)
        // All probes escape at k=1; first probe is at (-1*2, -1) → (98, -1).
        // Just check x is within the aspect-widened range.
        XCTAssertGreaterThanOrEqual(r.x, 98)
        XCTAssertLessThanOrEqual(r.x, 102)
    }
}
