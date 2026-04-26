import Foundation
import simd

enum FractalType: Int, Codable, CaseIterable, Identifiable {
    case mandelbrot = 0
    case julia      = 1
    case newton     = 2
    case multibrot  = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .mandelbrot: return "Mandelbrot"
        case .julia:      return "Julia"
        case .newton:     return "Newton"
        case .multibrot:  return "Multibrot"
        }
    }

    var supportsDeepZoom: Bool {
        self == .mandelbrot || self == .julia
    }

    var supportsPerturbation: Bool { self == .mandelbrot }
}

enum Palette: Int, Codable, CaseIterable, Identifiable {
    case hot       = 0
    case cold      = 1
    case gray      = 2
    case chromatic = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .hot:       return "Hot"
        case .cold:      return "Cold"
        case .gray:      return "Gray"
        case .chromatic: return "Chromatic"
        }
    }
}

struct ViewState: Codable, Equatable {
    var type: FractalType
    var centerX: Double
    var centerY: Double
    var scale: Double
    var maxIterations: UInt32
    var usePerturbation: Bool
    var palette: Palette
    var smooth: Bool
    var juliaCx: Double
    var juliaCy: Double
    var multibrotExponent: UInt32
    var newtonFlavor: UInt32

    var center: SIMD2<Double> {
        get { SIMD2<Double>(centerX, centerY) }
        set { centerX = newValue.x; centerY = newValue.y }
    }

    static let defaultState = defaults(for: .mandelbrot)

    static func defaults(for type: FractalType) -> ViewState {
        switch type {
        case .mandelbrot:
            return ViewState(type: .mandelbrot,
                             centerX: -0.5, centerY: 0.0, scale: 1.5,
                             maxIterations: 512, usePerturbation: false,
                             palette: .chromatic, smooth: true,
                             juliaCx: -0.7, juliaCy: 0.27015,
                             multibrotExponent: 3, newtonFlavor: 0)
        case .julia:
            return ViewState(type: .julia,
                             centerX: 0.0, centerY: 0.0, scale: 1.6,
                             maxIterations: 512, usePerturbation: false,
                             palette: .chromatic, smooth: true,
                             juliaCx: -0.7, juliaCy: 0.27015,
                             multibrotExponent: 3, newtonFlavor: 0)
        case .newton:
            return ViewState(type: .newton,
                             centerX: 0.0, centerY: 0.0, scale: 1.5,
                             maxIterations: 64, usePerturbation: false,
                             palette: .chromatic, smooth: false,
                             juliaCx: -0.7, juliaCy: 0.27015,
                             multibrotExponent: 3, newtonFlavor: 0)
        case .multibrot:
            return ViewState(type: .multibrot,
                             centerX: 0.0, centerY: 0.0, scale: 1.6,
                             maxIterations: 256, usePerturbation: false,
                             palette: .chromatic, smooth: true,
                             juliaCx: -0.7, juliaCy: 0.27015,
                             multibrotExponent: 3, newtonFlavor: 0)
        }
    }

    static func interpolate(_ a: ViewState, _ b: ViewState, _ t: Double) -> ViewState {
        // Cross-type or cross-palette segments don't blend smoothly — snap.
        guard a.type == b.type, a.palette == b.palette,
              a.multibrotExponent == b.multibrotExponent,
              a.newtonFlavor == b.newtonFlavor else {
            return t < 0.5 ? a : b
        }

        let cx = a.centerX * (1 - t) + b.centerX * t
        let cy = a.centerY * (1 - t) + b.centerY * t
        let scale: Double
        if a.scale > 0, b.scale > 0 {
            scale = exp(log(a.scale) * (1 - t) + log(b.scale) * t)
        } else {
            scale = a.scale * (1 - t) + b.scale * t
        }
        let jx = a.juliaCx * (1 - t) + b.juliaCx * t
        let jy = a.juliaCy * (1 - t) + b.juliaCy * t
        let iter = t < 0.5 ? a.maxIterations : b.maxIterations
        let perturb = t < 0.5 ? a.usePerturbation : b.usePerturbation
        let smooth = t < 0.5 ? a.smooth : b.smooth

        return ViewState(type: a.type,
                         centerX: cx, centerY: cy, scale: scale,
                         maxIterations: iter, usePerturbation: perturb,
                         palette: a.palette, smooth: smooth,
                         juliaCx: jx, juliaCy: jy,
                         multibrotExponent: a.multibrotExponent,
                         newtonFlavor: a.newtonFlavor)
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

    // Bumped when ViewState fields changed; previous persisted blobs are ignored.
    private static let stateKey = "fractals.viewState.v2"
    private static let journalKey = "fractals.journal.v2"
    private static let maxJournalCount = 4096
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
        state = ViewState.defaults(for: state.type)
    }

    func switchType(to type: FractalType) {
        guard state.type != type else { return }
        stopReplay()
        var next = ViewState.defaults(for: type)
        // Preserve cosmetic preferences across switches.
        next.palette = state.palette
        next.smooth = state.smooth
        if type == .julia {
            next.juliaCx = state.juliaCx
            next.juliaCy = state.juliaCy
        }
        if type == .multibrot {
            next.multibrotExponent = max(2, state.multibrotExponent)
        }
        if type == .newton {
            next.newtonFlavor = state.newtonFlavor
        }
        state = next
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
