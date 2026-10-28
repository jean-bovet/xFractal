import XCTest
@testable import xFractal

/// The app ships in English, French, German and Italian (the Swiss four), plus Spanish, Brazilian Portuguese,
/// Japanese, Turkish, Hebrew and Arabic (the last two right to left).
final class LocalizationTests: XCTestCase {
    static let languages = ["fr", "de", "it", "es", "pt-BR", "ja", "tr", "he", "ar"]

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
        XCTAssertEqual(localized(Palette.gray.label, "he"), "אפור")
        XCTAssertEqual(localized(Palette.gray.label, "ar"), "رمادي")
    }

    /// The iteration count keeps Western digits in every language, also under Saudi Arabia's Eastern Arabic-Indic default.
    func testIterationsLabelKeepsWesternDigits() {
        var state = ViewState.defaultState
        state.maxIterations = 250
        XCTAssertEqual(localized(state.iterationsLabel, "en"), "Iter 250")
        // Compared by scalar: String.contains folds the Arabic-Indic digits onto the Western ones.
        for language in ["he", "ar-SA"] {
            let label = localized(state.iterationsLabel, language)
            XCTAssertTrue(label.contains("250"), label)
            let easternDigits = label.unicodeScalars.filter { (0x0660...0x0669).contains($0.value) || (0x06F0...0x06F9).contains($0.value) }
            XCTAssertTrue(easternDigits.isEmpty, label)
        }
    }

    /// The Julia values keep their minus sign on the left in a right-to-left paragraph: the digits sit in a left-to-right isolate.
    func testJuliaValueLabelIsALeftToRightIsolate() {
        XCTAssertEqual(juliaValueLabel(-0.123), "\u{2066}-0.1230\u{2069}")
        XCTAssertEqual(juliaValueLabel(0.745), "\u{2066}0.7450\u{2069}")
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
