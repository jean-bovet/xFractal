import XCTest
@testable import xFractal

final class JournalCoalesceTests: XCTestCase {
    private func state(_ scale: Double) -> ViewState {
        var s = ViewState.defaultState
        s.scale = scale
        return s
    }

    func testIdenticalStateIsDropped() {
        let s = state(1.0)
        let initial = [Snapshot(state: s, time: 1.0)]
        let next = StateStore.journal(byApplying: s, to: initial, at: 5.0)
        XCTAssertEqual(next, initial, "identical state must not extend the journal")
    }

    func testWithinCoalesceWindowReplacesLast() {
        let s1 = state(1.0)
        let s2 = state(2.0)
        let initial = [Snapshot(state: s1, time: 0)]
        let next = StateStore.journal(byApplying: s2, to: initial, at: 0.04)
        XCTAssertEqual(next.count, 1)
        XCTAssertEqual(next[0].state.scale, 2.0, accuracy: 1e-12)
        XCTAssertEqual(next[0].time, 0.04)
    }

    func testBeyondCoalesceWindowAppends() {
        let initial = [Snapshot(state: state(1), time: 0)]
        let next = StateStore.journal(byApplying: state(2), to: initial, at: 0.06)
        XCTAssertEqual(next.count, 2)
        XCTAssertEqual(next[1].time, 0.06)
    }

    func testAtBoundaryAppends() {
        let initial = [Snapshot(state: state(1), time: 0)]
        let next = StateStore.journal(byApplying: state(2), to: initial, at: 0.05)
        XCTAssertEqual(next.count, 2,
                       "exactly at the boundary should append (window is strict <)")
    }

    func testCapsAtMaxCount() {
        let cap = 3
        var seq: [Snapshot] = [Snapshot(state: state(0), time: 0)]
        for i in 1..<10 {
            seq = StateStore.journal(byApplying: state(Double(i)),
                                     to: seq, at: Double(i),
                                     maxCount: cap)
        }
        XCTAssertEqual(seq.count, cap)
        XCTAssertEqual(seq.last?.state.scale, 9.0)
        XCTAssertEqual(seq.first?.state.scale, 7.0)
    }

    func testEmptyJournalAppends() {
        let next = StateStore.journal(byApplying: state(1.0), to: [], at: 0)
        XCTAssertEqual(next.count, 1)
    }
}
