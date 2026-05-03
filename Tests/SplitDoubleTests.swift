import XCTest
import simd
@testable import xFractal

final class SplitDoubleTests: XCTestCase {
    func testRoundTripsForRepresentativeValues() {
        let values: [Double] = [
            0, 1, -1, 0.5, -0.75, .pi, .ulpOfOne,
            -0.7500000123456789,
            1.5e-10,
            1.0 + Double.ulpOfOne,
        ]
        for d in values {
            let (hi, lo) = splitDouble(d)
            // The lo half is a single-precision Float, so the recoverable precision
            // is bounded by Float.ulp(residual) / 2 — about 10–100× Double.ulp(d).
            let tolerance = max(abs(d), 1) * 1e-13
            XCTAssertEqual(Double(hi) + Double(lo), d, accuracy: tolerance,
                           "round-trip failed for \(d)")
        }
    }

    func testHiIsTheNearestFloatApproximation() {
        let d = -0.7500000123456789
        let (hi, _) = splitDouble(d)
        XCTAssertEqual(hi, Float(d))
    }

    func testZeroDecomposesToZero() {
        let (hi, lo) = splitDouble(0)
        XCTAssertEqual(hi, 0)
        XCTAssertEqual(lo, 0)
    }

    func testLoIsBoundedByFloatPrecision() {
        // For any d, |lo| ≤ ulp(hi) — the residual fits within one Float ulp.
        for d in [Double.pi, -1.0/3.0, 1.234567890123, -123456789.987654321] {
            let (hi, lo) = splitDouble(d)
            let ulp = Float(hi).ulp
            XCTAssertLessThanOrEqual(abs(lo), ulp, "lo should fit within one ulp of hi for \(d)")
        }
    }
}
