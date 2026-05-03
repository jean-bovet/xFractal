import SwiftUI
import simd

struct ContentView: View {
    @StateObject private var store = StateStore()
    @State private var viewSize: CGSize = .zero
    @State private var dragLastLocation: CGPoint? = nil
    @State private var pinchState: PinchState? = nil
    @State private var showingPanel: Bool = false
    @State private var showingSheet: Bool = false

    private struct PinchState {
        let startCenter: SIMD2<Double>
        let startScale: Double
        let anchorNDC: SIMD2<Double>
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            FractalView(state: $store.state, viewSize: $viewSize)
                .gesture(viewGestures)
                .allowsHitTesting(!store.isReplaying)
                .ignoresSafeArea()

            #if os(macOS)
            VStack(spacing: 10) {
                if showingPanel { paramPanel }
                hud
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            #else
            iOSPeek
                .padding(.bottom, 12)
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showingSheet) {
            iOSControlsSheet
                .presentationDetents([.height(260), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(260)))
        }
        #endif
    }

    private var viewGestures: some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // While pinching, only track the finger's location; pinch
                    // owns the center. This avoids any accumulated drag delta
                    // surviving past the pinch and producing a jump.
                    if pinchState != nil {
                        dragLastLocation = value.location
                        return
                    }
                    guard let last = dragLastLocation else {
                        dragLastLocation = value.location
                        return
                    }
                    store.state.center = panCenter(center: store.state.center,
                                                   scale: store.state.scale,
                                                   viewHeight: Double(viewSize.height),
                                                   dxPx: Double(value.location.x - last.x),
                                                   dyPx: Double(value.location.y - last.y))
                    dragLastLocation = value.location
                }
                .onEnded { _ in
                    dragLastLocation = nil
                },
            MagnifyGesture()
                .onChanged { value in
                    let pinch: PinchState
                    if let existing = pinchState {
                        pinch = existing
                    } else {
                        let aspect = max(Double(viewSize.width) / max(Double(viewSize.height), 1), 1e-9)
                        // SwiftUI UnitPoint is y-down; helpers expect y-up — flip here.
                        let unit = SIMD2<Double>(Double(value.startAnchor.x),
                                                 1.0 - Double(value.startAnchor.y))
                        pinch = PinchState(startCenter: store.state.center,
                                           startScale: store.state.scale,
                                           anchorNDC: unitToNDC(unit, aspect: aspect))
                        pinchState = pinch
                    }
                    let mag = max(Double(value.magnification), 1e-9)
                    let newScale = max(1e-15, pinch.startScale / mag)
                    store.state.scale = newScale
                    store.state.center = anchoredZoomCenter(center: pinch.startCenter,
                                                            scale: pinch.startScale,
                                                            anchorNDC: pinch.anchorNDC,
                                                            newScale: newScale)
                }
                .onEnded { _ in
                    pinchState = nil
                    // Force the next drag tick to rebase: DragGesture.value.location
                    // tracks the centroid of active touches, so lifting one finger
                    // creates a discontinuity (centroid → single-finger position).
                    // Nilling here makes the next drag.onChanged consume that jump
                    // as a zero-delta rebase instead of a pan.
                    dragLastLocation = nil
                }
        )
    }

    // MARK: - macOS HUD

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
                .frame(minWidth: 140, idealWidth: 200)
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

    // MARK: - iOS peek + sheet

    #if os(iOS)
    private var iOSPeek: some View {
        HStack(spacing: 6) {
            Button {
                showingSheet = true
            } label: {
                HStack(spacing: 8) {
                    Text(store.state.type.label)
                        .font(.subheadline.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(store.state.maxIterations)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 18)
                .opacity(0.4)

            Button {
                if store.isReplaying { store.stopReplay() } else { store.replay() }
            } label: {
                Image(systemName: store.isReplaying ? "stop.fill" : "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.journal.count < 2)
            .padding(.trailing, 4)
        }
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    private var iOSControlsSheet: some View {
        NavigationStack {
            Form {
                Section("Fractal") {
                    Picker("Type", selection: Binding(
                        get: { store.state.type },
                        set: { store.switchType(to: $0) }
                    )) {
                        ForEach(FractalType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Iterations")
                            Spacer()
                            Text("\(store.state.maxIterations)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(store.state.maxIterations) },
                            set: { store.state.maxIterations = UInt32($0) }
                        ), in: 32...4096)
                    }
                }

                Section("Appearance") {
                    Picker("Palette", selection: $store.state.palette) {
                        ForEach(Palette.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    Toggle("Smooth", isOn: $store.state.smooth)
                    if store.state.type.supportsPerturbation {
                        Toggle("Perturbation", isOn: $store.state.usePerturbation)
                    }
                }

                iOSTypeSpecificSection

                Section {
                    Button {
                        if store.isReplaying {
                            store.stopReplay()
                        } else {
                            store.replay()
                            showingSheet = false
                        }
                    } label: {
                        Label(store.isReplaying ? "Stop Replay" : "Replay",
                              systemImage: store.isReplaying ? "stop.fill" : "play.fill")
                    }
                    .disabled(store.journal.count < 2)

                    Button {
                        store.reset()
                    } label: {
                        Label("Reset View", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        store.clearJournal()
                    } label: {
                        Label("Clear Journal", systemImage: "trash")
                    }
                    .disabled(store.journal.isEmpty || store.isReplaying)
                }
            }
            .navigationTitle("Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSheet = false }
                }
            }
        }
    }

    @ViewBuilder
    private var iOSTypeSpecificSection: some View {
        switch store.state.type {
        case .julia:
            Section("Julia c") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Real")
                        Spacer()
                        Text(String(format: "%.4f", store.state.juliaCx))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.state.juliaCx, in: -1.5...1.5)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Imaginary")
                        Spacer()
                        Text(String(format: "%.4f", store.state.juliaCy))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.state.juliaCy, in: -1.5...1.5)
                }
                ScrollView(.horizontal, showsIndicators: false) {
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
        case .multibrot:
            Section {
                Stepper(value: Binding(
                    get: { Int(store.state.multibrotExponent) },
                    set: { store.state.multibrotExponent = UInt32(max(2, min(8, $0))) }
                ), in: 2...8) {
                    HStack {
                        Text("Exponent")
                        Spacer()
                        Text("n = \(store.state.multibrotExponent)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .newton:
            Section {
                Picker("Polynomial", selection: Binding(
                    get: { Int(store.state.newtonFlavor) },
                    set: { store.state.newtonFlavor = UInt32($0) }
                )) {
                    Text("z³ − 1").tag(0)
                    Text("z³ − 2z + 2").tag(1)
                    Text("z⁸ + 15z⁴ − 16").tag(2)
                }
            }
        case .mandelbrot:
            EmptyView()
        }
    }
    #endif
}
