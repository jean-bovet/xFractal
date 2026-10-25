import SwiftUI
import UIKit
import MetalKit
import ImageIO
import UniformTypeIdentifiers
@testable import xFractal

struct GalleryFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct GalleryRegion: Codable, Equatable {
    var kind: GalleryRegionKind
    var x: Double, y: Double, w: Double, h: Double

    init(_ kind: GalleryRegionKind, _ rect: CGRect) {
        self.kind = kind
        x = rect.minX; y = rect.minY; w = rect.width; h = rect.height
    }
}

/// What one frame submitted by the explicit draw proved.
struct FrameEvidence {
    var submits = 0
    var state: ViewState?
    var completedStatus: MTLCommandBufferStatus?
    var completedError: Error?
    /// When the buffer, which presents the drawable, was scheduled. The iOS SDK has no per-drawable presented handler.
    var scheduledTime: CFTimeInterval = 0
}

private final class FrameRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var evidence = FrameEvidence()
    private var completed = false
    private var presented = false

    func submitted(_ state: ViewState) { lock.lock(); evidence.submits += 1; evidence.state = state; lock.unlock() }
    func complete(_ status: MTLCommandBufferStatus, _ error: Error?) {
        lock.lock(); evidence.completedStatus = status; evidence.completedError = error; completed = true; lock.unlock()
    }
    func schedule(_ time: CFTimeInterval) { lock.lock(); evidence.scheduledTime = time; presented = true; lock.unlock() }
    var snapshot: (FrameEvidence, completed: Bool, presented: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (evidence, completed, presented)
    }
}

/// What a SwiftUI probe saw of the horizontal size class.
final class SizeClassBox {
    var outer: UserInterfaceSizeClass?
    var sheet: UserInterfaceSizeClass?
}

struct SizeClassProbe: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let record: (UserInterfaceSizeClass?) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { record(sizeClass) }
            .onChange(of: sizeClass) { _, new in record(new) }
    }
}

struct ContentCheck {
    var value: Double
    /// "corr" (Pearson correlation) or "mad" (mean absolute difference, for a flat reference).
    var mode: String
    /// The fitted scrim (a presented sheet's dimming, a black overlay: captured = (1 - scrim) x reference) and the
    /// mean absolute RGB error left after applying it.
    var scrim: Double
    var rgbError: Double
    var passed: Bool
    var reason: String?
}

struct RenderResult {
    var png: Data
    var regions: [GalleryRegion]
    var readyMs: Int
    var totalMs: Int
    var submits: Int
    var redraws: Int
    var check: ContentCheck?
    var detent: String?
    var sheetHeight: Double?
    /// The window's leading and trailing safe-area insets: the peek capsule is centred between them.
    var safeLeft: Double
    var safeRight: Double
}

/// How the controls are presented: a sheet in a compact horizontal size class, a trailing column in a regular one
/// (`.inspector` adapts by itself).
enum PresentationForm: String, Equatable {
    case sheet, column
}

/// The fold regions a mounted scenario is told about, changeable after the mount (the app itself gets them from the system).
final class FoldRegionsBox: ObservableObject {
    @Published var regions: [CGRect]?
    init(_ regions: [CGRect]?) { self.regions = regions }
}

/// Hosts `ContentView` so that a change of `FoldRegionsBox.regions` rebuilds the view from the same wrapper: the structural
/// identity holds, so the store, the sheet state and the peek state persist while the fold regions change.
struct FoldHost: View {
    @ObservedObject var box: FoldRegionsBox
    let make: (_ foldRegions: [CGRect]?) -> ContentView
    var body: some View { make(box.regions) }
}

/// One scenario mounted in a window on the app's scene.
@MainActor
final class GalleryMount {
    let scenario: GalleryScenario
    let appearance: GalleryAppearance
    let built: BuiltScenario
    let window: UIWindow
    let host: UIHostingController<AnyView>
    let sizeClasses = SizeClassBox()
    let foldBox: FoldRegionsBox
    var replayStartedAt: Date?

    var mtk: MTKView!
    var renderer: FractalRenderer!

