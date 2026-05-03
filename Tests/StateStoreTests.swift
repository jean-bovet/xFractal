import XCTest
import simd
@testable import xFractal

final class StateStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> StateStore {
        StateStore(defaults: defaults, now: Date.init)
    }

    // MARK: - switchType preservation rules

    func testSwitchToJuliaPreservesJuliaCAndType() {
        let s = makeStore()
        s.state.juliaCx = 0.314
        s.state.juliaCy = -0.21
        s.switchType(to: .julia)
        XCTAssertEqual(s.state.type, .julia)
        XCTAssertEqual(s.state.juliaCx, 0.314, accuracy: 1e-12)
        XCTAssertEqual(s.state.juliaCy, -0.21, accuracy: 1e-12)
    }

    func testSwitchPreservesPaletteAndSmooth() {
        let s = makeStore()
        s.state.palette = .gray
        s.state.smooth = false
        s.switchType(to: .julia)
        XCTAssertEqual(s.state.palette, .gray)
        XCTAssertFalse(s.state.smooth)
    }

    func testSwitchToMultibrotClampsExponentAtTwo() {
        let s = makeStore()
        s.state.multibrotExponent = 1
        s.switchType(to: .multibrot)
        XCTAssertGreaterThanOrEqual(s.state.multibrotExponent, 2)
    }

    func testSwitchToNewtonPreservesFlavor() {
        let s = makeStore()
        s.state.newtonFlavor = 2
        s.switchType(to: .newton)
        XCTAssertEqual(s.state.newtonFlavor, 2)
    }

    func testSwitchToMandelbrotResetsViewToDefaults() {
        let s = makeStore()
        s.switchType(to: .julia)
        s.state.scale = 1e-6
        s.switchType(to: .mandelbrot)
        let defaults = ViewState.defaults(for: .mandelbrot)
        XCTAssertEqual(s.state.scale, defaults.scale, accuracy: 1e-12)
        XCTAssertEqual(s.state.centerX, defaults.centerX, accuracy: 1e-12)
        XCTAssertEqual(s.state.centerY, defaults.centerY, accuracy: 1e-12)
    }

    func testSwitchToSameTypeIsNoop() {
        let s = makeStore()
        let before = s.state
        s.switchType(to: s.state.type)
        XCTAssertEqual(s.state, before)
    }

    // MARK: - reset

    func testResetMatchesDefaults() {
        let s = makeStore()
        s.state.scale = 1e-6
        s.state.center = SIMD2<Double>(0.123, 0.456)
        s.reset()
        XCTAssertEqual(s.state, ViewState.defaults(for: s.state.type))
    }

    // MARK: - clearJournal

    func testClearJournalEmptiesJournal() {
        let s = makeStore()
        s.state.scale = 1.4
        s.state.scale = 0.7
        XCTAssertGreaterThan(s.journal.count, 0)
        s.clearJournal()
        XCTAssertEqual(s.journal.count, 0)
    }

    // MARK: - persistence via injected UserDefaults

    func testStateLoadsFromInjectedDefaults() {
        let target = ViewState.defaults(for: .julia)
        let data = try! JSONEncoder().encode(target)
        defaults.set(data, forKey: StateStore.stateKey)
        let s = makeStore()
        XCTAssertEqual(s.state, target)
    }

    func testJournalLoadsFromInjectedDefaults() {
        let snaps = [
            Snapshot(state: ViewState.defaults(for: .mandelbrot), time: 0),
            Snapshot(state: ViewState.defaults(for: .julia),      time: 0.1),
        ]
        let data = try! JSONEncoder().encode(snaps)
        defaults.set(data, forKey: StateStore.journalKey)
        let s = makeStore()
        XCTAssertEqual(s.journal, snaps)
    }
}
