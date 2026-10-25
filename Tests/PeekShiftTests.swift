import XCTest
import CoreGraphics
@testable import xFractal

final class PeekShiftTests: XCTestCase {
    private func box(_ x: CGFloat, _ w: CGFloat) -> CGRect {
        CGRect(x: x, y: 0, width: w, height: 10)
    }

    private func assertClear(_ capsule: CGRect, shift: CGFloat, of regions: [CGRect],
                             file: StaticString = #filePath, line: UInt = #line) {
        let moved = capsule.offsetBy(dx: shift, dy: 0)
        for r in regions {
            let overlap = moved.intersection(r)
            XCTAssertTrue(overlap.isNull || overlap.width <= 0 || overlap.height <= 0,
                          "shifted capsule overlaps \(r)", file: file, line: line)
        }
    }

    func testNoRegionsNoShift() {
        let capsule = CGRect(x: 365.5, y: 621, width: 220, height: 36)
        XCTAssertEqual(peekShift(capsule: capsule, clearing: [], in: CGSize(width: 951, height: 669)), 0)
    }

    func testRegionNotIntersectingNoShift() {
        let capsule = CGRect(x: 365.5, y: 621, width: 220, height: 36)
        let region = CGRect(x: 700, y: 0, width: 40, height: 669)
        XCTAssertEqual(peekShift(capsule: capsule, clearing: [region], in: CGSize(width: 951, height: 669)), 0)
    }

    func testHingeOnCentreShiftsTrailingByTheMinimum() {
        let capsule = CGRect(x: 365.5, y: 621, width: 220, height: 36)
        let region = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let shift = peekShift(capsule: capsule, clearing: [region], in: CGSize(width: 951, height: 669))
        XCTAssertEqual(shift, 130, accuracy: 0.001)
        assertClear(capsule, shift: shift, of: [region])
    }

    func testTrailingBlockedFallsBackToLeading() {
        let capsule = box(70, 20)
        let region = box(75, 10)
        let shift = peekShift(capsule: capsule, clearing: [region], in: CGSize(width: 100, height: 10))
        XCTAssertEqual(shift, -15, accuracy: 0.001)
        assertClear(capsule, shift: shift, of: [region])
    }

    func testNeitherFitsReturnsZero() {
        let capsule = box(40, 20)
        let region = box(10, 80)
        XCTAssertEqual(peekShift(capsule: capsule, clearing: [region], in: CGSize(width: 100, height: 10)), 0)
    }

    func testCandidateInsideAnotherRegionIsRejected() {
        let capsule = box(40, 20)
        let regions = [box(45, 10), box(70, 25)]
        let shift = peekShift(capsule: capsule, clearing: regions, in: CGSize(width: 100, height: 10))
        XCTAssertEqual(shift, -15, accuracy: 0.001)
        assertClear(capsule, shift: shift, of: regions)
    }

    func testTouchingEdgeIsClear() {
        let capsule = box(40, 20)
        let region = box(60, 20)
        XCTAssertEqual(peekShift(capsule: capsule, clearing: [region], in: CGSize(width: 100, height: 10)), 0)
    }
}
