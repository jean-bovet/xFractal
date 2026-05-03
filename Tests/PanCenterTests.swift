import XCTest
import simd
@testable import xFractal

final class PanCenterTests: XCTestCase {
    func testHorizontalDragMovesCenterOpposite() {
        let r = panCenter(center: SIMD2<Double>(0, 0), scale: 1.0,
                          viewHeight: 100, dxPx: 50, dyPx: 0)
        // pxToWorld = 2/100 = 0.02; world dx = 1.0; center.x decreases by 1.0.
        XCTAssertEqual(r.x, -1.0, accuracy: 1e-12)
        XCTAssertEqual(r.y, 0,    accuracy: 1e-12)
    }

    func testVerticalDragInvertsY() {
        let r = panCenter(center: SIMD2<Double>(0, 0), scale: 1.0,
                          viewHeight: 100, dxPx: 0, dyPx: 50)
        // Screen y is down; world y is up. Drag down → world center.y increases.
        XCTAssertEqual(r.y, 1.0, accuracy: 1e-12)
    }

    func testHalvingScaleHalvesWorldDelta() {
        let near = panCenter(center: SIMD2<Double>(0, 0), scale: 1.0,
                             viewHeight: 100, dxPx: 100, dyPx: 0)
        let far  = panCenter(center: SIMD2<Double>(0, 0), scale: 0.5,
                             viewHeight: 100, dxPx: 100, dyPx: 0)
        XCTAssertEqual(near.x, -2.0, accuracy: 1e-12)
        XCTAssertEqual(far.x,  -1.0, accuracy: 1e-12)
    }

    func testZeroDeltaIsIdentity() {
        let center = SIMD2<Double>(0.123, -0.456)
        let r = panCenter(center: center, scale: 1.7, viewHeight: 800, dxPx: 0, dyPx: 0)
        XCTAssertEqual(r.x, center.x, accuracy: 1e-12)
        XCTAssertEqual(r.y, center.y, accuracy: 1e-12)
    }

    func testZeroOrNegativeHeightStaysFinite() {
        let r = panCenter(center: SIMD2<Double>(1, 1), scale: 1.0,
                          viewHeight: 0, dxPx: 5, dyPx: 5)
        XCTAssertTrue(r.x.isFinite && r.y.isFinite)
    }
}
