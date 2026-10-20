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
        let content = built.makeView(probe)
        let root: AnyView
        if activeScenePhase {
            // The real app's foreground state: a test window's scene phase is .background, which pauses the MTKView.
            root = AnyView(content.environment(\.scenePhase, .active)
                .background(SizeClassProbe { [sizeClasses] in sizeClasses.outer = $0 }))
        } else {
            root = AnyView(content.background(SizeClassProbe { [sizeClasses] in sizeClasses.outer = $0 }))
        }
        host = UIHostingController(rootView: root)
        if scenario.fixture.size == .regularWidth {
            host.traitOverrides.horizontalSizeClass = .regular
            // The presented sheet takes its traits from the window, not from the presenting controller.
            window.traitOverrides.horizontalSizeClass = .regular
        }
    }

    var store: StateStore { built.store }
    var fixture: GalleryFixture { scenario.fixture }
    var presented: UIViewController? { host.presentedViewController }
    var sheetController: UISheetPresentationController? { presented?.sheetPresentationController }

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

    var sheetFrame: CGRect? {
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
        guard fixture.sheet != .none else { return }
        try await waitUntil(5, "the sheet presented") {
            guard let p = presented else { return false }
            return !p.isBeingPresented && p.transitionCoordinator == nil && sheetController != nil
        }
        if fixture.size == .regularWidth, let presented {
            // The sheet takes its adaptation from the phone, but its content can be told the regular width.
            presented.traitOverrides.horizontalSizeClass = .regular
        }
        if fixture.sheet == .medium || fixture.sheet == .large {
            let controller = sheetController!
            let ids = controller.detents.map(\.identifier)
            guard ids.count == 3, ids.contains(.medium), ids.contains(.large) else {
                throw GalleryFailure("unexpected sheet detents: \(ids.map(\.rawValue))")
            }
            let wanted: UISheetPresentationController.Detent.Identifier = fixture.sheet == .medium ? .medium : .large
            controller.animateChanges { controller.selectedDetentIdentifier = wanted }
            try await waitUntil(5, "detent \(wanted.rawValue) selected") { controller.selectedDetentIdentifier == wanted }
        }
        try await waitStableSheetFrame()
    }

    func waitStableSheetFrame() async throws {
        var last: CGRect?
        var same = 0
        try await waitUntil(10, "the sheet frame stable") {
            window.layoutIfNeeded()
            let frame = sheetFrame
            if let frame, frame == last { same += 1 } else { same = 0 }
            last = frame
            return same >= 3 && presented?.transitionCoordinator == nil
        }
    }

    /// The sheet's dimming fades in after its frame has settled, and the animation's end is not observable from here: wait
    /// (bounded) until `ScrimSettling` finds the fitted scrim of the board region flat over its last samples. Only where a
    /// board region and a scrim exist (the medium detent).
    func settleScrim() async throws {
        guard fixture.sheet == .medium, let region = fractalRegion() else { return }
        _ = try await drawFrame()
        var samples: [Double] = []
        let deadline = Date().addingTimeInterval(4)
        while !ScrimSettling.isSettled(samples) {
            if Date() > deadline { throw GalleryFailure("timeout (4 s): the sheet's dimming did not settle (samples \(samples.suffix(4)))") }
            try await Task.sleep(nanoseconds: 100_000_000)
            samples.append(try validate(capture(), expected: fixture.expectedState, region: region, scrimBand: -1...1).scrim)
        }
    }

    /// A capture-sized image of the reference render multiplied by `gain` (a pure gain: no offset), for the tests.
    func gainedReference(of state: ViewState, gain: Double) throws -> UIImage {
        let reference = try referenceImage(of: state)
        let w = reference.width, h = reference.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(reference, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in stride(from: 0, to: bytes.count, by: 4) {
            for c in 0..<3 { bytes[i + c] = UInt8(max(0, min(255, (Double(bytes[i + c]) * gain).rounded()))) }
        }
        guard let image = ctx.makeImage() else { throw GalleryFailure("gained reference: no image") }
        return UIImage(cgImage: image, scale: CGFloat(w) / window.bounds.width, orientation: .up)
    }

    // MARK: scroll

    @discardableResult
    func scrollSheetToEnd() async throws -> UIScrollView {
        guard let root = presented?.view else { throw GalleryFailure("no sheet to scroll") }
        var scrolls: [UIScrollView] = []
        func collect(_ v: UIView) {
            if let s = v as? UIScrollView { scrolls.append(s) }
            v.subviews.forEach(collect)
        }
        collect(root)
        func extent(_ s: UIScrollView) -> CGFloat {
            s.contentSize.height + s.adjustedContentInset.top + s.adjustedContentInset.bottom - s.bounds.height
        }
        let form = scrolls.filter { extent($0) > 0 && $0.contentSize.width <= $0.bounds.width + 0.5 }
            .max { extent($0) < extent($1) }
        guard let form else { throw GalleryFailure("no vertical scroll view in the sheet") }
        let target = form.contentSize.height + form.adjustedContentInset.bottom - form.bounds.height
        form.setContentOffset(CGPoint(x: form.contentOffset.x, y: target), animated: false)
        try await waitStableSheetFrame()
        try await waitUntil(2, "scroll offset held") { abs(form.contentOffset.y - target) <= 1 }
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
    /// row is the cell holding the horizontal scroll view, the last row is the last item of the list.
    func formRows(of form: UIScrollView) throws -> (presets: CGRect, last: CGRect) {
        guard let list = form as? UICollectionView else { throw GalleryFailure("the controls list is not a UICollectionView") }
        let sections = list.numberOfSections
        guard sections > 0, list.numberOfItems(inSection: sections - 1) > 0 else { throw GalleryFailure("the controls list is empty") }
        guard let last = list.cellForItem(at: IndexPath(item: list.numberOfItems(inSection: sections - 1) - 1, section: sections - 1)) else {
            throw GalleryFailure("the last row of the controls list is not on screen")
        }
        func holdsHorizontalScroll(_ v: UIView) -> Bool {
            if let s = v as? UIScrollView, s.contentSize.width > s.bounds.width + 1 { return true }
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
        format.scale = 2
        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    // MARK: content validation

    /// The region of the window whose pixels are only the fractal (plus a sheet's scrim), or nil when UI covers it.
    func fractalRegion() -> CGRect? {
        let size = window.bounds.size
        let top = window.safeAreaInsets.top
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
        guard fixture.sheet == .medium else { return -Self.scrimTolerance...Self.scrimTolerance }
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
        let refScale = CGFloat(reference.width) / window.bounds.width
        let a = GalleryPixels.luma64(image.cgImage!, region: region, pixelsPerPoint: image.scale)
        let b = GalleryPixels.luma64(reference, region: region, pixelsPerPoint: refScale)
        let a3 = GalleryPixels.rgb64(image.cgImage!, region: region, pixelsPerPoint: image.scale)
        let b3 = GalleryPixels.rgb64(reference, region: region, pixelsPerPoint: refScale)
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
                if let presentedView = presented?.view, let bar = Self.findNavigationBar(presentedView) {
                    top = max(top, bar.convert(bar.bounds, to: window).maxY)
                }
                let rect = CGRect(x: visible.minX + 16, y: top, width: visible.width - 32, height: visible.maxY - 16 - top)
                regions.append(GalleryRegion(kind, rect))
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
        let detent = mount.sheetController?.selectedDetentIdentifier?.rawValue
        return RenderResult(png: image.pngData()!, regions: regions, readyMs: readyMs, totalMs: total,
                            submits: submits, redraws: redraws, check: check, detent: detent,
                            sheetHeight: sheet.map { Double($0.intersection(mount.window.bounds).height) })
    }
}
