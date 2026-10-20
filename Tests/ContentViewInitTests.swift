import XCTest
import SwiftUI
import AppKit
@testable import xFractal

final class ContentViewInitTests: XCTestCase {
    /// The store is an autoclosure: initialising a ContentView must not build one (SwiftUI builds it once per
    /// view identity, through StateObject's own autoclosure).
    func testStoreIsNotBuiltOnEveryInit() {
        var built = 0
        func counted() -> StateStore {
            built += 1
            return StateStore(defaults: UserDefaults(suiteName: "init-test-\(UUID().uuidString)")!)
        }
        _ = ContentView(store: counted())
        _ = ContentView(store: counted())
        XCTAssertEqual(built, 0)
    }

    /// Every SF Symbol the views name exists: a misspelt name draws nothing (the panel button went blank when open).
    func testEverySymbolExists() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("xFractal/ContentView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let names = text.matches(of: /system(?:Name|Image): [^)\n]*/).flatMap { match in
            match.output.matches(of: /"([a-z0-9.]+)"/).map { String($0.output.1) }
        }
        XCTAssertFalse(names.isEmpty)
        for name in Set(names) {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "no SF Symbol \(name)")
        }
    }
}
