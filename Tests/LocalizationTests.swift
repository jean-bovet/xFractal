import XCTest
@testable import xFractal

/// The app ships in English, French, German and Italian (the Swiss four), plus Spanish, Brazilian Portuguese,
/// Japanese and Turkish.
final class LocalizationTests: XCTestCase {
    static let languages = ["fr", "de", "it", "es", "pt-BR", "ja", "tr"]

    private func localized(_ resource: LocalizedStringResource, _ language: String) -> String {
        var r = resource
        r.locale = Locale(identifier: language)
        return String(localized: r)
    }

    func testPaletteLabelsAreTranslated() {
        XCTAssertEqual(localized(Palette.gray.label, "en"), "Gray")
        XCTAssertEqual(localized(Palette.gray.label, "fr"), "Gris")
        XCTAssertEqual(localized(Palette.gray.label, "de"), "Grau")
        XCTAssertEqual(localized(Palette.gray.label, "it"), "Grigio")
        XCTAssertEqual(localized(Palette.gray.label, "ja"), "グレイ")
    }

    func testJuliaPresetNamesAreTranslated() {
        let rabbit = JuliaPreset.all.first { $0.c == SIMD2(-0.123, 0.745) }!
        XCTAssertEqual(localized(rabbit.name, "en"), "Rabbit")
        XCTAssertEqual(localized(rabbit.name, "fr"), "Lapin")
    }

    /// Every key of the String Catalog has a reviewed translation in each language.
    func testCatalogIsFullyTranslated() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("xFractal/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let strings = catalog["strings"] as! [String: [String: Any]]
        XCTAssertFalse(strings.isEmpty)
        for (key, entry) in strings where entry["shouldTranslate"] as? Bool != false {
            XCTAssertNotEqual(entry["extractionState"] as? String, "stale", "stale key \(key)")
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in Self.languages {
                let unit = localizations[language]?["stringUnit"] as? [String: Any]
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key) has no \(language) translation")
            }
        }
    }
}
