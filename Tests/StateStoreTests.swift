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

    // MARK: - load must not rewrite what it loaded

    private func seedPersistedJulia() -> (state: Data, journal: Data, snaps: [Snapshot]) {
        let persisted = ViewState.defaults(for: .julia)
        // Two distinct snapshots: a journal of identical states would be dropped as no-ops.
        var zoomed = ViewState.defaults(for: .mandelbrot)
        zoomed.scale = 0.75
        let journal = [Snapshot(state: ViewState.defaults(for: .mandelbrot), time: 0),
                       Snapshot(state: zoomed, time: 5)]
        let stateData = try! JSONEncoder().encode(persisted)
        let journalData = try! JSONEncoder().encode(journal)
        defaults.set(stateData, forKey: StateStore.stateKey)
        defaults.set(journalData, forKey: StateStore.journalKey)
        return (stateData, journalData, journal)
    }

    func testLoadPreservesPersistedJournalAfterDebounce() {
        let seed = seedPersistedJulia()
        let s = makeStore()
        // Past both debounces (0.2 s state, 0.5 s journal).
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        XCTAssertEqual(defaults.data(forKey: StateStore.journalKey), seed.journal)
        XCTAssertEqual(defaults.data(forKey: StateStore.stateKey), seed.state)
        XCTAssertEqual(s.journal, seed.snaps)
    }

    func testLoadPreservesPersistedJournalAfterImmediateBackground() {
        let seed = seedPersistedJulia()
        let s = makeStore()
        s.enterBackground()   // performs any pending save now
        XCTAssertEqual(defaults.data(forKey: StateStore.journalKey), seed.journal)
        XCTAssertEqual(defaults.data(forKey: StateStore.stateKey), seed.state)
        XCTAssertEqual(s.journal, seed.snaps)
    }

    // MARK: - background

    func testEnterBackgroundFlushesPendingStateAndJournal() {
        let s = makeStore()
        s.state.scale = 1e-6
        s.enterBackground()
        // No run-loop turn: the debounced saves would not have fired yet.
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.state.scale, 1e-6, accuracy: 1e-18)
        XCTAssertEqual(reloaded.journal, s.journal)
    }

    func testEnterBackgroundStopsReplay() {
        var zoomed = ViewState.defaultState
        zoomed.scale = 0.25
        let snaps = [Snapshot(state: ViewState.defaultState, time: 0),
                     Snapshot(state: zoomed, time: 1)]
        defaults.set(try! JSONEncoder().encode(snaps), forKey: StateStore.journalKey)
        let r = makeStore()
        r.replay()
        XCTAssertTrue(r.isReplaying)
        r.enterBackground()
        XCTAssertFalse(r.isReplaying)
    }
}
