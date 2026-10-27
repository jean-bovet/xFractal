import UIKit
@testable import xFractal

/// The fixed clock every gallery store runs on.
let galleryFixedDate = Date(timeIntervalSince1970: 1_800_000_000)

enum GallerySize: Equatable {
    /// The simulator's own screen (the Duo simulator folded: its 466 x 678 pt outer display).
    case phone
    /// The iPhone Duo's inner display in landscape, 951 x 669 pt: a window with the regular horizontal size class.
    case duoInnerLandscape
    /// The iPhone Duo's inner display in portrait, 669 x 951 pt.
    case duoInnerPortrait

    var points: CGSize {
        switch self {
        case .phone: return UIScreen.main.bounds.size
        case .duoInnerLandscape: return CGSize(width: 951, height: 669)
        case .duoInnerPortrait: return CGSize(width: 669, height: 951)
        }
    }

    /// The sizes whose window and presented controller are told the regular horizontal size class.
    var forcesRegularWidth: Bool { self != .phone }

    /// The capture scale: the Duo's inner display is 3x (its store screenshots are edge to edge at 2853 x 2007), 2 otherwise.
    var scale: CGFloat { self == .phone ? 2 : 3 }
}

/// A fractal rendered off screen at a fixed pixel size, with no app UI around it.
struct GalleryArtwork {
    var name: String
    var state: ViewState
    var width: Int
    var height: Int
}

enum GallerySheet: Equatable {
    case none
    /// Presented, untouched: whatever detent SwiftUI opens at.
    case opening
    case medium
    case large
}

enum GalleryRegionKind: String, Codable {
    case peek, fractal, sheet
    /// A translucent sheet (the board shows through): judged by light versus dark, not by a lit background.
    case sheetGlass
}

/// One scenario's seeded state, journal, sheet, scroll and size, defined once. The tests that mount a scenario
/// without rendering it use these directly.
struct GalleryFixture {
    var name: String
    var group: String
    /// nil = nothing seeded (first launch: `ViewState.defaultState`).
    var state: ViewState?
    /// Empty = no journal seeded.
    var journal: [Snapshot] = []
    var size: GallerySize = .phone
    var sheet: GallerySheet = .none
    var scrollToEnd = false
    /// Started with the production `store.replay()` once the store is built.
    var replays = false
    var regions: [GalleryRegionKind]
    /// A stand-in for the fold region the system reports (hinge at x 475.5, 40 pt wide with its margins): the peek
    /// capsule must clear it. nil = no fold.
    var foldRegion: CGRect? = nil
    /// Dark in both appearances by design (a document canvas, full-bleed imagery): `--check` judges the pair instead of
    /// each image (the dark render's mean luminance at least 0.05 below the light one's).
    var documentCanvas = false
    /// Draws nothing by design: `--check` accepts the blank render (otherwise a render whose pixels are all one colour fails).
    var drawsNothing = false
    /// A card this pass cannot render honestly: not rendered, the reason printed and written to the manifest, the page
    /// says "not rendered on this pass" and `--check` accepts the missing pair for that reason only. nil = rendered.
    var skipped: String? = nil

    var slug: String {
        name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// The state the board shows once the scenario is ready: the seeded one, or snapshot A while replaying.
    var expectedState: ViewState {
        if replays, let first = journal.first { return first.state }
        return state ?? .defaultState
    }
}

enum GalleryFixtures {
    // MARK: seeded states

    static let rabbit = (x: -0.123, y: 0.745)

    static var mandelbrotA: ViewState { .defaultState }
    static var mandelbrotB: ViewState {
        var s = ViewState.defaultState
        s.palette = .cold
        s.centerX = -0.75; s.centerY = 0.1; s.scale = 0.35
        return s
    }

