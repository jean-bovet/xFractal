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
        XCTAssertEqual(slugs.count, 26)
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
        try XCTSkipUnless(medium.form == .sheet, "the controls are a \(medium.form), not a sheet: no detents")
        XCTAssertEqual(medium.sheetController?.selectedDetentIdentifier, .medium)
        let mediumHeight = medium.sheetFrame!.intersection(medium.window.bounds).height
        XCTAssertGreaterThan(mediumHeight, medium.window.bounds.height * 0.40)
        XCTAssertLessThan(mediumHeight, medium.window.bounds.height * 0.62)

        let large = try await GalleryHarness.mount(GalleryScenarios.scenario("controls-mandelbrot-large-first-launch"), .light)
        defer { large.teardown() }
        XCTAssertEqual(large.sheetController?.selectedDetentIdentifier, .large)
        XCTAssertGreaterThan(large.sheetFrame!.intersection(large.window.bounds).height, large.window.bounds.height * 0.85)
    }

    func testDuoInnerTraits() async throws {
        let sizes: [(String, CGSize)] = [("duo-inner-landscape-board-julia", CGSize(width: 951, height: 669)),
                                         ("duo-inner-portrait-board-mandelbrot-deep-zoom", CGSize(width: 669, height: 951))]
        for (slug, size) in sizes {
            let board = try await GalleryHarness.mount(GalleryScenarios.scenario(slug), .light)
            defer { board.teardown() }
            XCTAssertEqual(board.host.traitCollection.horizontalSizeClass, .regular, slug)
            XCTAssertEqual(board.sizeClasses.outer, .regular, slug)
            XCTAssertEqual(board.window.bounds.size, size, slug)
        }
        for slug in ["duo-inner-landscape-controls-julia", "duo-inner-portrait-controls-mandelbrot"] {
            let controls = try await GalleryHarness.mount(GalleryScenarios.scenario(slug), .light)
            defer { controls.teardown() }
            XCTAssertEqual(controls.host.traitCollection.horizontalSizeClass, .regular, slug)
            XCTAssertEqual(controls.form, .column, slug)
            XCTAssertEqual(controls.sizeClasses.outer, .regular, slug)
            // The column is 280 pt wide: its own content sees a compact width.
            XCTAssertEqual(controls.sizeClasses.sheet, .compact, slug)
        }
    }

    /// The compact inspector is the production sheet: the same three detents, the opening one 260 pt high and the board
    /// interactive under it.
    func testCompactSheetKeepsOpeningDetentAndBackgroundInteraction() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("controls-mandelbrot-opening-detent"), .light)
        defer { mount.teardown() }
        try XCTSkipUnless(mount.form == .sheet, "the controls are a \(mount.form), not a sheet")
        let controller = try XCTUnwrap(mount.sheetController)
        let ids = controller.detents.map(\.identifier)
        XCTAssertEqual(ids.count, 3, "\(ids.map(\.rawValue))")
        XCTAssertTrue(ids.contains(.medium) && ids.contains(.large), "\(ids.map(\.rawValue))")
        let custom = ids.filter { $0 != .medium && $0 != .large }
        XCTAssertEqual(custom.map(\.rawValue), ["Height:260.0"], "the custom opening detent")
        let height = mount.sheetFrame!.intersection(mount.window.bounds).height
        XCTAssertGreaterThanOrEqual(height, 260, "the opening height")
        XCTAssertLessThanOrEqual(height, 260 + mount.window.safeAreaInsets.bottom + 2, "the opening height")
        XCTAssertEqual(controller.largestUndimmedDetentIdentifier, custom.first, "the board stays interactive at the opening detent")
    }

    func testColumnPresentsTheFormBesideTheBoard() async throws {
        var slugs = ["duo-inner-landscape-controls-julia"]
        // On the iPad pass `.phone` is a regular window too: the phone Controls scenarios are columns there.
        if UIScreen.main.traitCollection.horizontalSizeClass == .regular { slugs.append("controls-julia-large") }
        for slug in slugs {
            let mount = try await GalleryHarness.mount(GalleryScenarios.scenario(slug), .light)
            defer { mount.teardown() }
            XCTAssertEqual(mount.form, .column, slug)
            XCTAssertNil(mount.presented, "\(slug): no sheet")
            let list = try XCTUnwrap(mount.columnList, slug)
            let column = try XCTUnwrap(mount.columnFrame, slug)
            let listFrame = list.convert(list.bounds, to: mount.window)
            XCTAssertEqual(mount.trailingEdge(of: listFrame), mount.trailingWindowEdge, accuracy: 1, "\(slug): at the trailing edge")
            // The list lies beside the board, not under it: judged against the board's frame, which SwiftUI sets by its
            // own padding, not against the column strip (that one is derived from the list).
            let boardFrame = mount.mtk.convert(mount.mtk.bounds, to: mount.window)
            if mount.rightToLeft {
                XCTAssertLessThanOrEqual(listFrame.maxX, boardFrame.minX + 1, "\(slug): the list ends where the board starts")
            } else {
                XCTAssertGreaterThanOrEqual(listFrame.minX, boardFrame.maxX - 1, "\(slug): the list starts where the board ends")
            }
            let board = mount.mtk.convert(mount.mtk.bounds, to: mount.window)
            XCTAssertEqual(board.width, mount.window.bounds.width - column.width, accuracy: 1, "\(slug): the board is narrower by the column")
            XCTAssertLessThan(board.width, mount.window.bounds.width, slug)
            XCTAssertEqual(mount.sizeClasses.sheet, .compact, "\(slug): the column's own content is compact")
        }
    }

    /// The reference render has the MTKView's size, not the window's: beside a column the comparison must still hold.
    func testReferenceComparisonBesideAColumn() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("duo-inner-landscape-controls-julia"), .light)
        defer { mount.teardown() }
        XCTAssertEqual(mount.form, .column)
        _ = try await mount.drawFrame()
        let image = mount.capture()
        let region = try XCTUnwrap(mount.fractalRegion())
        // The region lies beside the column, on the board's side.
        let strip = try XCTUnwrap(mount.columnFrame)
        if mount.rightToLeft {
            XCTAssertGreaterThanOrEqual(region.minX, strip.maxX)
        } else {
            XCTAssertLessThanOrEqual(region.maxX, strip.minX)
        }
        let own = try mount.validate(image, expected: mount.fixture.expectedState, region: region)
        XCTAssertTrue(own.passed, "own reference \(own.mode) \(own.value): \(own.reason ?? "")")
        let other = try mount.validate(image, expected: .defaultState, region: region)
        XCTAssertFalse(other.passed, "another fractal must not match (\(other.mode) \(other.value))")
    }

    /// A compact sheet becomes a column when the window turns wide and regular, and a sheet again, with the controls open
    /// and the store untouched. Resizing the window and overriding its size class stand in for a fold.
    func testControlsSurviveSizeClassChange() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("controls-mandelbrot-opening-detent"), .light)
        defer { mount.teardown() }
        try XCTSkipUnless(mount.form == .sheet, "the controls are a \(mount.form) on this screen: no compact start")
        XCTAssertNotNil(mount.presented)
        let compactFrame = mount.window.frame
        mount.store.state.maxIterations = 777
        let edited = mount.store.state

        mount.window.frame = CGRect(x: 0, y: 0, width: 951, height: 669)
        mount.host.traitOverrides.horizontalSizeClass = .regular
        mount.window.traitOverrides.horizontalSizeClass = .regular
        try await mount.settlePresentation()
        XCTAssertEqual(mount.form, .column)
        XCTAssertNil(mount.presented, "no sheet beside a column")
        let list = try XCTUnwrap(mount.columnList)
        let column = try XCTUnwrap(mount.columnFrame)
        XCTAssertEqual(mount.trailingEdge(of: list.convert(list.bounds, to: mount.window)), mount.trailingWindowEdge, accuracy: 1)
        XCTAssertLessThan(mount.mtk.convert(mount.mtk.bounds, to: mount.window).width, mount.window.bounds.width)
        XCTAssertGreaterThan(column.width, 0)
        XCTAssertEqual(mount.store.state, edited, "the controls kept the store")
        try await assertBoardShows(edited, in: mount, "beside the column")

        mount.window.frame = compactFrame
        mount.host.traitOverrides.horizontalSizeClass = .compact
        mount.window.traitOverrides.horizontalSizeClass = .compact
        try await mount.settlePresentation()
        XCTAssertEqual(mount.form, .sheet)
        XCTAssertNotNil(mount.presented, "the controls are still open: a sheet again")
        // A sheet floats with a small margin on each side of the window.
        XCTAssertGreaterThan(mount.sheetFrame?.width ?? 0, mount.window.bounds.width - 24)
        XCTAssertEqual(mount.store.state, edited)
        try await assertBoardShows(edited, in: mount, "under the sheet again")
        // The current binding still dismisses: closing the sheet closes the controls (no presentation comes back).
        let dismissed = try XCTUnwrap(mount.presented)
        dismissed.dismiss(animated: false)
        try await mount.waitUntil(5, "the sheet dismissed") { mount.presented == nil }
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(mount.presented, "a dismissed sheet stays dismissed")
        XCTAssertNil(mount.columnList)
    }

    // MARK: the peek capsule and the fold

    /// The bottom 140 pt of the window (where the peek capsule sits) as RGBA bytes.
    private func peekBand(_ mount: GalleryMount) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let image = try XCTUnwrap(mount.capture().cgImage)
        let scale = mount.fixture.size.scale
        let band = CGRect(x: 0, y: CGFloat(image.height) - 140 * scale, width: CGFloat(image.width), height: 140 * scale).integral
        let crop = try XCTUnwrap(image.cropping(to: band))
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let ctx = CGContext(data: &bytes, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        return (bytes, crop.width, crop.height)
    }

    private func settledBand(_ mount: GalleryMount) async throws -> (bytes: [UInt8], width: Int, height: Int) {
        let band = try await mount.settled("the peek band") { try peekBand(mount).bytes }
        return (band, try peekBand(mount).width, try peekBand(mount).height)
    }

    func testFoldedPeekIsStableAcrossLayoutPasses() async throws {
        let folded = try await GalleryHarness.mount(GalleryScenarios.scenario("duo-inner-landscape-board-folded-mandelbrot"), .light)
        defer { folded.teardown() }
        let first = try await settledBand(folded)
        folded.window.layoutIfNeeded()
        let second = try await settledBand(folded)
        XCTAssertEqual(first.bytes, second.bytes, "the capsule oscillates between layout passes")

        let open = try await GalleryHarness.mount(GalleryScenarios.scenario("duo-inner-landscape-board-mandelbrot-first-launch"), .light)
        defer { open.teardown() }
        let centred = try await settledBand(open)
        XCTAssertNotEqual(first.bytes, centred.bytes, "the capsule did not move off the fold")
    }

    func testFoldRegionChangeMovesAndRecentersTheCapsule() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("duo-inner-landscape-board-folded-mandelbrot"), .light)
        defer { mount.teardown() }
        let hinge = try XCTUnwrap(mount.fixture.foldRegion)
        let state = mount.store.state
        let a = try await settledBand(mount)
        mount.foldBox.regions = []
        let b = try await settledBand(mount)
        mount.foldBox.regions = [hinge]
        let c = try await settledBand(mount)
        XCTAssertEqual(a.bytes, c.bytes, "re-shifting is deterministic")
        XCTAssertNotEqual(a.bytes, b.bytes, "the capsule recentred")
        XCTAssertEqual(mount.store.state, state, "the store is untouched")
        // The columns where the shifted and the centred capsule differ: the centred one covers the window's centre, the
        // shifted one reaches past the fold's trailing edge (the capsules overlap, so the differing columns run together).
        let scale = Double(a.width) / Double(mount.window.bounds.width)
        var differing: [Int] = []
        for x in 0..<a.width {
            for y in 0..<a.height {
                let i = (y * a.width + x) * 4
                if a.bytes[i..<i + 4] != b.bytes[i..<i + 4] { differing.append(x); break }
            }
        }
        let first = try XCTUnwrap(differing.first), last = try XCTUnwrap(differing.last)
        if mount.rightToLeft {
            XCTAssertGreaterThanOrEqual(Double(last), Double(mount.window.bounds.width) / 2 * scale, "the centred capsule")
            XCTAssertLessThan(Double(first), (hinge.minX - 60) * scale, "the shifted capsule lies trailing of the fold")
        } else {
            XCTAssertLessThanOrEqual(Double(first), Double(mount.window.bounds.width) / 2 * scale, "the centred capsule")
            XCTAssertGreaterThan(Double(last), (hinge.maxX + 60) * scale, "the shifted capsule lies trailing of the fold")
        }
    }

    /// The displayed board is wired to the same store the controls bind: an edit made after a transition reaches the renderer
    /// (store -> `FractalView` binding), and what the store held before is what the renderer shows.
    private func assertBoardShows(_ state: ViewState, in mount: GalleryMount, _ when: String) async throws {
        try await mount.waitUntil(3, "the renderer shows the store's state \(when)") { mount.renderer.state == state }
        var next = state
        next.maxIterations += 1
        mount.store.state = next
        try await mount.waitUntil(3, "an edit reaches the renderer \(when)") { mount.renderer.state == next }
        mount.store.state = state
        try await mount.waitUntil(3, "the edit is undone \(when)") { mount.renderer.state == state }
    }

    /// A device inset on the trailing side (the Duo's status bar side): right, or left under right to left, so the
    /// production `safeAreaInsets.trailing` path is the one exercised in both directions.
    private func trailingInset(_ points: CGFloat, in mount: GalleryMount) -> UIEdgeInsets {
        mount.rightToLeft ? UIEdgeInsets(top: 0, left: points, bottom: 0, right: 0) : UIEdgeInsets(top: 0, left: 0, bottom: 0, right: points)
    }

    /// Closed controls at regular width leave the board full-bleed, also where the trailing edge has a device inset (the Duo
    /// inner display's status bar side); opened, the board stops at the column.
    func testClosedBoardReachesTheTrailingEdgeDespiteADeviceInset() async throws {
        let board = try await GalleryHarness.mount(GalleryScenarios.scenario("duo-inner-landscape-board-julia"), .light)
        defer { board.teardown() }
        board.host.additionalSafeAreaInsets = trailingInset(84, in: board)
        board.window.layoutIfNeeded()
        try await board.waitUntil(3, "the board spans the window") {
            board.window.layoutIfNeeded()
            return abs(board.trailingEdge(of: board.mtk.convert(board.mtk.bounds, to: board.window)) - board.trailingWindowEdge) < 1
        }
        XCTAssertNil(board.columnFrame)
        _ = try await board.drawFrame()
        let region = try XCTUnwrap(board.fractalRegion())
        let check = try board.validate(board.capture(), expected: board.fixture.expectedState, region: region)
        XCTAssertTrue(check.passed, check.reason ?? "")
    }

    /// A column laid over the board is recognised as such with a device inset on the trailing edge too (the board then ends
    /// at that inset, still under the column), and the comparison samples the same area of capture and reference.
    func testOverlayColumnIsRecognisedDespiteADeviceInset() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("duo-inner-portrait-controls-mandelbrot"), .light)
        defer { mount.teardown() }
        mount.host.additionalSafeAreaInsets = trailingInset(84, in: mount)
        try await mount.settlePresentation()
        XCTAssertTrue(mount.columnOverlaysBoard, "the board reaches under the column")
        try await mount.settleScrim()
        _ = try await mount.drawFrame()
        let region = try XCTUnwrap(mount.fractalRegion())
        let check = try mount.validate(mount.capture(), expected: mount.fixture.expectedState, region: region)
        XCTAssertTrue(check.passed, check.reason ?? "")
    }

    func testDuoCaptureScaleIsThree() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("duo-inner-landscape-board-mandelbrot-first-launch"), .light)
        defer { mount.teardown() }
        _ = try await mount.drawFrame()
        let image = try XCTUnwrap(mount.capture().cgImage)
        XCTAssertEqual(image.width, 2853)
        XCTAssertEqual(image.height, 2007)
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
        format.scale = mount.fixture.size.scale
        let blank = UIGraphicsImageRenderer(size: mount.window.bounds.size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: mount.window.bounds.size))
        }
        let uniform = try mount.validate(blank, expected: mount.fixture.expectedState, region: region)
        XCTAssertFalse(uniform.passed, "a uniform region must fail (\(uniform.mode) \(uniform.value))")
    }

    /// The fractal is never mirrored under right to left, and a mirrored one would fail the reference comparison: the
    /// capture of an asymmetric Julia set passes, the same capture flipped horizontally does not.
    func testMirroredCaptureFailsTheReference() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("board-julia-spiral-chromatic"), .light)
        defer { mount.teardown() }
        _ = try await mount.drawFrame()
        let image = mount.capture()
        let region = try XCTUnwrap(mount.fractalRegion())
        let own = try mount.validate(image, expected: mount.fixture.expectedState, region: region)
        XCTAssertTrue(own.passed, "own reference \(own.mode) \(own.value): \(own.reason ?? "")")
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let flipped = UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: image.size.width, y: 0)
            ctx.cgContext.scaleBy(x: -1, y: 1)
            image.draw(at: .zero)
        }
        let mirrored = try mount.validate(flipped, expected: mount.fixture.expectedState, region: region)
        XCTAssertFalse(mirrored.passed, "a mirrored fractal must not match (\(mirrored.mode) \(mirrored.value))")
        XCTAssertEqual(mirrored.mode, "corr")
        XCTAssertLessThan(mirrored.value, 0.95)
    }

    /// A capture can lag the explicit draw (observed once in a run: the frame showing was still the previous one), so the
    /// frame evidence is never trusted alone: whichever frame is visible is validated against the expected state.
    func testStaleFrameIsRejected() async throws {
        let mount = try await GalleryHarness.mount(GalleryScenarios.scenario("board-mandelbrot-first-launch"), .light)
        defer { mount.teardown() }
        let expected = ViewState.defaultState
        let julia = GalleryFixtures.julia
        let region = try XCTUnwrap(mount.fractalRegion())
        // Present a frame of another state (Julia).
        // (Through the store: a SwiftUI update copies the store's state into the renderer and resumes the view.)
        mount.store.state = julia
        try await mount.waitUntil(2, "the Julia state reaches the renderer") { mount.renderer.state == julia }
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
        mount.store.state = expected
        try await mount.waitUntil(2, "the Mandelbrot state reaches the renderer") { mount.renderer.state == expected }
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
            // Both forms: a sheet's band is the system's dimming, a column's is zero (`scrimBand`).
            let expected = mount.fixture.expectedState
            let region = try XCTUnwrap(mount.fractalRegion())
            let band = mount.scrimBand(appearance)
            func check(_ scrim: Double) throws -> ContentCheck {
                try mount.validate(try mount.gainedReference(of: expected, gain: 1 - scrim), expected: expected, region: region)
            }
            let inside = try check((band.lowerBound + band.upperBound) / 2)
            XCTAssertTrue(inside.passed, "\(appearance) a gain inside the band passes (\(inside.reason ?? ""))")
            let lower = try check(band.lowerBound - 0.1)
            // (A brightening past white clips: a column's band sits at 0, so only a dimming is exactly a pure gain.)
            if band.lowerBound - 0.1 >= 0 { XCTAssertLessThan(lower.rgbError, 0.01, "\(appearance): a pure gain leaves no residual") }
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
            try XCTSkipUnless(mount.form == .sheet, "the controls are a \(mount.form), not a sheet: no scrim")
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
