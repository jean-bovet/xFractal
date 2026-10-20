import XCTest
import SwiftUI
import AppKit
import MetalKit
import QuartzCore
@testable import xFractal

/// Renders the Mac app's window for the Mac App Store screenshots: the real `ContentView` (title bar, HUD, parameter
/// panel) in a window that is never on screen, drawn by Core Animation's `CARenderer` at 2x. The fractal itself is a
/// `CAMetalLayer`, which `CARenderer` does not draw, so the capture paints it with the app's own `encodeFrame` (the
/// pixels the window shows) as a sublayer of the Metal view's layer for that one frame.
/// Skipped unless XFRACTAL_MAC_SNAPSHOT is set (scripts/snapshot-mac.sh). The host app is sandboxed and macOS keeps
/// other processes out of its container, so each PNG goes out on stdout: `mac-gallery-png <name> <base64 chunk>` lines,
/// which the script joins and decodes.
@MainActor
final class MacWindowSnapshotTests: XCTestCase {
    struct Scenario {
        var name: String
        var state: ViewState
        var panel = false
    }

    /// The window's content size in points (2200 x 1400 px plus the title bar at 2x).
    static let size = CGSize(width: 1100, height: 700)

    static var scenarios: [Scenario] {
        var deepZoom = ViewState.defaultState
        deepZoom.centerX = -0.743643887037151; deepZoom.centerY = 0.131825904205330
        deepZoom.scale = 1e-10; deepZoom.maxIterations = 2048; deepZoom.usePerturbation = true
        var spiral = ViewState.defaults(for: .julia)
        spiral.juliaCx = -0.7; spiral.juliaCy = 0.27015
        spiral.palette = .chromatic
        var rabbit = ViewState.defaults(for: .julia)
        rabbit.juliaCx = -0.123; rabbit.juliaCy = 0.745
        rabbit.palette = .cold
        return [
            Scenario(name: "mac-mandelbrot", state: .defaultState),
            Scenario(name: "mac-deep-zoom", state: deepZoom),
            Scenario(name: "mac-julia-spiral", state: spiral),
            Scenario(name: "mac-controls-julia", state: rabbit, panel: true),
        ]
    }

    func testRenderMacWindows() async throws {
        guard ProcessInfo.processInfo.environment["XFRACTAL_MAC_SNAPSHOT"] != nil else {
            throw XCTSkip("XFRACTAL_MAC_SNAPSHOT not set")
        }
        for scenario in Self.scenarios {
            let t0 = Date()
            let base64 = try await render(scenario).base64EncodedString()
            var start = base64.startIndex
            while start < base64.endIndex {
                let end = base64.index(start, offsetBy: 65_536, limitedBy: base64.endIndex) ?? base64.endIndex
                print("mac-gallery-png \(scenario.name) \(base64[start..<end])")
                start = end
            }
            print("mac-gallery: \(scenario.name) in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        }
    }

    // MARK: mount

    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
        override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
            if place == .out { super.order(place, relativeTo: otherWin) }
        }
        override func orderFront(_ sender: Any?) {}
        override func orderFrontRegardless() {}
        override func makeKeyAndOrderFront(_ sender: Any?) {}
    }

