import XCTest
import SwiftUI
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
}
