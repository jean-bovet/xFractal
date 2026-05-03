import XCTest
@testable import xFractal

final class CodableTests: XCTestCase {
    func testViewStateRoundTrips() throws {
        for type in FractalType.allCases {
            let original = ViewState.defaults(for: type)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ViewState.self, from: data)
            XCTAssertEqual(decoded, original, "\(type) round-trip mismatch")
        }
    }

    func testSnapshotRoundTrips() throws {
        let original = Snapshot(state: ViewState.defaults(for: .newton), time: 12.34)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testJournalArrayRoundTrips() throws {
        let arr = [
            Snapshot(state: ViewState.defaults(for: .mandelbrot), time: 0),
            Snapshot(state: ViewState.defaults(for: .julia),      time: 0.1),
            Snapshot(state: ViewState.defaults(for: .multibrot),  time: 0.2),
        ]
        let data = try JSONEncoder().encode(arr)
        let decoded = try JSONDecoder().decode([Snapshot].self, from: data)
        XCTAssertEqual(decoded, arr)
    }

    func testDecodingGarbageReturnsNil() {
        let bogus = Data("not json".utf8)
        XCTAssertNil(try? JSONDecoder().decode(ViewState.self, from: bogus))
        XCTAssertNil(try? JSONDecoder().decode([Snapshot].self, from: bogus))
    }
}
