import SwiftUI
import simd

struct ContentView: View {
    @StateObject private var store: StateStore
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var widthGuard = WidthGuard()
    #endif
    @State private var viewSize: CGSize = .zero
    @State private var dragLastLocation: CGPoint? = nil
    @State private var pinchState: PinchState? = nil
    @State private var showingPanel: Bool
    @State private var showingSheet: Bool
    /// Preview-gallery hook, nil in the app: a view drawn (zero size) inside the controls sheet.
    private let sheetProbe: AnyView?
    /// Preview-gallery hook, nil in the app: stands in for the fold regions the system reports (container coordinates).
    private let foldRegionsOverride: [CGRect]?
    #if os(iOS)
    @State private var peekSize: CGSize = .zero
    @State private var foldInput = FoldInput(size: .zero, regions: [])
    @State private var trailingInset: CGFloat = 0

    /// What the fold avoidance reads from the layout: the container the peek capsule sits in and the active fold regions in
    /// that same space.
    private struct FoldInput: Equatable {
        var size: CGSize
        var regions: [CGRect]
    }
    #endif

    /// The store is an autoclosure so it is built once per view identity (StateObject's own autoclosure), not on
    /// every initialisation of this struct.
    /// `showingPanel` (the Mac's parameter panel) and `showingSheet` (the iOS controls) are the preview galleries' hooks.
    init(store: @autoclosure @escaping () -> StateStore = StateStore(), showingSheet: Bool = false,
         showingPanel: Bool = false, sheetProbe: AnyView? = nil, foldRegions: [CGRect]? = nil) {
        _store = StateObject(wrappedValue: store())
        _showingSheet = State(initialValue: showingSheet)
        _showingPanel = State(initialValue: showingPanel)
        self.sheetProbe = sheetProbe
        self.foldRegionsOverride = foldRegions
    }

