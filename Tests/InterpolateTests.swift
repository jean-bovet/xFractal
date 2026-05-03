import XCTest
@testable import xFractal

final class InterpolateTests: XCTestCase {
    private func makeA() -> ViewState {
        ViewState(type: .mandelbrot,
                  centerX: 0, centerY: 0, scale: 1.0,
                  maxIterations: 100, usePerturbation: false,
                  palette: .hot, smooth: false,
                  juliaCx: 0.1, juliaCy: 0.2,
                  multibrotExponent: 3, newtonFlavor: 0)
    }

    private func makeB() -> ViewState {
        ViewState(type: .mandelbrot,
                  centerX: 1, centerY: 2, scale: 4.0,
                  maxIterations: 200, usePerturbation: true,
                  palette: .hot, smooth: true,
                  juliaCx: 0.3, juliaCy: 0.4,
                  multibrotExponent: 3, newtonFlavor: 0)
    }

    func testEndpoints() {
        let a = makeA(), b = makeB()
        XCTAssertEqual(ViewState.interpolate(a, b, 0), a)
        XCTAssertEqual(ViewState.interpolate(a, b, 1), b)
    }

    func testCenterIsLinear() {
        let m = ViewState.interpolate(makeA(), makeB(), 0.5)
        XCTAssertEqual(m.centerX, 0.5, accuracy: 1e-12)
        XCTAssertEqual(m.centerY, 1.0, accuracy: 1e-12)
    }

    func testScaleIsLogInterpolated() {
        let m = ViewState.interpolate(makeA(), makeB(), 0.5)
        // Log-mean of 1 and 4 is 2.
        XCTAssertEqual(m.scale, 2.0, accuracy: 1e-12)
    }

    func testJuliaCIsLinear() {
        let m = ViewState.interpolate(makeA(), makeB(), 0.5)
        XCTAssertEqual(m.juliaCx, 0.2, accuracy: 1e-12)
        XCTAssertEqual(m.juliaCy, 0.3, accuracy: 1e-12)
    }

    func testIterPerturbAndSmoothSnapAtMidpoint() {
        let a = makeA(), b = makeB()
        let lo = ViewState.interpolate(a, b, 0.49)
        XCTAssertEqual(lo.maxIterations, a.maxIterations)
        XCTAssertFalse(lo.usePerturbation)
        XCTAssertFalse(lo.smooth)

        let hi = ViewState.interpolate(a, b, 0.5)
        XCTAssertEqual(hi.maxIterations, b.maxIterations)
        XCTAssertTrue(hi.usePerturbation)
        XCTAssertTrue(hi.smooth)
    }

    func testCrossTypeSnaps() {
        var b = makeB(); b.type = .julia
        XCTAssertEqual(ViewState.interpolate(makeA(), b, 0.4), makeA())
        XCTAssertEqual(ViewState.interpolate(makeA(), b, 0.6), b)
    }

    func testCrossPaletteSnaps() {
        var b = makeB(); b.palette = .gray
        XCTAssertEqual(ViewState.interpolate(makeA(), b, 0.49), makeA())
    }

    func testCrossMultibrotExponentSnaps() {
        var b = makeB(); b.multibrotExponent = 5
        XCTAssertEqual(ViewState.interpolate(makeA(), b, 0.6), b)
    }

    func testCrossNewtonFlavorSnaps() {
        var b = makeB(); b.newtonFlavor = 2
        XCTAssertEqual(ViewState.interpolate(makeA(), b, 0.1), makeA())
        XCTAssertEqual(ViewState.interpolate(makeA(), b, 0.9), b)
    }

    func testZeroScaleFallsBackToLinear() {
        var p = makeA(); p.scale = 0
        var q = makeB(); q.scale = 1
        let m = ViewState.interpolate(p, q, 0.5)
        // With one endpoint at zero, the implementation falls back to a linear blend.
        XCTAssertEqual(m.scale, 0.5, accuracy: 1e-12)
    }

    func testNegativeScaleFallsBackToLinear() {
        var p = makeA(); p.scale = -1
        var q = makeB(); q.scale = 1
        let m = ViewState.interpolate(p, q, 0.5)
        XCTAssertEqual(m.scale, 0, accuracy: 1e-12)
    }
}