    /// The product page header (AppStore/header.json): the whole first-launch Mandelbrot (Chromatic, on its yellow-orange
    /// field) centered and large, about 1150 px of the 1646 px height: the iPhone keeps only the middle of the header.
    static var mandelbrotHeader: ViewState {
        var s = ViewState.defaultState
        s.centerX = -0.76; s.centerY = 0
        s.scale = 1.65
        return s
    }
    /// The search results asset (AppStore/search-results.json): the whole set well to the left (centered near x 950 of
    /// 3840), room for a phone standing on the right.
    static var mandelbrotSearch: ViewState {
        var s = ViewState.defaultState
        s.centerX = 1.326; s.centerY = 0
        s.scale = 2.75
        return s
    }

    static var julia: ViewState {
        var s = ViewState.defaults(for: .julia)
        s.juliaCx = rabbit.x; s.juliaCy = rabbit.y
        return s
    }
    /// The Spiral preset in Chromatic: colour almost everywhere, little black. The search results asset's phone shows it.
    static var juliaSpiralChromatic: ViewState {
        var s = ViewState.defaults(for: .julia)
        s.juliaCx = -0.7; s.juliaCy = 0.27015
        s.palette = .chromatic
        return s
    }
    static var juliaCold: ViewState {
        var s = julia
        s.palette = .cold
        return s
    }
    static var juliaB: ViewState {
        var s = juliaCold
        s.scale = 0.8
        return s
    }

    static var newton: ViewState { .defaults(for: .newton) }
    static var newtonFlavor2: ViewState {
        var s = ViewState.defaults(for: .newton)
        s.newtonFlavor = 2
        return s
    }

    static var multibrotHot: ViewState {
        var s = ViewState.defaults(for: .multibrot)
        s.multibrotExponent = 5
        s.palette = .hot
        return s
    }
    static var multibrot5: ViewState {
        var s = ViewState.defaults(for: .multibrot)
        s.multibrotExponent = 5
        return s
    }

    static var deepZoom: ViewState {
        var s = ViewState.defaultState
        s.centerX = -0.743643887037151; s.centerY = 0.131825904205330
        s.scale = 1e-10
        s.maxIterations = 2048
        s.usePerturbation = true
        s.palette = .gray
        return s
    }
    /// The same deep zoom in color: the App Store screenshots (AppStore/screenshots.json) use it.
    static var deepZoomChromatic: ViewState {
        var s = deepZoom
        s.palette = .chromatic
        return s
    }

    // MARK: artwork

    /// Fractals rendered full-frame at App Store creative-asset size (no UI), into XFRACTAL_ARTWORK_DIR: the backgrounds
    /// of AppStore/creative-assets.json.
    static let artwork: [GalleryArtwork] = [
        GalleryArtwork(name: "mandelbrot-header", state: mandelbrotHeader, width: 3840, height: 1646),
        GalleryArtwork(name: "mandelbrot-search", state: mandelbrotSearch, width: 3840, height: 2560),
    ]

    // MARK: journals

    /// "[s]": one snapshot of the state at time 0 (Replay disabled, Clear Journal enabled).
    static func single(_ state: ViewState) -> [Snapshot] { [Snapshot(state: state, time: 0)] }

    /// "A to B": A at 0 s and B at 30 s (a 30 s replay at speed 1).
    static func pair(_ a: ViewState, _ b: ViewState) -> [Snapshot] {
        [Snapshot(state: a, time: 0), Snapshot(state: b, time: 30)]
    }

    // MARK: the 26 scenarios

