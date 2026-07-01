import XCTest
@testable import DJukeboxCommon

final class DJukeboxCommonTests: XCTestCase {
    // `<=` on Log.Level compares severity: `.error` is the most severe and is
    // shown by a handler set at any threshold; `.debug` is the least severe.
    func testLevelSeverityOrdering() {
        XCTAssertTrue(Log.Level.error <= Log.Level.debug)
        XCTAssertTrue(Log.Level.warn <= Log.Level.info)
        XCTAssertFalse(Log.Level.debug <= Log.Level.error)
    }

    func testStringLogData() {
        let data = StringLogData(with: "hello")
        XCTAssertEqual(data.description, "hello")
        XCTAssertNil(data.encodable)
    }

    static let allTests = [
        ("testLevelSeverityOrdering", testLevelSeverityOrdering),
        ("testStringLogData", testStringLogData),
    ]
}
