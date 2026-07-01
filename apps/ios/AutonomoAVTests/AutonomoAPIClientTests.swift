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

    func testPrepareUploadResponseDecodesUploadURLAliases() throws {
        let data = Data("""
        {
          "uploadId": "upload_123",
          "uploadUrl": "https://uploads.example.com/signed",
          "uploadMethod": "PUT",
          "maxBytes": 10485760
        }
        """.utf8)

        let response = try JSONDecoder().decode(AutonomoPrepareUploadResponse.self, from: data)

        XCTAssertEqual(response.uploadId, "upload_123")
        XCTAssertEqual(response.uploadURL, URL(string: "https://uploads.example.com/signed"))
        XCTAssertEqual(response.uploadMethod, "PUT")
        XCTAssertEqual(response.maxBytes, 10_485_760)
    }

    func testPreparedUploadAuthorizationDecisionUsesApiOriginOnly() {
        let baseURL = URL(string: "https://api-account-av-preview.avalsys.com")!

        XCTAssertTrue(AutonomoAPIClient.shouldAuthorizePreparedUpload(
            uploadURL: URL(string: "https://api-account-av-preview.avalsys.com/v1/apps/autonomo/uploads/upload_123")!,
            baseURL: baseURL
        ))
        XCTAssertFalse(AutonomoAPIClient.shouldAuthorizePreparedUpload(
            uploadURL: URL(string: "https://example-r2.cloudflare.com/bucket/object?signature=abc")!,
            baseURL: baseURL
        ))
    }

    func testPreparedUploadURLResolvesRelativeApiPath() {
        let baseURL = URL(string: "https://api-account-av-preview.avalsys.com")!
        let resolved = AutonomoAPIClient.resolvedPreparedUploadURL(
            URL(string: "/v1/apps/autonomo/uploads/upload_123")!,
            baseURL: baseURL
        )

        XCTAssertEqual(resolved.absoluteString, "https://api-account-av-preview.avalsys.com/v1/apps/autonomo/uploads/upload_123")
    }
}
