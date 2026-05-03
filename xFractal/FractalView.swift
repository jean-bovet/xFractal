import SwiftUI
import MetalKit
import simd

#if os(macOS)
typealias PlatformRepresentable = NSViewRepresentable

final class ZoomableMTKView: MTKView {
    var onScrollZoom: ((_ factor: Double, _ anchorUV: SIMD2<Double>) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * 10.0

        let factor = exp(-dy * 0.01)

        let p = convert(event.locationInWindow, from: nil)
        let w = max(bounds.width, 1)
        let h = max(bounds.height, 1)
        let anchor = SIMD2<Double>(Double(p.x / w), Double(p.y / h))

        onScrollZoom?(factor, anchor)
    }
}
#else
typealias PlatformRepresentable = UIViewRepresentable
#endif

struct FractalView: PlatformRepresentable {
    @Binding var state: ViewState
    @Binding var viewSize: CGSize

    final class Coordinator {
        var renderer: FractalRenderer?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    private func make(context: Context) -> MTKView {
        #if os(macOS)
        let view = ZoomableMTKView()
        #else
        let view = MTKView()
        #endif
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = true

        let renderer = FractalRenderer(metalView: view)
        renderer?.state = state
        view.delegate = renderer
        context.coordinator.renderer = renderer

        #if os(macOS)
        view.onScrollZoom = { [weak view] factor, anchor in
            guard let view, let r = context.coordinator.renderer else { return }
            _ = view
            // Cocoa locationInWindow is y-up, so anchor is already y-up: no flip.
            let ndc = unitToNDC(anchor, aspect: Double(r.aspect))
            let newScale = max(1e-15, r.state.scale * factor)
            let newCenter = anchoredZoomCenter(center: r.state.center,
                                               scale: r.state.scale,
                                               anchorNDC: ndc,
                                               newScale: newScale)
            r.state.scale = newScale
            r.state.center = newCenter
            DispatchQueue.main.async {
                self.state.scale = newScale
                self.state.center = newCenter
            }
        }
        #endif

        return view
    }

    private func update(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.state = state
        DispatchQueue.main.async {
            if viewSize != view.bounds.size { viewSize = view.bounds.size }
        }
    }

    #if os(macOS)
    func makeNSView(context: Context) -> MTKView { make(context: context) }
    func updateNSView(_ v: MTKView, context: Context) { update(v, context: context) }
    #else
    func makeUIView(context: Context) -> MTKView { make(context: context) }
    func updateUIView(_ v: MTKView, context: Context) { update(v, context: context) }
    #endif
}
