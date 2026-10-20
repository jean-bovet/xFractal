import XCTest
import SwiftUI
import MetalKit
@testable import xFractal

/// Plain tests of the gallery harness: never skipped, run with every gallery run.
@MainActor
final class GalleryScenarioTests: XCTestCase {
    // MARK: scenario list

    func testSlugsAreUnique() {
        let slugs = GalleryScenarios.every.map(\.slug)
        XCTAssertEqual(Set(slugs).count, slugs.count)
        XCTAssertEqual(slugs.count, 19)
        XCTAssertFalse(slugs.contains(""))
    }

    func testArtworkHasAnAppStoreCreativeAssetSize() {
        let names = GalleryFixtures.artwork.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.isEmpty)
        for artwork in GalleryFixtures.artwork {
            XCTAssertEqual(artwork.name, artwork.name.lowercased().replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression))
            // App Store creative-asset sizes: the product page header (3840 x 1646), the largest search results asset
            // (3840 x 2560) and the universal asset that serves both (5244 x 2950).
            let sizes = [[3840, 1646], [3840, 2560], [5244, 2950]]
            XCTAssertTrue(sizes.contains([artwork.width, artwork.height]), "\(artwork.name): \(artwork.width) x \(artwork.height)")
        }
    }

    func testBuilderIsFreshPerCall() {
        for scenario in GalleryScenarios.every {
            let a = scenario.build(.light), b = scenario.build(.light), c = scenario.build(.dark)
            XCTAssertFalse(a.store === b.store, scenario.slug)
            XCTAssertFalse(a.store === c.store, scenario.slug)
            XCTAssertNotEqual(a.suiteName, c.suiteName, scenario.slug)
            for built in [a, b, c] { built.defaults.removePersistentDomain(forName: built.suiteName) }
        }
    }

    func testSeededStateReadsBackThroughLoad() {
        for scenario in GalleryScenarios.every {
            let built = scenario.build(.light)
            XCTAssertEqual(built.store.state, scenario.fixture.state ?? .defaultState, scenario.slug)
            XCTAssertEqual(built.store.journal, scenario.fixture.journal, scenario.slug)
            XCTAssertFalse(built.store.isReplaying, scenario.slug)
            built.defaults.removePersistentDomain(forName: built.suiteName)
        }
    }

    // MARK: the lazy seam, hosted

    private final class Driver: ObservableObject {
        @Published var tick = 0
        @Published var identity = 0
    }

    private struct Wrapper: View {
        @ObservedObject var driver: Driver
        let make: () -> StateStore
        var body: some View {
            ContentView(store: make())
                .id(driver.identity)
                .overlay(Text("\(driver.tick)").hidden())
        }
    }

    func testHostedStoreIsBuiltOncePerIdentity() async throws {
        var built: [StateStore] = []
        let driver = Driver()
        let make = {
            let store = StateStore(defaults: UserDefaults(suiteName: "hosted-\(UUID().uuidString)")!)
            built.append(store)
            return store
        }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        window.rootViewController = UIHostingController(rootView: Wrapper(driver: driver, make: make))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<3 {
            driver.tick += 1
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(built.count, 1, "re-renders must not rebuild the store")
        driver.identity += 1
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(built.count, 2, "a new identity builds one more")
    }

    // MARK: scene phase

    func testActiveScenePhaseKeepsMetalRunning() async throws {
        let board = try await GalleryHarness.mount(GalleryScenarios.scenario("board-mandelbrot-first-launch"), .light)
        defer { board.teardown() }
        XCTAssertFalse(board.mtk.isPaused, "paused after the first render")
        for _ in 0..<10 {
            board.store.state.scale *= 0.99
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertFalse(board.mtk.isPaused, "paused after a store update")
        }
        let replay = try await GalleryHarness.mount(GalleryScenarios.scenario("board-replaying"), .light)
        defer { replay.teardown() }
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertFalse(replay.mtk.isPaused, "paused during the replay")
        }
        XCTAssertTrue(replay.store.isReplaying)
    }

    // MARK: readiness

    func testReadinessObservesOurFrame() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("board-julia"), .light)
        defer { mount.teardown() }
        let evidence = try await mount.drawFrame()
        XCTAssertEqual(evidence.submits, 1)
        XCTAssertEqual(evidence.completedStatus, .completed)
        XCTAssertNil(evidence.completedError)
        XCTAssertGreaterThan(evidence.scheduledTime, 0)
        XCTAssertEqual(evidence.state, mount.fixture.expectedState)

        let started = Date()
        do {
            _ = try await mount.drawFrame(arm: false)
            XCTFail("an unarmed observer must fail")
        } catch {
            XCTAssertTrue("\(error)".contains("no frame submitted"), "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testDetentSelectionSettles() async throws {
        let medium = try await GalleryHarness.mount(GalleryScenarios.scenario("controls-mandelbrot-medium"), .light)
        defer { medium.teardown() }
        XCTAssertEqual(medium.sheetController?.selectedDetentIdentifier, .medium)
        let mediumHeight = medium.sheetFrame!.intersection(medium.window.bounds).height
        XCTAssertGreaterThan(mediumHeight, medium.window.bounds.height * 0.40)
        XCTAssertLessThan(mediumHeight, medium.window.bounds.height * 0.62)

        let large = try await GalleryHarness.mount(GalleryScenarios.scenario("controls-mandelbrot-large-first-launch"), .light)
        defer { large.teardown() }
        XCTAssertEqual(large.sheetController?.selectedDetentIdentifier, .large)
        XCTAssertGreaterThan(large.sheetFrame!.intersection(large.window.bounds).height, large.window.bounds.height * 0.85)
    }

    func testRegularWidthTraits() async throws {
        let board = try await GalleryHarness.mount(GalleryScenarios.scenario("regular-width-board-julia"), .light)
        defer { board.teardown() }
        XCTAssertEqual(board.host.traitCollection.horizontalSizeClass, .regular)
        XCTAssertEqual(board.sizeClasses.outer, .regular)
        XCTAssertEqual(board.window.bounds.size, CGSize(width: 834, height: 1210))

        let sheet = try await GalleryHarness.mount(GalleryScenarios.scenario("regular-width-controls-mandelbrot"), .light)
        defer { sheet.teardown() }
        XCTAssertEqual(sheet.host.traitCollection.horizontalSizeClass, .regular)
        XCTAssertEqual(sheet.presented?.traitCollection.horizontalSizeClass, .regular)
        XCTAssertEqual(sheet.sizeClasses.outer, .regular)
        XCTAssertEqual(sheet.sizeClasses.sheet, .regular)
    }

    // MARK: content validation

    func testContentMatchesReference() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("board-julia"), .light)
        defer { mount.teardown() }
        _ = try await mount.drawFrame()
        let image = mount.capture()
        let region = try XCTUnwrap(mount.fractalRegion())
        let own = try mount.validate(image, expected: mount.fixture.expectedState, region: region)
        XCTAssertTrue(own.passed, "own reference \(own.mode) \(own.value)")
        let other = try mount.validate(image, expected: .defaultState, region: region)
        XCTAssertFalse(other.passed, "another fractal must not match (\(other.mode) \(other.value))")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let blank = UIGraphicsImageRenderer(size: mount.window.bounds.size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: mount.window.bounds.size))
        }
        let uniform = try mount.validate(blank, expected: mount.fixture.expectedState, region: region)
        XCTAssertFalse(uniform.passed, "a uniform region must fail (\(uniform.mode) \(uniform.value))")
    }

    /// A capture can lag the explicit draw (observed once in a run: the frame showing was still the previous one), so the
    /// frame evidence is never trusted alone: whichever frame is visible is validated against the expected state.
    func testStaleFrameIsRejected() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("board-mandelbrot-first-launch"), .light)
        defer { mount.teardown() }
        let expected = ViewState.defaultState
        let julia = GalleryFixtures.julia
        let region = try XCTUnwrap(mount.fractalRegion())
        // Present a frame of another state (Julia) and stop the display link, so nothing redraws it.
        mount.mtk.isPaused = true
        mount.renderer.state = julia
        let stale = try await mount.drawFrame()
        XCTAssertEqual(stale.state, julia)
        // Draw and poll the capture (bounded, redrawing between rounds like the render does) until the Julia frame shows: a
        // capture can lag the draw, more so on a loaded machine. Then validate against Mandelbrot.
        var image = mount.capture()
        var rounds = 0
        while try rounds < 3 && !mount.validate(image, expected: julia, region: region).passed {
            _ = try await mount.drawFrame()
            var polls = 0
            repeat {
                try await Task.sleep(nanoseconds: 100_000_000)
                image = mount.capture()
                polls += 1
            } while try polls < 15 && !mount.validate(image, expected: julia, region: region).passed
            rounds += 1
        }
        let jr = try mount.validate(image, expected: julia, region: region)
        let mr = try mount.validate(image, expected: expected, region: region)
        XCTAssertTrue(jr.passed, "the Julia frame becomes visible: vs julia \(jr.reason ?? "ok"); vs mandelbrot \(mr.reason ?? "ok")")
        XCTAssertFalse(mr.passed, "a stale frame must fail")
        mount.renderer.state = expected
        let fresh = try await mount.drawFrame()
        XCTAssertEqual(fresh.state, expected)
        var after = mount.capture()
        rounds = 0
        while try rounds < 3 && !mount.validate(after, expected: expected, region: region).passed {
            _ = try await mount.drawFrame()
            var polls = 0
            repeat {
                try await Task.sleep(nanoseconds: 100_000_000)
                after = mount.capture()
                polls += 1
            } while try polls < 15 && !mount.validate(after, expected: expected, region: region).passed
            rounds += 1
        }
        XCTAssertTrue(try mount.validate(after, expected: expected, region: region).passed)
    }

    private func tinted(_ image: UIImage, _ color: UIColor, alpha: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            image.draw(at: .zero)
            color.withAlphaComponent(alpha).setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size), blendMode: .normal)
        }
    }

    func testBrightnessAndColourErrorsAreRejected() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("board-mandelbrot-first-launch"), .light)
        defer { mount.teardown() }
        _ = try await mount.drawFrame()
        let image = mount.capture()
        let region = try XCTUnwrap(mount.fractalRegion())
        let expected = mount.fixture.expectedState
        let good = try mount.validate(image, expected: expected, region: region)
        XCTAssertTrue(good.passed, good.reason ?? "")
        // A brightness shift keeps the correlation high but is not a black overlay.
        let brighter = try mount.validate(tinted(image, .white, alpha: 0.15), expected: expected, region: region)
        XCTAssertFalse(brighter.passed, "a brightness shift must fail (\(brighter.reason ?? ""))")
        // A colour cast keeps the luminance pattern.
        let cast = try mount.validate(tinted(image, UIColor(red: 1, green: 0, blue: 0, alpha: 1), alpha: 0.2), expected: expected, region: region)
        XCTAssertFalse(cast.passed, "a colour error must fail (\(cast.reason ?? ""))")
        // Dimming beyond what the scenario allows (none for a plain board) fails too.
        let dimmed = try mount.validate(tinted(image, .black, alpha: 0.3), expected: expected, region: region)
        XCTAssertFalse(dimmed.passed, "an unexpected scrim must fail (\(dimmed.reason ?? ""))")
        // ... and is fine where that scrim is allowed (a band around it).
        let allowed = try mount.validate(tinted(image, .black, alpha: 0.3), expected: expected, region: region, scrimBand: 0.25...0.35)
        XCTAssertTrue(allowed.passed, "an allowed scrim passes (\(allowed.reason ?? ""))")
    }

    func testScrimSettlingNeedsAFlatWindow() {
        XCTAssertFalse(ScrimSettling.isSettled([]))
        XCTAssertFalse(ScrimSettling.isSettled([0.2, 0.2]), "too few samples")
        XCTAssertTrue(ScrimSettling.isSettled([0.2, 0.2, 0.2]))
        XCTAssertTrue(ScrimSettling.isSettled([0.1, 0.19, 0.2005, 0.2, 0.1995]), "only the last window counts")
        // A steady drift has small adjacent steps (0.004) but a range over the window past epsilon.
        XCTAssertFalse(ScrimSettling.isSettled([0.188, 0.192, 0.196, 0.200]))
        XCTAssertFalse(ScrimSettling.isSettled([0.2, 0.2, 0.2, 0.208]), "a late step")
        XCTAssertTrue(ScrimSettling.isSettled([0.2, 0.2, 0.2, 0.2, 0.2]))
    }

    /// A pure gain (the reference times a constant, no offset) has no residual, so only the scrim band can reject it. Below
    /// the lower limit it is a brightening relative to the sheet's scrim; above the upper one, extra dimming.
    func testPureGainOutsideTheScrimBandIsRejected() async throws {
        for appearance in [GalleryAppearance.light, .dark] {
            let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("controls-mandelbrot-medium"), appearance)
            defer { mount.teardown() }
            let expected = mount.fixture.expectedState
            let region = try XCTUnwrap(mount.fractalRegion())
            let band = mount.scrimBand(appearance)
            func check(_ scrim: Double) throws -> ContentCheck {
                try mount.validate(try mount.gainedReference(of: expected, gain: 1 - scrim), expected: expected, region: region)
            }
            let inside = try check((band.lowerBound + band.upperBound) / 2)
            XCTAssertTrue(inside.passed, "\(appearance) a gain inside the band passes (\(inside.reason ?? ""))")
            let lower = try check(band.lowerBound - 0.1)
            XCTAssertLessThan(lower.rgbError, 0.01, "\(appearance): a pure gain leaves no residual")
            XCTAssertLessThan(lower.scrim, band.lowerBound)
            XCTAssertFalse(lower.passed, "\(appearance) a brightening below the band must fail (\(lower.reason ?? ""))")
            let upper = try check(band.upperBound + 0.1)
            XCTAssertLessThan(upper.rgbError, 0.01)
            XCTAssertFalse(upper.passed, "\(appearance) extra dimming above the band must fail (\(upper.reason ?? ""))")
        }
    }

    /// At the medium detent the sheet dims the board by a measured amount; extra dimming or a brightening on top of it must
    /// fail, although the scrim fit alone would absorb a uniform gain.
    func testMediumDetentScrimIsBounded() async throws {
        for appearance in [GalleryAppearance.light, .dark] {
            let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("controls-mandelbrot-medium"), appearance)
            defer { mount.teardown() }
            try await mount.settleScrim()
            _ = try await mount.drawFrame()
            let image = mount.capture()
            let region = try XCTUnwrap(mount.fractalRegion())
            let expected = mount.fixture.expectedState
            let good = try mount.validate(image, expected: expected, region: region)
            XCTAssertTrue(good.passed, "\(appearance): \(good.reason ?? "")")
            let darker = try mount.validate(tinted(image, .black, alpha: 0.3), expected: expected, region: region)
            XCTAssertFalse(darker.passed, "\(appearance): extra dimming must fail (\(darker.reason ?? ""))")
            XCTAssertLessThan(darker.rgbError, 0.01, "the fit absorbs the gain: only the band can reject it")
            let brighter = try mount.validate(tinted(image, .white, alpha: 0.1), expected: expected, region: region)
            XCTAssertFalse(brighter.passed, "\(appearance): a brightening must fail (\(brighter.reason ?? ""))")
        }
    }

    func testReplayScenarioIsStable() async throws {
        let scenario = GalleryScenarios.scenario("board-replaying")
        let mount = try await GalleryHarness.mount(scenario, .light)
        let a = GalleryFixtures.mandelbrotA
        let first = try await mount.drawFrame()
        XCTAssertEqual(first.state, a)
        try await Task.sleep(nanoseconds: 500_000_000)
        let second = try await mount.drawFrame()
        XCTAssertEqual(second.state, a)
        XCTAssertTrue(mount.store.isReplaying)
        mount.teardown()

        let before = GalleryHarness.clock
        defer { GalleryHarness.clock = before }
        var calls = 0
        GalleryHarness.clock = { calls += 1; return Date().addingTimeInterval(calls > 1 ? 11 : 0) }
        do {
            _ = try await GalleryHarness.render(scenario, .light)
            XCTFail("a render ending more than 10 s after replay() must fail")
        } catch {
            XCTAssertTrue("\(error)".contains("replay"), "\(error)")
        }
    }

    func testScrollFindsVerticalForm() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("controls-julia-large-bottom"), .light)
        defer { mount.teardown() }
        let form = try await mount.scrollSheetToEnd()
        XCTAssertLessThanOrEqual(form.contentSize.width, form.bounds.width + 0.5, "the vertical form, not the presets row")
        if form.contentSize.height > form.bounds.height {
            XCTAssertGreaterThan(form.contentOffset.y, 0, "a form taller than the sheet is scrolled to its end")
        }
        let rows = try mount.formRows(of: form)
        let visible = mount.sheetFrame!.intersection(mount.window.bounds)
        XCTAssertTrue(visible.contains(rows.presets.insetBy(dx: 1, dy: 1)), "the presets row")
        XCTAssertTrue(visible.contains(rows.last.insetBy(dx: 1, dy: 1)), "the last row")
        XCTAssertLessThan(rows.presets.maxY, rows.last.minY, "presets above the journal actions")
    }
}