    init(scenario: GalleryScenario, appearance: GalleryAppearance, activeScenePhase: Bool = true) {
        self.scenario = scenario
        self.appearance = appearance
        built = scenario.build(appearance)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: scenario.fixture.size.points)
        window.overrideUserInterfaceStyle = appearance.style
        let probe = AnyView(SizeClassProbe { [sizeClasses] in sizeClasses.sheet = $0 })
        foldBox = FoldRegionsBox(scenario.fixture.foldRegion.map { [$0] })
        let content = FoldHost(box: foldBox) { [built] regions in built.makeView(probe, regions) }
        let root: AnyView
        if activeScenePhase {
            // The real app's foreground state: a test window's scene phase is .background, which pauses the MTKView.
            root = AnyView(content.environment(\.scenePhase, .active)
                .background(SizeClassProbe { [sizeClasses] in sizeClasses.outer = $0 }))
        } else {
            root = AnyView(content.background(SizeClassProbe { [sizeClasses] in sizeClasses.outer = $0 }))
        }
        host = UIHostingController(rootView: root)
        if scenario.fixture.size.forcesRegularWidth {
            host.traitOverrides.horizontalSizeClass = .regular
            // The presented sheet takes its traits from the window, not from the presenting controller.
            window.traitOverrides.horizontalSizeClass = .regular
        }
    }

    var store: StateStore { built.store }
    var fixture: GalleryFixture { scenario.fixture }
    /// The controller presenting nothing above it that is a sheet: found from the host down through its children (the
    /// inspector wrapper hosts the content in a child controller, which then presents the sheet).
    var presented: UIViewController? {
        func find(_ vc: UIViewController) -> UIViewController? {
            if let p = vc.presentedViewController { return p }
            for child in vc.children { if let p = find(child) { return p } }
            return nil
        }
        return find(host)
    }
    var sheetController: UISheetPresentationController? { presented?.sheetPresentationController }

    /// Read from the host's current traits every time, never cached: a trait override changed after the mount is seen on
    /// the next read.
    var form: PresentationForm { host.traitCollection.horizontalSizeClass == .regular ? .column : .sheet }

    /// The controls list (the Form's collection view) when it is part of the window's own hierarchy: a column.
    var columnList: UICollectionView? {
        func find(_ v: UIView) -> UICollectionView? {
            if let c = v as? UICollectionView { return c }
            if v is MTKView { return nil }
            for sub in v.subviews { if let c = find(sub) { return c } }
            return nil
        }
        return find(window)
    }

    /// A narrow window (the Duo's portrait inner display) gets the column laid over the board, with the system's dimming,
    /// instead of beside it: the board then reaches under the column, whatever device inset the trailing edge has.
    var columnOverlaysBoard: Bool {
        guard form == .column, let column = columnFrame, let mtk else { return false }
        return mtk.convert(mtk.bounds, to: window).maxX > column.minX + 1
    }

    /// The column's strip of the window (from the controls list's leading edge to the trailing edge), in window
    /// coordinates; nil while there is no column. Beside a wide window the board is narrower by this width; in a narrow
    /// one the system lays the column over the board instead.
    var columnFrame: CGRect? {
        guard form == .column, let list = columnList else { return nil }
        let frame = list.convert(list.bounds, to: window)
        guard frame.width > 0 else { return nil }
        return CGRect(x: frame.minX, y: 0, width: window.bounds.width - frame.minX, height: window.bounds.height)
    }

    func show() {
        if fixture.replays {
            store.replay()   // the production call
            replayStartedAt = GalleryHarness.clock()
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    func teardown() {
        renderer?.frameObserver = nil
        store.enterBackground()
        built.defaults.removePersistentDomain(forName: built.suiteName)
        window.isHidden = true
        window.rootViewController = nil
    }

    // MARK: waiting

    func waitUntil(_ timeout: TimeInterval, _ what: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw GalleryFailure("timeout (\(timeout) s): \(what)") }
            try await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    static func findMTK(_ view: UIView) -> MTKView? {
        if let m = view as? MTKView { return m }
        for sub in view.subviews { if let m = findMTK(sub) { return m } }
        return nil
    }

    /// The sheet's frame, or the column's in `.column`.
    var sheetFrame: CGRect? {
        if form == .column { return columnFrame }
        guard let v = presented?.view else { return nil }
        return v.convert(v.bounds, to: window)
    }

    /// Readiness step 1: layout settled (bounded wait), with the detent applied for a medium or large sheet.
    func settleLayout() async throws {
        try await waitUntil(5, "the MTKView laid out") {
            guard let m = Self.findMTK(window), m.bounds.width > 0, m.bounds.height > 0 else { return false }
            mtk = m
            let scale = m.contentScaleFactor
            return abs(m.drawableSize.width - m.bounds.width * scale) < 0.5
                && abs(m.drawableSize.height - m.bounds.height * scale) < 0.5
        }
        renderer = mtk.delegate as? FractalRenderer
        guard renderer != nil else { throw GalleryFailure("the MTKView has no FractalRenderer delegate") }
        try await settlePresentation()
    }

    /// The presentation part of `settleLayout()`, also called by a test after it changes the size class: a sheet is waited
    /// for (with the detent applied for a medium or large one), a column is waited for beside a narrower board and with no
    /// presented controller; then the frame is stable.
    func settlePresentation() async throws {
        guard fixture.sheet != .none else { return }
        switch form {
        case .sheet:
            try await waitUntil(5, "the sheet presented") {
                guard let p = presented else { return false }
                return !p.isBeingPresented && p.transitionCoordinator == nil && sheetController != nil
            }
            if fixture.size.forcesRegularWidth, let presented {
                presented.traitOverrides.horizontalSizeClass = .regular
            }
            if fixture.sheet == .medium || fixture.sheet == .large {
                let controller = sheetController!
                let ids = controller.detents.map(\.identifier)
                guard ids.count == 3, ids.contains(.medium), ids.contains(.large) else {
                    throw GalleryFailure("unexpected sheet detents: \(ids.map(\.rawValue))")
                }
                let wanted: UISheetPresentationController.Detent.Identifier = fixture.sheet == .medium ? .medium : .large
                if controller.selectedDetentIdentifier != wanted {
                    controller.animateChanges { controller.selectedDetentIdentifier = wanted }
                    try await waitUntil(5, "detent \(wanted.rawValue) selected") { controller.selectedDetentIdentifier == wanted }
                }
            }
        case .column:
            try await waitUntil(5, "the controls column beside the board (no sheet)") {
                window.layoutIfNeeded()
                guard presented == nil, columnFrame != nil, let list = columnList else { return false }
                // Not while the column is still sliding in from beyond the trailing edge.
                return list.convert(list.bounds, to: window).maxX <= window.bounds.width + 1
            }
            if let presented { throw GalleryFailure("a sheet is presented where a column is due: \(presented)") }
        }
        try await waitStableSheetFrame()
    }

    /// Stable: the sheet (or column) frame and the board's frame unchanged over three successive polls. The board is
    /// part of it because it follows a column with an animation of its own (the padding that stops it at the column),
    /// which outlasts the column's slide.
    func waitStableSheetFrame() async throws {
        var last: CGRect?
        var lastBoard: CGRect?
        var same = 0
        try await waitUntil(10, "the sheet frame stable") {
            window.layoutIfNeeded()
            let frame = sheetFrame
            let board = mtk.convert(mtk.bounds, to: window)
            if let frame, frame == last, board == lastBoard { same += 1 } else { same = 0 }
            last = frame
            lastBoard = board
            return same >= 3 && presented?.transitionCoordinator == nil && (frame != nil || fixture.sheet == .none)
        }
    }

    /// The sheet's dimming fades in after its frame has settled, and the animation's end is not observable from here: wait
    /// (bounded) until `ScrimSettling` finds the fitted scrim of the board region flat over its last samples. Only where a
    /// board region and a scrim exist (the medium detent).
    func settleScrim() async throws {
        guard (fixture.sheet == .medium && form == .sheet) || columnOverlaysBoard, let region = fractalRegion() else { return }
        _ = try await drawFrame()
        var samples: [Double] = []
        let deadline = Date().addingTimeInterval(4)
        while !ScrimSettling.isSettled(samples) {
            if Date() > deadline { throw GalleryFailure("timeout (4 s): the sheet's dimming did not settle (samples \(samples.suffix(4)))") }
            try await Task.sleep(nanoseconds: 100_000_000)
            samples.append(try validate(capture(), expected: fixture.expectedState, region: region, scrimBand: -1...1).scrim)
        }
    }

    /// A capture-sized (window-sized, at the capture scale) image of the reference render multiplied by `gain` (a pure
    /// gain: no offset), for the tests. The reference is drawn at the MTKView's frame in the window and the rest is
    /// black, so `validate` samples the same geometry from it as from a capture, beside a column too.
    func gainedReference(of state: ViewState, gain: Double) throws -> UIImage {
        let reference = try referenceImage(of: state)
        let rw = reference.width, rh = reference.height
        var refBytes = [UInt8](repeating: 0, count: rw * rh * 4)
        let rctx = CGContext(data: &refBytes, width: rw, height: rh, bitsPerComponent: 8, bytesPerRow: rw * 4,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        rctx.draw(reference, in: CGRect(x: 0, y: 0, width: rw, height: rh))
        for i in stride(from: 0, to: refBytes.count, by: 4) {
            for c in 0..<3 { refBytes[i + c] = UInt8(max(0, min(255, (Double(refBytes[i + c]) * gain).rounded()))) }
        }
        guard let gained = rctx.makeImage() else { throw GalleryFailure("gained reference: no image") }
        let scale = fixture.size.scale
        let w = Int((window.bounds.width * scale).rounded()), h = Int((window.bounds.height * scale).rounded())
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let board = mtk.convert(mtk.bounds, to: window)
        // CGContext is y-up; the window's frame is y-down.
        ctx.draw(gained, in: CGRect(x: board.minX * scale, y: CGFloat(h) - board.maxY * scale,
                                    width: board.width * scale, height: board.height * scale))
        guard let image = ctx.makeImage() else { throw GalleryFailure("gained reference: no image") }
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }

    /// Draws a frame and takes `sample` until two successive samples are equal (an animation has ended), bounded at 3 s.
    func settled<T: Equatable>(_ what: String, _ sample: () throws -> T) async throws -> T {
        var last: T?
        let deadline = Date().addingTimeInterval(3)
        while true {
            _ = try await drawFrame()
            let now = try sample()
            if let last, last == now { return now }
            last = now
            if Date() > deadline { throw GalleryFailure("timeout (3 s): \(what) did not settle") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// The peek capsule moves with an animation when the fold regions change: wait until two successive captures of the
    /// window are identical. Only where a fold region is seeded.
    func settlePeek() async throws {
        guard fixture.foldRegion != nil else { return }
        _ = try await settled("the peek capsule") { capture().pngData() }
    }

    // MARK: scroll

    @discardableResult
    func scrollSheetToEnd() async throws -> UIScrollView {
        guard let root = form == .column ? columnList : presented?.view else { throw GalleryFailure("no sheet to scroll") }
        var scrolls: [UIScrollView] = []
        func collect(_ v: UIView) {
            if let s = v as? UIScrollView { scrolls.append(s) }
            v.subviews.forEach(collect)
        }
        collect(root)
        func extent(_ s: UIScrollView) -> CGFloat {
            s.contentSize.height + s.adjustedContentInset.top + s.adjustedContentInset.bottom - s.bounds.height
        }
        let vertical = scrolls.filter { $0.contentSize.width <= $0.bounds.width + 0.5 }
        if let form = vertical.filter({ extent($0) > 0 }).max(by: { extent($0) < extent($1) }) {
            let target = form.contentSize.height + form.adjustedContentInset.bottom - form.bounds.height
            form.setContentOffset(CGPoint(x: form.contentOffset.x, y: target), animated: false)
            try await waitStableSheetFrame()
            try await waitUntil(2, "scroll offset held") { abs(form.contentOffset.y - target) <= 1 }
            return try checkedEnd(of: form)
        }
        // The whole form fits (the iPad's large sheet): nothing to scroll, its end is already in view.
        guard let form = vertical.first(where: { $0 is UICollectionView }) else {
            throw GalleryFailure("no vertical scroll view in the sheet")
        }
        return try checkedEnd(of: form)
    }

    /// The presets row and the last row of the controls list must both be inside the visible sheet.
    private func checkedEnd(of form: UIScrollView) throws -> UIScrollView {
        let rows = try formRows(of: form)
        let visible = sheetFrame!.intersection(window.bounds)
        for (name, frame) in [("the presets row (Rabbit)", rows.presets), ("the last row (Clear Journal)", rows.last)] {
            guard visible.contains(frame.insetBy(dx: 1, dy: 1)) else {
                throw GalleryFailure("\(name) not inside the visible sheet: \(frame) vs \(visible)")
            }
        }
        return form
    }

    /// Frames (window coordinates) of the Julia presets row and of the last row of the controls list. SwiftUI draws the
    /// Form's text itself and builds no accessibility tree in a test, so the rows are found structurally: the presets
    /// row is the cell holding a scroll view, the last row is the last item of the list.
    func formRows(of form: UIScrollView) throws -> (presets: CGRect, last: CGRect) {
        guard let list = form as? UICollectionView else { throw GalleryFailure("the controls list is not a UICollectionView") }
        let sections = list.numberOfSections
        guard sections > 0, list.numberOfItems(inSection: sections - 1) > 0 else { throw GalleryFailure("the controls list is empty") }
        guard let last = list.cellForItem(at: IndexPath(item: list.numberOfItems(inSection: sections - 1) - 1, section: sections - 1)) else {
            throw GalleryFailure("the last row of the controls list is not on screen")
        }
        // The presets row is the only row holding a scroll view (its horizontal one), whether or not the buttons overflow
        // it: on the iPad's wide sheet they all fit.
        func holdsHorizontalScroll(_ v: UIView) -> Bool {
            if v is UIScrollView { return true }
            return v.subviews.contains(where: holdsHorizontalScroll)
        }
        guard let presets = list.visibleCells.first(where: holdsHorizontalScroll) else {
            throw GalleryFailure("the presets row is not on screen")
        }
        return (presets.convert(presets.bounds, to: window), last.convert(last.bounds, to: window))
    }

    // MARK: frames

    /// Readiness steps 2 and 3: the explicit draw yields a frame of the expected state that was **submitted**, completed
    /// without error and **scheduled** (its buffer presents the drawable when scheduled), followed by two display-link
    /// ticks. Terms used everywhere: submitted/scheduled (this evidence), captured content (checked against the reference
    /// render by `validate`), and actual presentation, which is **not proven**: the iOS SDK has no per-drawable presented
    /// handler, and a capture can lag the draw. A scenario with no board region left (the large detent) has only the
    /// submitted/scheduled evidence and no content check.
    /// `arm: false` leaves the observer off, which must fail with "no frame submitted".
    func drawFrame(arm: Bool = true) async throws -> FrameEvidence {
        let record = FrameRecord()
        var tries = 0
        while true {
            if arm {
                renderer.frameObserver = { cmd, _, state in
                    record.submitted(state)
                    cmd.addCompletedHandler { record.complete($0.status, $0.error) }
                    cmd.addScheduledHandler { _ in record.schedule(CACurrentMediaTime()) }
                }
            }
            mtk.draw()
            renderer.frameObserver = nil
            if record.snapshot.0.submits > 0 { break }
            tries += 1
            if tries >= 3 { throw GalleryFailure("no frame submitted") }
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        try await waitUntil(2, "frame completed") { record.snapshot.completed }
        let done = record.snapshot.0
        guard done.completedStatus == .completed, done.completedError == nil else {
            throw GalleryFailure("frame failed: status \(String(describing: done.completedStatus)) error \(String(describing: done.completedError))")
        }
        try await waitUntil(2, "frame scheduled for presentation") { record.snapshot.presented }
        // The drawable is on screen one display frame after its buffer completed: wait for two display-link ticks.
        try await DisplayTicks.wait(2, timeout: 2)
        let result = record.snapshot.0
        guard result.scheduledTime > 0 else { throw GalleryFailure("frame not presented") }
        return result
    }

    func capture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = fixture.size.scale
        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    // MARK: content validation

    /// The region of the window whose pixels are only the fractal (plus a sheet's scrim), or nil when UI covers it.
    func fractalRegion() -> CGRect? {
        let size = window.bounds.size
        let top = window.safeAreaInsets.top
        if fixture.sheet != .none, form == .column {
            // The board stays visible beside a column (also at the large detent), clear of the peek capsule's band.
            guard let column = columnFrame else { return nil }
            return CGRect(x: 0, y: top, width: column.minX - 4, height: size.height - top - 140)
        }
        switch fixture.sheet {
        case .none:
            return CGRect(x: 0, y: top, width: size.width, height: size.height - top - 140)
        case .opening, .medium:
            guard let sheet = sheetFrame else { return nil }
            let bottom = sheet.minY - 4
            return bottom - top > 40 ? CGRect(x: 0, y: top, width: size.width, height: bottom - top) : nil
        case .large:
            return nil
        }
    }

    /// Renders `state` offscreen through the app's own `encodeFrame` into a texture of the view's drawable size.
    func referenceImage(of state: ViewState) throws -> CGImage {
        try Self.offscreenImage(renderer, state: state, width: Int(mtk.drawableSize.width),
                                height: Int(mtk.drawableSize.height), pixelFormat: mtk.colorPixelFormat)
    }

    /// Renders `state` through `encodeFrame` into a `width` x `height` texture. `opaque` drops the alpha channel (an App
    /// Store creative asset may not have one).
    static func offscreenImage(_ renderer: FractalRenderer, state: ViewState, width: Int, height: Int,
                               pixelFormat: MTLPixelFormat, opaque: Bool = false) throws -> CGImage {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let texture = renderer.device.makeTexture(descriptor: desc),
              let cmd = renderer.commandQueue.makeCommandBuffer() else { throw GalleryFailure("reference render: no texture") }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard renderer.encodeFrame(state: state, aspect: Float(width) / Float(height), into: rpd, commandBuffer: cmd) else {
            throw GalleryFailure("reference render: encode failed")
        }
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw GalleryFailure("reference render failed: \(String(describing: cmd.error))") }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let space = CGColorSpaceCreateDeviceRGB()
        let alpha = opaque ? CGImageAlphaInfo.noneSkipFirst : CGImageAlphaInfo.premultipliedFirst
        let info = CGBitmapInfo.byteOrder32Little.rawValue | alpha.rawValue
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: space, bitmapInfo: info),
              let image = ctx.makeImage() else { throw GalleryFailure("reference render: no image") }
        return image
    }

    /// One artwork as an opaque PNG (RGB, no alpha), rendered off screen at its full pixel size.
    static func artworkPNG(_ artwork: GalleryArtwork) throws -> Data {
        guard let renderer = FractalRenderer(metalView: MTKView(frame: .zero)) else { throw GalleryFailure("artwork: no Metal renderer") }
        let image = try offscreenImage(renderer, state: artwork.state, width: artwork.width, height: artwork.height,
                                       pixelFormat: .bgra8Unorm, opaque: true)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw GalleryFailure("artwork: no PNG encoder")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw GalleryFailure("artwork: PNG encoding failed") }
        return data as Data
    }

    /// The scrim (a black overlay of the sheet's dimming) a scenario may show over the board, per appearance, calibrated
    /// from the gallery: none for the plain board and the opening detent (nothing dims there: measured 0.000 to 0.001), the
    /// system's dimming at the medium detent (settled value, measured after the dimming has faded in: 0.200 in light, 0.479 in dark; the band is +-0.03 around it).
    /// The large detent leaves no board region to check. The fit takes its gain from the pixels it checks, so the band is
    /// what keeps an extra dimming or a brightening from passing as a scrim.
    func scrimBand(_ appearance: GalleryAppearance) -> ClosedRange<Double> {
        // A column beside the board dims nothing; one laid over it dims it as a medium sheet does.
        if fixture.sheet != .none, form == .column, !columnOverlaysBoard { return -0.03...0.03 }
        guard fixture.sheet == .medium || columnOverlaysBoard else { return -Self.scrimTolerance...Self.scrimTolerance }
        let measured = appearance == .light ? 0.200 : 0.479
        return (measured - 0.03)...(measured + 0.03)
    }

    static let rgbErrorBound = 0.01
    static let scrimTolerance = 0.02

    /// Compares the captured region with a reference render of `expected`: a blank, stale or different fractal fails
    /// (luminance correlation >= 0.95, or mean difference <= 0.03 for a flat reference), and so does a brightness or colour
    /// error: after fitting the sheet's scrim (a black overlay of alpha `scrim`) the mean absolute RGB difference over the
    /// 64 x 64 reduction must be <= 0.01 (measured: at most 0.0007) and the fitted scrim must lie in `scrimBand` (the
    /// fit alone would accept any uniform gain, so this is validation modulo that band).
    func validate(_ image: UIImage, expected: ViewState, region: CGRect, scrimBand: ClosedRange<Double>? = nil) throws -> ContentCheck {
        let reference = try referenceImage(of: expected)
        // The reference has the MTKView's size, which is the window's only while nothing sits beside the board (or a device
        // inset narrows it): sample the same area of both. The window region is cut to what the board covers first, so the
        // capture and the reference crops are the same area before they are reduced to 64 x 64.
        let board = mtk.convert(mtk.bounds, to: window)
        let area = region.intersection(board)
        let refScale = CGFloat(reference.width) / mtk.bounds.width
        let refRegion = mtk.convert(area, from: window)
        let a = GalleryPixels.luma64(image.cgImage!, region: area, pixelsPerPoint: image.scale)
        let b = GalleryPixels.luma64(reference, region: refRegion, pixelsPerPoint: refScale)
        let a3 = GalleryPixels.rgb64(image.cgImage!, region: area, pixelsPerPoint: image.scale)
        let b3 = GalleryPixels.rgb64(reference, region: refRegion, pixelsPerPoint: refScale)
        let fit = GalleryPixels.scrimFit(captured: a3, reference: b3)
        let band = scrimBand ?? self.scrimBand(appearance)
        var reasons: [String] = []
        let value: Double, mode: String
        if GalleryPixels.standardDeviation(b) < 0.02 {
            mode = "mad"
            value = zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Double(a.count)
            if value > 0.03 { reasons.append("mean difference \(String(format: "%.3f", value)) > 0.03") }
        } else {
            mode = "corr"
            value = GalleryPixels.pearson(a, b)
            if value < 0.95 { reasons.append("correlation \(String(format: "%.3f", value)) < 0.95") }
        }
        if !band.contains(fit.scrim) {
            reasons.append("scrim \(String(format: "%.3f", fit.scrim)) outside [\(String(format: "%.3f", band.lowerBound)), \(String(format: "%.3f", band.upperBound))]")
        }
        if fit.error > Self.rgbErrorBound { reasons.append("rgb error \(String(format: "%.3f", fit.error)) > 0.01") }
        return ContentCheck(value: value, mode: mode, scrim: fit.scrim, rgbError: fit.error,
                            passed: reasons.isEmpty, reason: reasons.isEmpty ? nil : reasons.joined(separator: ", "))
    }

    // MARK: regions

    func measureRegions() -> [GalleryRegion] {
        var regions: [GalleryRegion] = []
        let size = window.bounds.size
        for kind in fixture.regions {
            switch kind {
            case .peek:
                regions.append(GalleryRegion(.peek, CGRect(x: 0, y: size.height - 140, width: size.width, height: 140)))
            case .fractal:
                if let r = fractalRegion() { regions.append(GalleryRegion(.fractal, r)) }
            case .sheet, .sheetGlass:
                guard let frame = sheetFrame else { break }
                let visible = frame.intersection(window.bounds)
                var top = visible.minY + 16
                let barRoot: UIView? = form == .column ? window : presented?.view
                if let barRoot, let bar = Self.findNavigationBar(barRoot) {
                    top = max(top, bar.convert(bar.bounds, to: window).maxY)
                }
                let rect = CGRect(x: visible.minX + 16, y: top, width: visible.width - 32, height: visible.maxY - 16 - top)
                // A column beside the board is opaque: its glass kind is judged as a sheet.
                regions.append(GalleryRegion(form == .column && !columnOverlaysBoard && kind == .sheetGlass ? .sheet : kind, rect))
            }
        }
        return regions
    }

    static func findNavigationBar(_ view: UIView) -> UINavigationBar? {
        if let bar = view as? UINavigationBar { return bar }
        for sub in view.subviews { if let bar = findNavigationBar(sub) { return bar } }
        return nil
    }
}

/// Waits for display-link ticks (the compositor ran), bounded.
@MainActor
final class DisplayTicks: NSObject {
    private var link: CADisplayLink?
    private var ticks = 0

    @objc private func tick() { ticks += 1 }

    static func wait(_ count: Int, timeout: TimeInterval) async throws {
        let t = DisplayTicks()
        t.link = CADisplayLink(target: t, selector: #selector(tick))
        t.link!.add(to: .main, forMode: .common)
        defer { t.link?.invalidate() }
        let deadline = Date().addingTimeInterval(timeout)
        while t.ticks < count {
            if Date() > deadline { throw GalleryFailure("timeout (\(timeout) s): display frames") }
            try await Task.sleep(nanoseconds: 4_000_000)
        }
    }
}

/// The decision of `settleScrim`, pure so that it is tested: settled when the last `window` fitted scrims span no more than
/// `epsilon` (max - min), so a steady drift whose adjacent steps are small is not settled.
enum ScrimSettling {
    static let window = 3
    static let epsilon = 0.004

    static func isSettled(_ samples: [Double], window: Int = ScrimSettling.window, epsilon: Double = ScrimSettling.epsilon) -> Bool {
        guard samples.count >= window, let lo = samples.suffix(window).min(), let hi = samples.suffix(window).max() else { return false }
        return hi - lo <= epsilon
    }
}

enum GalleryPixels {
    /// The region reduced to 64 x 64 luminance values (0...1).
    static func luma64(_ image: CGImage, region: CGRect, pixelsPerPoint: CGFloat) -> [Double] {
        let rect = CGRect(x: region.minX * pixelsPerPoint, y: region.minY * pixelsPerPoint,
                          width: region.width * pixelsPerPoint, height: region.height * pixelsPerPoint)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let crop = image.cropping(to: rect) else { return [Double](repeating: 0, count: 64 * 64) }
        var pixels = [UInt8](repeating: 0, count: 64 * 64)
        let ctx = CGContext(data: &pixels, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        return pixels.map { Double($0) / 255 }
    }

    /// The region reduced to 64 x 64 RGB values (0...1), interleaved.
    static func rgb64(_ image: CGImage, region: CGRect, pixelsPerPoint: CGFloat) -> [Double] {
        let rect = CGRect(x: region.minX * pixelsPerPoint, y: region.minY * pixelsPerPoint,
                          width: region.width * pixelsPerPoint, height: region.height * pixelsPerPoint)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let crop = image.cropping(to: rect) else { return [Double](repeating: 0, count: 64 * 64 * 3) }
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let ctx = CGContext(data: &pixels, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        var out: [Double] = []
        out.reserveCapacity(64 * 64 * 3)
        for i in 0..<(64 * 64) { for c in 0..<3 { out.append(Double(pixels[i * 4 + c]) / 255) } }
        return out
    }

    /// Fits captured = (1 - scrim) x reference (a black overlay) by least squares; the error is the mean absolute
    /// difference left over.
    static func scrimFit(captured: [Double], reference: [Double]) -> (scrim: Double, error: Double) {
        let dot = zip(captured, reference).map { $0 * $1 }.reduce(0, +)
        let norm = reference.map { $0 * $0 }.reduce(0, +)
        let scrim = norm > 1e-9 ? 1 - dot / norm : 0
        let error = zip(captured, reference).map { abs($0 - (1 - scrim) * $1) }.reduce(0, +) / Double(captured.count)
        return (scrim, error)
    }

    static func mean(_ v: [Double]) -> Double { v.reduce(0, +) / Double(v.count) }

    static func standardDeviation(_ v: [Double]) -> Double {
        let m = mean(v)
        return (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(v.count)).squareRoot()
    }

    static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let ma = mean(a), mb = mean(b)
        var num = 0.0, da = 0.0, db = 0.0
        for (x, y) in zip(a, b) {
            num += (x - ma) * (y - mb)
            da += (x - ma) * (x - ma)
            db += (y - mb) * (y - mb)
        }
        guard da > 0, db > 0 else { return 0 }
        return num / (da * db).squareRoot()
    }
}

@MainActor
enum GalleryHarness {
    /// Injected by the tests that check the replay bound.
    static var clock: () -> Date = Date.init
    static var activeScenePhase = true
    private static var hostPaused = false

    /// The host app's own window runs a ContentView on the standard defaults: pause its MTKView once so it does not
    /// compete for the GPU. Nothing the scenarios read.
    static func pauseHostApp() {
        guard !hostPaused else { return }
        hostPaused = true
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { if let m = GalleryMount.findMTK(window) { m.isPaused = true } }
        }
    }

    static func mount(_ scenario: GalleryScenario, _ appearance: GalleryAppearance) async throws -> GalleryMount {
        pauseHostApp()
        let mount = GalleryMount(scenario: scenario, appearance: appearance, activeScenePhase: activeScenePhase)
        mount.show()
        do {
            try await mount.settleLayout()
        } catch {
            mount.teardown()
            throw error
        }
        return mount
    }

    /// One render: mount, settle, scroll, our frame, capture, validate, regions. Throws with the reason.
    static func render(_ scenario: GalleryScenario, _ appearance: GalleryAppearance) async throws -> RenderResult {
        let t0 = Date()
        let mount = try await Self.mount(scenario, appearance)
        defer { mount.teardown() }
        let fixture = scenario.fixture
        if fixture.scrollToEnd { try await mount.scrollSheetToEnd() }
        try await mount.settleScrim()
        try await mount.settlePeek()

        var redraws = 0
        var submits = 0
        var image: UIImage
        var check: ContentCheck?
        var readyMs = 0
        while true {
            let evidence = try await mount.drawFrame()
            submits += evidence.submits
            guard evidence.state == fixture.expectedState else {
                throw GalleryFailure("the frame encoded another state than the scenario's")
            }
            if readyMs == 0 { readyMs = Int(Date().timeIntervalSince(t0) * 1000) }
            image = mount.capture()
            if let region = mount.fractalRegion() {
                let c = try mount.validate(image, expected: fixture.expectedState, region: region)
                check = c
                if !c.passed {
                    if redraws >= 2 {
                        throw GalleryFailure("content does not match the reference (\(c.reason ?? ""))")
                    }
                    redraws += 1
                    print("gallery: \(scenario.slug) \(appearance.rawValue) redraw \(redraws) (\(c.reason ?? ""))")
                    continue
                }
            }
            break
        }
        if fixture.replays, let started = mount.replayStartedAt, clock().timeIntervalSince(started) > 10 {
            throw GalleryFailure("replay: the capture ended more than 10 s after replay() (the snap to A lasts 15 s)")
        }
        if let started = mount.replayStartedAt, mount.store.state != fixture.expectedState {
            _ = started
            throw GalleryFailure("replay: the store is no longer in snapshot A")
        }
        let regions = mount.measureRegions()
        let total = Int(Date().timeIntervalSince(t0) * 1000)
        let sheet = mount.sheetFrame
        let detent = mount.form == .column && fixture.sheet != .none
            ? "column" : mount.sheetController?.selectedDetentIdentifier?.rawValue
        return RenderResult(png: image.pngData()!, regions: regions, readyMs: readyMs, totalMs: total,
                            submits: submits, redraws: redraws, check: check, detent: detent,
                            sheetHeight: sheet.map { Double($0.intersection(mount.window.bounds).height) },
                            safeLeft: Double(mount.window.safeAreaInsets.left), safeRight: Double(mount.window.safeAreaInsets.right))
    }
}
