import XCTest
@testable import xFractal

/// Renders every gallery scenario, light and dark, into XFRACTAL_SNAPSHOT_DIR (`<slug>.png`, `<slug>.dark.png`,
/// `manifest.json`). Skipped unless the variable is set, so normal runs and Xcode Cloud skip it.
/// XFRACTAL_SNAPSHOT_ONLY filters by comma-separated substrings of names or slugs.
@MainActor
final class SnapshotGalleryTests: XCTestCase {
    private struct ManifestEntry: Encodable {
        struct Size: Encodable { var w: Double; var h: Double }
        struct Regions: Encodable { var light: [GalleryRegion]; var dark: [GalleryRegion] }
        struct Diagnostics: Encodable {
            var referenceMode: String?
            var referenceLight: Double?
            var referenceDark: Double?
            var detent: String?
            var sheetHeight: Double?
        }
        var name: String
        var group: String
        var slug: String
        var size: Size
        var kinds: [String]
        var regions: Regions?
        var diagnostics: Diagnostics?
    }

    func testRenderGallery() async throws {
        guard let dir = ProcessInfo.processInfo.environment["XFRACTAL_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("XFRACTAL_SNAPSHOT_DIR not set")
        }
        let only = (ProcessInfo.processInfo.environment["XFRACTAL_SNAPSHOT_ONLY"] ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var entries: [ManifestEntry] = []
        var readyTimes: [Int] = []
        var redraws = 0
        var rendered = 0
        for scenario in GalleryScenarios.all {
            let selected = only.isEmpty || only.contains { scenario.name.lowercased().contains($0) || scenario.slug.contains($0) }
            var entry = ManifestEntry(name: scenario.name, group: scenario.group, slug: scenario.slug,
                                      size: .init(w: scenario.fixture.size.points.width, h: scenario.fixture.size.points.height),
                                      kinds: scenario.fixture.regions.map(\.rawValue), regions: nil, diagnostics: nil)
            if selected {
                var results: [GalleryAppearance: RenderResult] = [:]
                for appearance in [GalleryAppearance.light, .dark] {
                    do {
                        let r = try await GalleryHarness.render(scenario, appearance)
                        let file = appearance == .light ? "\(scenario.slug).png" : "\(scenario.slug).dark.png"
                        try r.png.write(to: URL(fileURLWithPath: dir + "/" + file))
                        results[appearance] = r
                        readyTimes.append(r.readyMs)
                        redraws += r.redraws
                        rendered += 1
                        print("gallery: \(scenario.slug) \(appearance.rawValue) ready \(r.readyMs) submits \(r.submits) redraws \(r.redraws) total \(r.totalMs)"
                              + (r.check.map { " ref \($0.mode) \(String(format: "%.4f", $0.value)) scrim \(String(format: "%.3f", $0.scrim)) rgb \(String(format: "%.4f", $0.rgbError))" } ?? "")
                              + (r.detent.map { " detent \($0)" } ?? ""))
                    } catch {
                        XCTFail("\(scenario.slug) \(appearance.rawValue): \(error)")
                    }
                }
                if let light = results[.light], let dark = results[.dark] {
                    entry.regions = .init(light: light.regions, dark: dark.regions)
                    entry.diagnostics = .init(referenceMode: light.check?.mode, referenceLight: light.check?.value,
                                              referenceDark: dark.check?.value, detent: light.detent,
                                              sheetHeight: light.sheetHeight)
                }
            }
            entries.append(entry)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: URL(fileURLWithPath: dir + "/manifest.json"))
        let sorted = readyTimes.sorted()
        let summary = sorted.isEmpty ? "none" : "min \(sorted.first!) median \(sorted[sorted.count / 2]) max \(sorted.last!)"
        print("gallery: \(rendered) scenario images, redraws \(redraws), ready ms \(summary)")
        XCTAssertEqual(redraws, 0, "redraws are a finding to explain")
    }

    /// Renders every `GalleryFixtures.artwork` into XFRACTAL_ARTWORK_DIR (`<name>.png`, opaque). Skipped unless set.
    func testRenderArtwork() throws {
        guard let dir = ProcessInfo.processInfo.environment["XFRACTAL_ARTWORK_DIR"], !dir.isEmpty else {
            throw XCTSkip("XFRACTAL_ARTWORK_DIR not set")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for artwork in GalleryFixtures.artwork {
            let t0 = Date()
            try GalleryMount.artworkPNG(artwork).write(to: URL(fileURLWithPath: dir + "/\(artwork.name).png"))
            print("gallery: artwork \(artwork.name) \(artwork.width)x\(artwork.height) in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        }
    }
}
