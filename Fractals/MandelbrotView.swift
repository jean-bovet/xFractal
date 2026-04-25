import SwiftUI
import MetalKit

#if os(macOS)
typealias PlatformRepresentable = NSViewRepresentable

final class ZoomableMTKView: MTKView {
    var onScrollZoom: ((_ factor: Float, _ anchorUV: SIMD2<Float>) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * 10.0

        let factor = Float(exp(-dy * 0.01))

        let p = convert(event.locationInWindow, from: nil)
        let w = max(bounds.width, 1)
        let h = max(bounds.height, 1)
        let anchor = SIMD2<Float>(Float(p.x / w), Float(p.y / h))

        onScrollZoom?(factor, anchor)
    }
}
#else
typealias PlatformRepresentable = UIViewRepresentable
#endif

struct MandelbrotView: PlatformRepresentable {
    @Binding var center: SIMD2<Float>
    @Binding var scale: Float
    @Binding var maxIterations: UInt32
    @Binding var viewSize: CGSize

    final class Coordinator {
        var renderer: MandelbrotRenderer?
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

        let renderer = MandelbrotRenderer(metalView: view)
        renderer?.center = center
        renderer?.scale = scale
        renderer?.maxIterations = maxIterations
        view.delegate = renderer
        context.coordinator.renderer = renderer

        #if os(macOS)
        view.onScrollZoom = { [weak view] factor, anchor in
            guard let view, let r = context.coordinator.renderer else { return }
            // Anchor is in [0,1] view coords with origin at bottom-left (AppKit).
            // Convert to centered, aspect-corrected world delta from view center.
            let aspect = r.aspect
            let s = r.scale
            let nx = (Float(anchor.x) * 2.0 - 1.0) * aspect
            let ny = (Float(anchor.y) * 2.0 - 1.0)
            let anchorWorld = r.center + SIMD2<Float>(nx, ny) * s

            let newScale = max(1e-7, s * factor)
            // Keep the world point under the cursor stationary.
            let newCenter = anchorWorld - SIMD2<Float>(nx, ny) * newScale

            r.scale = newScale
            r.center = newCenter
            DispatchQueue.main.async {
                self.scale = newScale
                self.center = newCenter
            }
        }
        #endif

        return view
    }

    private func update(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.center = center
        context.coordinator.renderer?.scale = scale
        context.coordinator.renderer?.maxIterations = maxIterations
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
