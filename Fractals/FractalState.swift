import Foundation
import simd

struct ViewState: Codable, Equatable {
    var centerX: Double
    var centerY: Double
    var scale: Double
    var maxIterations: UInt32
    var usePerturbation: Bool

    static let defaultState = ViewState(
        centerX: -0.5, centerY: 0.0, scale: 1.5,
        maxIterations: 512, usePerturbation: false
    )

    var center: SIMD2<Double> {
        get { SIMD2<Double>(centerX, centerY) }
        set { centerX = newValue.x; centerY = newValue.y }
    }

    static func interpolate(_ a: ViewState, _ b: ViewState, _ t: Double) -> ViewState {
        let cx = a.centerX * (1 - t) + b.centerX * t
        let cy = a.centerY * (1 - t) + b.centerY * t
        // Zoom is exponential — log-interpolate scale.
        let scale: Double
        if a.scale > 0, b.scale > 0 {
            scale = exp(log(a.scale) * (1 - t) + log(b.scale) * t)
        } else {
            scale = a.scale * (1 - t) + b.scale * t
        }
        let iter = t < 0.5 ? a.maxIterations : b.maxIterations
        let perturb = t < 0.5 ? a.usePerturbation : b.usePerturbation
        return ViewState(centerX: cx, centerY: cy, scale: scale,
                         maxIterations: iter, usePerturbation: perturb)
    }
}

struct Snapshot: Codable {
    var state: ViewState
    var time: TimeInterval
}

final class StateStore: ObservableObject {
    @Published var state: ViewState = .defaultState {
        didSet { onStateChanged(oldValue: oldValue) }
    }
    @Published private(set) var journal: [Snapshot] = []
    @Published private(set) var isReplaying: Bool = false

    private var journalStart: Date = Date()
    private var saveStateWork: DispatchWorkItem?
    private var saveJournalWork: DispatchWorkItem?
    private var replayTimer: Timer?

    private static let stateKey = "fractals.viewState"
    private static let journalKey = "fractals.journal"
    private static let maxJournalCount = 4096
    // Cap replay length so a long exploration session is still watchable.
    private static let maxReplayDuration: TimeInterval = 30

    init() { load() }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.stateKey),
           let decoded = try? JSONDecoder().decode(ViewState.self, from: data) {
            state = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.journalKey),
           let decoded = try? JSONDecoder().decode([Snapshot].self, from: data) {
            journal = decoded
            // Continue timeline across restarts.
            let lastTime = decoded.last?.time ?? 0
            journalStart = Date().addingTimeInterval(-lastTime)
        }
    }

    private func onStateChanged(oldValue: ViewState) {
        guard oldValue != state else { return }
        saveStateDebounced()
        if !isReplaying {
            recordSnapshot()
        }
    }

    private func recordSnapshot() {
        let now = Date().timeIntervalSince(journalStart)
        if let last = journal.last, last.state == state { return }
        // Coalesce rapid updates (drags) into single tail snapshot.
        if let last = journal.last, now - last.time < 0.05 {
            journal[journal.count - 1] = Snapshot(state: state, time: now)
        } else {
            journal.append(Snapshot(state: state, time: now))
            if journal.count > Self.maxJournalCount {
                journal.removeFirst(journal.count - Self.maxJournalCount)
            }
        }
        saveJournalDebounced()
    }

    private func saveStateDebounced() {
        saveStateWork?.cancel()
        let snapshot = state
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Self.stateKey)
            }
        }
        saveStateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func saveJournalDebounced() {
        saveJournalWork?.cancel()
        let snapshot = journal
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Self.journalKey)
            }
        }
        saveJournalWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func reset() {
        stopReplay()
        state = .defaultState
    }

    func clearJournal() {
        stopReplay()
        journal = []
        journalStart = Date()
        UserDefaults.standard.removeObject(forKey: Self.journalKey)
    }

    func replay() {
        guard journal.count >= 2, !isReplaying else { return }
        replayTimer?.invalidate()

        let originalDuration = journal.last!.time - journal.first!.time
        let speed = max(1.0, originalDuration / Self.maxReplayDuration)
        let startWall = Date()
        let baseTime = journal.first!.time

        isReplaying = true
        state = journal.first!.state

        replayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let wallElapsed = Date().timeIntervalSince(startWall)
            let virtualTime = baseTime + wallElapsed * speed
            let last = self.journal.last!

            if virtualTime >= last.time {
                self.state = last.state
                timer.invalidate()
                self.replayTimer = nil
                self.isReplaying = false
                return
            }

            // Binary search for surrounding snapshots.
            var lo = 0
            var hi = self.journal.count - 1
            while lo < hi - 1 {
                let mid = (lo + hi) / 2
                if self.journal[mid].time <= virtualTime { lo = mid } else { hi = mid }
            }
            let a = self.journal[lo]
            let b = self.journal[hi]
            let span = max(b.time - a.time, 1e-9)
            let t = (virtualTime - a.time) / span
            self.state = ViewState.interpolate(a.state, b.state, t)
        }
    }

    func stopReplay() {
        replayTimer?.invalidate()
        replayTimer = nil
        isReplaying = false
    }
}
