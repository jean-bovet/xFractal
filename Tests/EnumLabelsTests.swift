import XCTest
@testable import xFractal

final class EnumLabelsTests: XCTestCase {
    func testAllFractalTypesHaveNonEmptyLabel() {
        for t in FractalType.allCases {
            XCTAssertFalse(t.label.isEmpty, "\(t) label is empty")
        }
    }

    func testDeepZoomCapability() {
        XCTAssertTrue(FractalType.mandelbrot.supportsDeepZoom)
        XCTAssertTrue(FractalType.julia.supportsDeepZoom)
        XCTAssertFalse(FractalType.newton.supportsDeepZoom)
        XCTAssertFalse(FractalType.multibrot.supportsDeepZoom)
    }

    func testPerturbationCapability() {
        XCTAssertTrue(FractalType.mandelbrot.supportsPerturbation)
        XCTAssertFalse(FractalType.julia.supportsPerturbation)
        XCTAssertFalse(FractalType.newton.supportsPerturbation)
        XCTAssertFalse(FractalType.multibrot.supportsPerturbation)
    }

    func testAllPalettesHaveNonEmptyLabel() {
        for p in Palette.allCases {
            XCTAssertFalse(p.label.isEmpty, "\(p) label is empty")
        }
    }

    func testViewStateCenterRoundTrip() {
        var s = ViewState.defaultState
        s.center = .init(0.123, -0.456)
        XCTAssertEqual(s.centerX, 0.123, accuracy: 1e-12)
        XCTAssertEqual(s.centerY, -0.456, accuracy: 1e-12)
        XCTAssertEqual(s.center.x, 0.123, accuracy: 1e-12)
        XCTAssertEqual(s.center.y, -0.456, accuracy: 1e-12)
    }
}