    static let all: [GalleryFixture] = [
        GalleryFixture(name: "Board · Mandelbrot · First launch", group: "Board", state: nil,
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Board · Julia", group: "Board", state: juliaCold, journal: single(juliaCold),
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Board · Julia · Spiral · Chromatic", group: "Board", state: juliaSpiralChromatic,
                       journal: single(juliaSpiralChromatic), regions: [.peek, .fractal]),
        GalleryFixture(name: "Board · Newton", group: "Board", state: newton, journal: single(newton),
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Board · Multibrot", group: "Board", state: multibrotHot, journal: single(multibrotHot),
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Board · Mandelbrot · Deep zoom", group: "Board", state: deepZoom, journal: single(deepZoom),
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Board · Mandelbrot · Deep zoom · Chromatic", group: "Board", state: deepZoomChromatic,
                       journal: single(deepZoomChromatic), regions: [.peek, .fractal]),
        GalleryFixture(name: "Board · Replay ready", group: "Board", state: mandelbrotB,
                       journal: pair(mandelbrotA, mandelbrotB), regions: [.peek, .fractal]),
        GalleryFixture(name: "Board · Replaying", group: "Board", state: mandelbrotB,
                       journal: pair(mandelbrotA, mandelbrotB), replays: true, regions: [.peek, .fractal]),
        GalleryFixture(name: "Controls · Mandelbrot · Opening detent", group: "Controls",
                       state: mandelbrotA, journal: single(mandelbrotA), sheet: .opening, regions: [.sheetGlass, .fractal]),
        GalleryFixture(name: "Controls · Mandelbrot · Medium", group: "Controls",
                       state: mandelbrotA, journal: single(mandelbrotA), sheet: .medium, regions: [.sheetGlass, .fractal]),
        GalleryFixture(name: "Controls · Mandelbrot · Large · First launch", group: "Controls",
                       state: nil, sheet: .large, regions: [.sheet]),
        GalleryFixture(name: "Controls · Julia · Large", group: "Controls", state: juliaB,
                       journal: pair(julia, juliaB), sheet: .large, regions: [.sheet]),
        GalleryFixture(name: "Controls · Julia · Large · Bottom", group: "Controls", state: juliaB,
                       journal: pair(julia, juliaB), sheet: .large, scrollToEnd: true, regions: [.sheet]),
        GalleryFixture(name: "Controls · Newton · Large", group: "Controls", state: newtonFlavor2,
                       journal: single(newtonFlavor2), sheet: .large, regions: [.sheet]),
        GalleryFixture(name: "Controls · Multibrot · Large", group: "Controls", state: multibrot5,
                       journal: single(multibrot5), sheet: .large, regions: [.sheet]),
        GalleryFixture(name: "Controls · Replaying", group: "Controls", state: mandelbrotB,
                       journal: pair(mandelbrotA, mandelbrotB), sheet: .large, replays: true, regions: [.sheet]),
        GalleryFixture(name: "Duo inner · Landscape · Board · Mandelbrot · First launch", group: "iPhone Duo · inner display",
                       state: nil, size: .duoInnerLandscape,
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Duo inner · Landscape · Board · Mandelbrot · Deep zoom · Chromatic", group: "iPhone Duo · inner display",
                       state: deepZoomChromatic, size: .duoInnerLandscape,
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Duo inner · Landscape · Board · Newton", group: "iPhone Duo · inner display",
                       state: newton, size: .duoInnerLandscape,
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Duo inner · Landscape · Board · Multibrot", group: "iPhone Duo · inner display",
                       state: multibrotHot, size: .duoInnerLandscape,
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Duo inner · Landscape · Board · Julia", group: "iPhone Duo · inner display",
                       state: juliaCold, size: .duoInnerLandscape,
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Duo inner · Landscape · Controls · Julia", group: "iPhone Duo · inner display",
                       state: juliaB, journal: pair(julia, juliaB), size: .duoInnerLandscape, sheet: .opening,
                       regions: [.sheet, .fractal]),
        GalleryFixture(name: "Duo inner · Portrait · Board · Mandelbrot · Deep zoom", group: "iPhone Duo · inner display",
                       state: deepZoom, size: .duoInnerPortrait,
                       regions: [.peek, .fractal]),
        GalleryFixture(name: "Duo inner · Portrait · Controls · Mandelbrot", group: "iPhone Duo · inner display",
                       state: mandelbrotA, size: .duoInnerPortrait, sheet: .opening,
                       regions: [.sheetGlass, .fractal]),
        GalleryFixture(name: "Duo inner · Landscape · Board · Folded · Mandelbrot", group: "iPhone Duo · inner display",
                       state: mandelbrotA, size: .duoInnerLandscape, regions: [.peek, .fractal],
                       foldRegion: CGRect(x: 455.5, y: 0, width: 40, height: 669)),
    ]

    static func named(_ fragment: String) -> GalleryFixture {
        all.first { $0.name.contains(fragment) || $0.slug.contains(fragment) }!
    }
}
