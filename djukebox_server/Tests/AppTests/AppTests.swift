@testable import App
import XCTVapor

final class AppTests: XCTestCase {
    func testHelloWorld() async throws {
        let app = try await Application.make(.testing)
        try configure(app)

        try await app.test(.GET, "hello") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Hello, world!")
        }

        try await app.asyncShutdown()
    }
}
