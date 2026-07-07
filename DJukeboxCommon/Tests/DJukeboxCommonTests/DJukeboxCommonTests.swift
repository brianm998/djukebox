import Testing
@testable import DJukeboxCommon

// `<=` on Log.Level compares severity: `.error` is the most severe and is
// shown by a handler set at any threshold; `.debug` is the least severe.
@Test func levelSeverityOrdering() {
    #expect(Log.Level.error <= Log.Level.debug)
    #expect(Log.Level.warn <= Log.Level.info)
    #expect(!(Log.Level.debug <= Log.Level.error))
}

@Test func stringLogData() {
    let data = StringLogData(with: "hello")
    #expect(data.description == "hello")
    #expect(data.encodable == nil)
}