    private func render(_ scenario: Scenario) async throws -> Data {
        let suite = "mac-gallery.\(scenario.name)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(scenario.state), forKey: StateStore.stateKey)
        let store = StateStore(defaults: defaults)

        let window = OffscreenWindow(contentRect: NSRect(origin: CGPoint(x: -30_000, y: -30_000), size: Self.size),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: false)
        window.title = "xFractal"
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.appearance = NSAppearance(named: .aqua)
        let hosting = NSHostingView(rootView: ContentView(store: store, showingPanel: scenario.panel))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(Self.size)
        defer { window.close() }

        var mtk: MTKView?
        for _ in 0..<100 {
            pass(window)
            if let view = Self.findMTK(hosting), view.drawableSize.width > 0, view.delegate is FractalRenderer {
                mtk = view
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let mtk, let renderer = mtk.delegate as? FractalRenderer, let metalLayer = mtk.layer else {
            throw Failure("\(scenario.name): the Metal view never got a drawable size")
        }
        try await Task.sleep(nanoseconds: 300_000_000)   // SwiftUI's asynchronous tail (the HUD's layout)
        pass(window)

        let fractal = try Self.fractalImage(renderer, state: store.state, size: mtk.drawableSize)
        let overlay = CALayer()
        overlay.contents = fractal
        overlay.contentsGravity = .resize
        overlay.frame = metalLayer.bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        metalLayer.addSublayer(overlay)
        CATransaction.commit()
        defer {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            overlay.removeFromSuperlayer()
            CATransaction.commit()
        }
        let image = try Self.capture(window)
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = window.frame.size
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure("\(scenario.name): no PNG") }
        return png
    }

    /// The display passes AppKit runs before showing a window: a window that is never on screen gets no others.
    private func pass(_ window: NSWindow) {
        _ = window.contentView
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private static func findMTK(_ view: NSView) -> MTKView? {
        if let mtk = view as? MTKView { return mtk }
        for sub in view.subviews { if let found = findMTK(sub) { return found } }
        return nil
    }

    // MARK: fractal

    /// `state` rendered through `encodeFrame` at the Metal view's drawable size (top row first, opaque).
    private static func fractalImage(_ renderer: FractalRenderer, state: ViewState, size: CGSize) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let texture = renderer.device.makeTexture(descriptor: desc),
              let cmd = renderer.commandQueue.makeCommandBuffer() else { throw Failure("fractal: no texture") }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard renderer.encodeFrame(state: state, aspect: Float(width) / Float(height), into: rpd, commandBuffer: cmd) else {
            throw Failure("fractal: encode failed")
        }
        cmd.commit()
        cmd.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info),
              let image = ctx.makeImage() else { throw Failure("fractal: no image") }
        return image
    }

    // MARK: capture (CARenderer: the window's whole layer tree into a Metal texture)

    private static func capture(_ window: NSWindow, scale: CGFloat = 2) throws -> CGImage {
        guard window.backingScaleFactor == scale else { throw Failure("needs a Retina (2x) display") }
        guard let content = window.contentView else { throw Failure("no content") }
        let frameView = content.superview ?? content
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        guard var root = frameView.layer else { throw Failure("no layer") }
        while let parent = root.superlayer { root = parent }

        let width = Int((root.frame.width * scale).rounded()), height = Int((root.frame.height * scale).rounded())
        guard width > 0, height > 0, let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw Failure("no Metal device") }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw Failure("no texture") }

        let clear = MTLRenderPassDescriptor()
        clear.colorAttachments[0].texture = texture
        clear.colorAttachments[0].loadAction = .clear
        clear.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        clear.colorAttachments[0].storeAction = .store
        guard let clearing = queue.makeCommandBuffer(),
              let encoder = clearing.makeRenderCommandEncoder(descriptor: clear) else { throw Failure("no command buffer") }
        encoder.endEncoding()
        clearing.commit()

        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let renderer = CARenderer(mtlTexture: texture,
                                  options: [kCARendererColorSpace: sRGB, kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        renderer.bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))

        let saved = (root.transform, root.position, root.anchorPoint)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        root.anchorPoint = .zero
        root.position = .zero
        root.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
        defer {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            (root.transform, root.position, root.anchorPoint) = saved
            CATransaction.commit()
            CATransaction.flush()
        }
        CATransaction.flush()

        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        guard let fence = queue.makeCommandBuffer() else { throw Failure("no command buffer") }
        fence.commit()
        fence.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let upsideDown = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: sRGB,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                           | CGBitmapInfo.byteOrder32Little.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure("readback") }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(upsideDown, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw Failure("no image") }
        return image
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
