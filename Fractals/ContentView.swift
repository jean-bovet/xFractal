import SwiftUI
import simd

struct ContentView: View {
    @State private var center = SIMD2<Float>(-0.5, 0.0)
    @State private var scale: Float = 1.5
    @State private var maxIterations: UInt32 = 512
    @State private var viewSize: CGSize = .zero

    @State private var dragStartCenter: SIMD2<Float>? = nil
    @State private var pinchStartScale: Float? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            MandelbrotView(center: $center,
                           scale: $scale,
                           maxIterations: $maxIterations,
                           viewSize: $viewSize)
                .gesture(
                    SimultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartCenter == nil { dragStartCenter = center }
                                let h = max(Float(viewSize.height), 1)
                                let pxToWorld = (2.0 * scale) / h
                                let dx = Float(value.translation.width) * pxToWorld
                                let dy = Float(value.translation.height) * pxToWorld
                                if let s = dragStartCenter {
                                    center = SIMD2<Float>(s.x - dx, s.y + dy)
                                }
                            }
                            .onEnded { _ in dragStartCenter = nil },
                        MagnificationGesture()
                            .onChanged { value in
                                if pinchStartScale == nil { pinchStartScale = scale }
                                if let s = pinchStartScale {
                                    scale = max(1e-7, s / Float(value))
                                }
                            }
                            .onEnded { _ in pinchStartScale = nil }
                    )
                )

            HStack {
                Text("Iter: \(maxIterations)")
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Slider(value: Binding(
                    get: { Double(maxIterations) },
                    set: { maxIterations = UInt32($0) }
                ), in: 64...4096)
                Button("Reset") {
                    center = SIMD2<Float>(-0.5, 0.0)
                    scale = 1.5
                    maxIterations = 512
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.black.opacity(0.5))
            .padding()
        }
        .ignoresSafeArea()
    }
}