    private struct PinchState {
        let startCenter: SIMD2<Double>
        let startScale: Double
        let anchorNDC: SIMD2<Double>
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            FractalView(state: $store.state, viewSize: $viewSize,
                        isActive: scenePhase != .background)
                .gesture(viewGestures)
                .allowsHitTesting(!store.isReplaying)
                .padding(.trailing, boardTrailingPadding)
                .animation(.default, value: boardTrailingPadding)
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
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { peekSize = $0 }
                .offset(x: peekOffset)
                .animation(.default, value: peekOffset)
                .padding(.bottom, 12)
            #endif
        }
        #if os(iOS)
        .background {
            GeometryReader { proxy in
                let input = FoldInput(size: proxy.size, regions: activeFoldRegions(proxy))
                Color.clear.onChange(of: input, initial: true) { foldInput = input }
                Color.clear.onChange(of: proxy.safeAreaInsets.trailing, initial: true) { _, inset in trailingInset = inset }
            }
        }
        #endif
        #if os(iOS)
        // One state, two presentations: the sheet while the width is compact, the inspector column once it is regular
        // (the Duo's inner display in every pose, the iPad). Each binding writes only while its own form is current: the
        // outgoing presentation's dismissal during a size-class change must not close the controls in the new form.
        .sheet(isPresented: sheetBinding) { controlsContent }
        .inspector(isPresented: inspectorBinding) { controlsContent }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.enterBackground() }
        }
    }

    #if os(iOS)
    /// The fold regions that are active now (none when the device is open or does not fold), in `proxy`'s space.
    private func activeFoldRegions(_ proxy: GeometryProxy) -> [CGRect] {
        if let foldRegionsOverride { return foldRegionsOverride }
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        }
        return []
    }

    /// How far the peek capsule moves off a fold. Its unshifted frame is derived from its size and the container (the
    /// ZStack bottom-centres it, 12 pt up), never measured through the offset it feeds, which would oscillate.
    private var peekOffset: CGFloat {
        let container = foldInput.size
        guard peekSize.width > 0, container.width > 0, !foldInput.regions.isEmpty else { return 0 }
        let capsule = CGRect(x: (container.width - peekSize.width) / 2,
                             y: container.height - 12 - peekSize.height,
                             width: peekSize.width, height: peekSize.height)
        return peekShift(capsule: capsule, clearing: foldInput.regions, in: container)
    }

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    /// The width the presentations' bindings consult. A reference, so that a binding SwiftUI kept from an earlier body
    /// still reads the current width when it is written during a size-class change (a captured copy of the view would
    /// hold the old one). Refreshed whenever a binding is built, i.e. on every body evaluation.
    private final class WidthGuard { var regular = false }

    private var sheetBinding: Binding<Bool> {
        let guardRef = widthGuard
        guardRef.regular = isRegularWidth
        return Binding(get: { showingSheet && !guardRef.regular }, set: { if !guardRef.regular { showingSheet = $0 } })
    }

    private var inspectorBinding: Binding<Bool> {
        let guardRef = widthGuard
        guardRef.regular = isRegularWidth
        return Binding(get: { showingSheet && guardRef.regular }, set: { if guardRef.regular { showingSheet = $0 } })
    }

    private var controlsContent: some View {
        iOSControlsSheet
            .background { if let sheetProbe { sheetProbe.frame(width: 0, height: 0) } }
            .presentationDetents([.height(260), .medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .height(260)))
    }
    #endif

    /// The board fills the screen. While the inspector column is shown (regular width, controls open) it stops at the column's
    /// edge: the column reports itself as a trailing safe-area inset, measured by the geometry reader below the board and
    /// applied as padding, so the board follows the column's slide with an animation of its own. (Respecting that edge
    /// through `ignoresSafeArea` instead snaps the board to its final width: the inset arrives in a layout pass of the
    /// inspector's, outside the animated state change.) Closed, the board is full-bleed again, whatever device inset
    /// (the Duo's status bar side) the trailing edge has.
    private var boardTrailingPadding: CGFloat {
        #if os(iOS)
        return isRegularWidth && showingSheet ? trailingInset : 0
        #else
        return 0
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

            Toggle(isOn: $showingPanel.animation(.easeInOut(duration: 0.15))) {
                Image(systemName: "slider.horizontal.3")
            }
            .toggleStyle(.button)

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
            Text(store.state.iterationsLabel)
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
                Text(verbatim: "c.re")
                    .font(.caption)
                    .frame(width: 36, alignment: .leading)
                Slider(value: $store.state.juliaCx, in: -1.5...1.5)
                Text(verbatim: juliaValueLabel(store.state.juliaCx))
                    .monospacedDigit()
                    .font(.caption)
                    .frame(width: 64, alignment: .trailing)
            }
            HStack {
                Text(verbatim: "c.im")
                    .font(.caption)
                    .frame(width: 36, alignment: .leading)
                Slider(value: $store.state.juliaCy, in: -1.5...1.5)
                Text(verbatim: juliaValueLabel(store.state.juliaCy))
                    .monospacedDigit()
                    .font(.caption)
                    .frame(width: 64, alignment: .trailing)
            }
            HStack(spacing: 8) {
                ForEach(JuliaPreset.all) { preset in
                    Button {
                        store.state.juliaCx = preset.c.x
                        store.state.juliaCy = preset.c.y
                    } label: {
                        Text(preset.name)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var multibrotControls: some View {
        HStack(spacing: 12) {
            Text("Exponent")
                .font(.caption)
            Stepper(value: Binding(
                get: { Int(store.state.multibrotExponent) },
                set: { store.state.multibrotExponent = UInt32(max(2, min(8, $0))) }
            ), in: 2...8) {
                Text(verbatim: "n = \(store.state.multibrotExponent)")
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
                Text(verbatim: "z³ − 1").tag(0)
                Text(verbatim: "z³ − 2z + 2").tag(1)
                Text(verbatim: "z⁸ + 15z⁴ − 16").tag(2)
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
                    Text(verbatim: "·")
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(store.state.maxIterations)")
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
                            Text(verbatim: "\(store.state.maxIterations)")
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
                        Text(verbatim: juliaValueLabel(store.state.juliaCx))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.state.juliaCx, in: -1.5...1.5)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Imaginary")
                        Spacer()
                        Text(verbatim: juliaValueLabel(store.state.juliaCy))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.state.juliaCy, in: -1.5...1.5)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(JuliaPreset.all) { preset in
                            Button {
                                store.state.juliaCx = preset.c.x
                                store.state.juliaCy = preset.c.y
                            } label: {
                                Text(preset.name)
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
                        Text(verbatim: "n = \(store.state.multibrotExponent)")
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
                    Text(verbatim: "z³ − 1").tag(0)
                    Text(verbatim: "z³ − 2z + 2").tag(1)
                    Text(verbatim: "z⁸ + 15z⁴ − 16").tag(2)
                }
            }
        case .mandelbrot:
            EmptyView()
        }
    }
    #endif
}
