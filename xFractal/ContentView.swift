import SwiftUI
import simd

struct ContentView: View {
    @StateObject private var store = StateStore()
    @State private var viewSize: CGSize = .zero
    @State private var dragStartCenter: SIMD2<Double>? = nil
    @State private var pinchStartScale: Double? = nil
    @State private var showingPanel: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            FractalView(state: $store.state, viewSize: $viewSize)
                .gesture(viewGestures)
                .allowsHitTesting(!store.isReplaying)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                if showingPanel { paramPanel }
                hud
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
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
        HStack(spacing: 12) {
            typePicker

            iterationControl

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showingPanel.toggle() }
            } label: {
                Image(systemName: showingPanel ? "slider.horizontal.3.fill" : "slider.horizontal.3")
            }

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
        #if os(macOS)
        .labelStyle(.titleAndIcon)
        #else
        .labelStyle(.iconOnly)
        #endif
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
    }

    private var typePicker: some View {
        Picker("Type", selection: Binding(
            get: { store.state.type },
            set: { store.switchType(to: $0) }
        )) {
            ForEach(FractalType.allCases) { t in
                Text(t.label).tag(t)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
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
            ), in: 32...4096)
            #if os(macOS)
                .frame(minWidth: 140, idealWidth: 200)
            #else
                .frame(minWidth: 80)
            #endif
        }
    }

    @ViewBuilder
    private var paramPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Palette", selection: $store.state.palette) {
                    ForEach(Palette.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Toggle("Smooth", isOn: $store.state.smooth)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()

                if store.state.type.supportsPerturbation {
                    Toggle("Perturb", isOn: $store.state.usePerturbation)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .fixedSize()
                }

                Spacer(minLength: 0)
            }

            switch store.state.type {
            case .julia:
                juliaControls
            case .multibrot:
                multibrotControls
            case .newton:
                newtonControls
            case .mandelbrot:
                EmptyView()
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    private var juliaControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("c.re")
                    .font(.caption)
                    .frame(width: 36, alignment: .leading)
                Slider(value: $store.state.juliaCx, in: -1.5...1.5)
                Text(String(format: "%.4f", store.state.juliaCx))
                    .monospacedDigit()
                    .font(.caption)
                    .frame(width: 64, alignment: .trailing)
            }
            HStack {
                Text("c.im")
                    .font(.caption)
                    .frame(width: 36, alignment: .leading)
                Slider(value: $store.state.juliaCy, in: -1.5...1.5)
                Text(String(format: "%.4f", store.state.juliaCy))
                    .monospacedDigit()
                    .font(.caption)
                    .frame(width: 64, alignment: .trailing)
            }
            HStack(spacing: 8) {
                ForEach(juliaPresets, id: \.label) { preset in
                    Button(preset.label) {
                        store.state.juliaCx = preset.c.x
                        store.state.juliaCy = preset.c.y
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var juliaPresets: [(label: String, c: SIMD2<Double>)] {
        [
            ("Dendrite",   SIMD2<Double>( 0.0,    1.0)),
            ("Spiral",     SIMD2<Double>(-0.7,    0.27015)),
            ("Rabbit",     SIMD2<Double>(-0.123,  0.745)),
            ("Galaxy",     SIMD2<Double>(-0.8,    0.156)),
            ("San Marco",  SIMD2<Double>(-0.75,   0.0)),
        ]
    }

    private var multibrotControls: some View {
        HStack(spacing: 12) {
            Text("Exponent")
                .font(.caption)
            Stepper(value: Binding(
                get: { Int(store.state.multibrotExponent) },
                set: { store.state.multibrotExponent = UInt32(max(2, min(8, $0))) }
            ), in: 2...8) {
                Text("n = \(store.state.multibrotExponent)")
                    .monospacedDigit()
                    .font(.caption)
            }
            .fixedSize()
            Spacer(minLength: 0)
        }
    }

    private var newtonControls: some View {
        HStack(spacing: 12) {
            Text("Polynomial")
                .font(.caption)
            Picker("Polynomial", selection: Binding(
                get: { Int(store.state.newtonFlavor) },
                set: { store.state.newtonFlavor = UInt32($0) }
            )) {
                Text("z³ − 1").tag(0)
                Text("z³ − 2z + 2").tag(1)
                Text("z⁸ + 15z⁴ − 16").tag(2)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
        }
    }
}
