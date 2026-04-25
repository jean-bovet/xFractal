import SwiftUI
import simd

struct ContentView: View {
    @StateObject private var store = StateStore()
    @State private var viewSize: CGSize = .zero
    @State private var dragStartCenter: SIMD2<Double>? = nil
    @State private var pinchStartScale: Double? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            MandelbrotView(center: $store.state.center,
                           scale: $store.state.scale,
                           maxIterations: $store.state.maxIterations,
                           usePerturbation: $store.state.usePerturbation,
                           viewSize: $viewSize)
                .gesture(viewGestures)
                .allowsHitTesting(!store.isReplaying)

            hud
        }
        .ignoresSafeArea()
    }

    private var viewGestures: some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartCenter == nil { dragStartCenter = store.state.center }
                    let h = max(Double(viewSize.height), 1)
                    let pxToWorld = (2.0 * store.state.scale) / h
                    let dx = Double(value.translation.width) * pxToWorld
                    let dy = Double(value.translation.height) * pxToWorld
                    if let s = dragStartCenter {
                        store.state.center = SIMD2<Double>(s.x - dx, s.y + dy)
                    }
                }
                .onEnded { _ in dragStartCenter = nil },
            MagnificationGesture()
                .onChanged { value in
                    if pinchStartScale == nil { pinchStartScale = store.state.scale }
                    if let s = pinchStartScale {
                        store.state.scale = max(1e-15, s / Double(value))
                    }
                }
                .onEnded { _ in pinchStartScale = nil }
        )
    }

    private var hud: some View {
        HStack(spacing: 14) {
            iterationControl

            Toggle("Perturb", isOn: $store.state.usePerturbation)
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()

            Spacer(minLength: 0)

            Button {
                store.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }

            Button {
                if store.isReplaying { store.stopReplay() } else { store.replay() }
            } label: {
                Label(store.isReplaying ? "Stop" : "Replay",
                      systemImage: store.isReplaying ? "stop.fill" : "play.fill")
            }
            .disabled(store.journal.count < 2)

            Button {
                store.clearJournal()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(store.journal.isEmpty || store.isReplaying)
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var iterationControl: some View {
        HStack(spacing: 8) {
            Text("Iter \(store.state.maxIterations)")
                .monospacedDigit()
                .font(.caption)
                .frame(minWidth: 70, alignment: .leading)
            Slider(value: Binding(
                get: { Double(store.state.maxIterations) },
                set: { store.state.maxIterations = UInt32($0) }
            ), in: 64...4096)
                .frame(minWidth: 160, idealWidth: 220)
        }
    }
}
