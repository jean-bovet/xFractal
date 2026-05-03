import XCTest
import simd
@testable import xFractal

final class UnitToNDCTests: XCTestCase {
    func testCenterOfUnitMapsToOrigin() {
        let r = unitToNDC(SIMD2<Double>(0.5, 0.5), aspect: 1.0)
        XCTAssertEqual(r.x, 0, accuracy: 1e-12)
        XCTAssertEqual(r.y, 0, accuracy: 1e-12)
    }

    func testCornersMapToCorners() {
        XCTAssertEqual(unitToNDC(SIMD2<Double>(0, 0), aspect: 1.0), SIMD2<Double>(-1, -1))
        XCTAssertEqual(unitToNDC(SIMD2<Double>(1, 1), aspect: 1.0), SIMD2<Double>( 1,  1))
    }

    func testAspectScalesXOnly() {
        let r = unitToNDC(SIMD2<Double>(1.0, 0.5), aspect: 2.0)
        XCTAssertEqual(r.x, 2.0, accuracy: 1e-12)
        XCTAssertEqual(r.y, 0,   accuracy: 1e-12)
    }
}

final class AnchoredZoomTests: XCTestCase {
    func testAnchorAtSceneCenterLeavesCenterAlone() {
        let center = SIMD2<Double>(-0.5, 0)
        let newCenter = anchoredZoomCenter(center: center, scale: 1.5,
                                           anchorNDC: SIMD2<Double>(0, 0),
                                           newScale: 0.75)
        XCTAssertEqual(newCenter, center)
    }

    func testWorldUnderAnchorIsInvariant() {
        // For any (center, scale, ndc, newScale), the world point under the
        // anchor should match before and after the zoom.
        let combos: [(SIMD2<Double>, Double, SIMD2<Double>, Double)] = [
            (SIMD2<Double>(0, 0),     1.0,  SIMD2<Double>( 1,  1),  0.5),
            (SIMD2<Double>(-0.5, 0),  1.5,  SIMD2<Double>(-1,  0),  0.1),
            (SIMD2<Double>(2, -3),    0.01, SIMD2<Double>(0.3, 0.7), 0.0001),
            (SIMD2<Double>(-0.75, 0), 1.0,  SIMD2<Double>(0, 0),    1e-9),
        ]
        for (center, scale, ndc, newScale) in combos {
            let before = worldFromAnchor(center: center, scale: scale, anchorNDC: ndc)
            let newCenter = anchoredZoomCenter(center: center, scale: scale,
                                               anchorNDC: ndc, newScale: newScale)
            let after = worldFromAnchor(center: newCenter, scale: newScale, anchorNDC: ndc)
            XCTAssertEqual(after.x, before.x, accuracy: max(abs(before.x), 1) * 1e-12,
                           "x drifted for combo \(center), \(scale) → \(newScale)")
            XCTAssertEqual(after.y, before.y, accuracy: max(abs(before.y), 1) * 1e-12,
                           "y drifted for combo \(center), \(scale) → \(newScale)")
        }
    }

    func testZoomingInTowardCornerMovesCenterTowardCorner() {
        let center = SIMD2<Double>(0, 0)
        let scale  = 1.0
        let ndc    = SIMD2<Double>(1, 1)
        let newScale = 0.5
        let newCenter = anchoredZoomCenter(center: center, scale: scale,
                                           anchorNDC: ndc, newScale: newScale)
        // Anchor is top-right (world (1,1)). Halving scale must shift center toward (1,1).
        XCTAssertEqual(newCenter.x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(newCenter.y, 0.5, accuracy: 1e-12)
    }
}
