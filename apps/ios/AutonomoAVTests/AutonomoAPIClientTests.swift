import XCTest
@testable import AutonomoAV

final class AutonomoAPIClientTests: XCTestCase {
    func testURLBuilderPreservesQuery() {
        let url = AutonomoAPIClient.url(
            baseURL: URL(string: "https://api.example.com/root")!,
            path: "/v1/apps/autonomo/documents?limit=25"
        )

        XCTAssertEqual(url.absoluteString, "https://api.example.com/root/v1/apps/autonomo/documents?limit=25")
    }
}
