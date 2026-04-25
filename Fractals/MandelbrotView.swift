import SwiftUI
import MetalKit

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

struct MandelbrotView: PlatformRepresentable {
    @Binding var center: SIMD2<Double>
    @Binding var scale: Double
    @Binding var maxIterations: UInt32
    @Binding var usePerturbation: Bool
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
        renderer?.usePerturbation = usePerturbation
        view.delegate = renderer
        context.coordinator.renderer = renderer

        #if os(macOS)
        view.onScrollZoom = { [weak view] factor, anchor in
            guard let view, let r = context.coordinator.renderer else { return }
            _ = view
            let aspect = Double(r.aspect)
            let s = r.scale
            let nx = (anchor.x * 2.0 - 1.0) * aspect
            let ny = (anchor.y * 2.0 - 1.0)
            let anchorWorld = r.center + SIMD2<Double>(nx, ny) * s

            let newScale = max(1e-15, s * factor)
            let newCenter = anchorWorld - SIMD2<Double>(nx, ny) * newScale

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
        context.coordinator.renderer?.usePerturbation = usePerturbation
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
