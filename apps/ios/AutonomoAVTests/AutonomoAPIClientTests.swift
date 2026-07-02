import XCTest
@testable import AutonomoAV

final class AutonomoAPIClientTests: XCTestCase {
    func testPrepareUploadRequestEncodesBackendPayload() throws {
        let request = AutonomoPrepareUploadRequest(
            originalFilename: "invoice.pdf",
            contentType: "application/pdf",
            byteSize: 12,
            sha256: String(repeating: "a", count: 64),
            source: .iosFiles
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["originalFilename"] as? String, "invoice.pdf")
        XCTAssertEqual(json["contentType"] as? String, "application/pdf")
        XCTAssertEqual(json["byteSize"] as? Int, 12)
        XCTAssertEqual(json["sha256"] as? String, String(repeating: "a", count: 64))
        XCTAssertEqual(json["source"] as? String, "ios_files")
        XCTAssertNil(json["fileName"])
        XCTAssertNil(json["mimeType"])
    }

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

    func testPrepareUploadResponseDecodesBackendMethodField() throws {
        let data = Data("""
        {
          "appId": "autonomoav",
          "workspaceId": "workspace_123",
          "documentId": "doc_123",
          "assetId": "asset_123",
          "uploadId": "upload_123",
          "uploadUrl": "/v1/apps/autonomo/uploads/upload_123",
          "completionUrl": "/v1/apps/autonomo/uploads/upload_123/complete",
          "method": "PUT",
          "headers": { "Content-Type": "application/pdf" },
          "expiresAt": "2026-07-01T20:00:00.000Z",
          "generatedAt": "2026-07-01T19:55:00.000Z"
        }
        """.utf8)

        let response = try JSONDecoder().decode(AutonomoPrepareUploadResponse.self, from: data)

        XCTAssertEqual(response.uploadURL, URL(string: "/v1/apps/autonomo/uploads/upload_123"))
        XCTAssertEqual(response.uploadMethod, "PUT")
    }

    func testDocumentSummaryDecodesBackendNamesAndCrossSurfaceSources() throws {
        let data = Data("""
        {
          "documentId": "doc_123",
          "originalFilename": "web-invoice.pdf",
          "contentType": "application/pdf",
          "source": "web_upload",
          "status": "queued",
          "createdAt": "2026-07-01T20:00:00.000Z",
          "updatedAt": "2026-07-01T20:00:00.000Z"
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(AutonomoAPIClient.decodeAutonomoDate)
        let document = try decoder.decode(AutonomoDocumentSummary.self, from: data)

        XCTAssertEqual(document.id, "doc_123")
        XCTAssertEqual(document.fileName, "web-invoice.pdf")
        XCTAssertEqual(document.mimeType, "application/pdf")
        XCTAssertEqual(document.source, .webUpload)
    }

    func testWorkspaceBootstrapResponseDecodes() throws {
        let data = Data("""
        {
          "appId": "autonomoav",
          "workspace": {
            "workspaceId": "workspace_123",
            "ownerUserId": "user_123",
            "displayName": "Autonomo AV",
            "country": "ES",
            "timezone": "Europe/Madrid",
            "defaultCurrency": "EUR",
            "status": "active",
            "createdAt": "2026-07-01T20:00:00.000Z",
            "updatedAt": "2026-07-01T20:00:00.000Z"
          },
          "generatedAt": "2026-07-01T20:00:00.000Z"
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(AutonomoAPIClient.decodeAutonomoDate)
        let response = try decoder.decode(AutonomoWorkspaceBootstrapResponse.self, from: data)

        XCTAssertEqual(response.appId, "autonomoav")
        XCTAssertEqual(response.workspace.workspaceId, "workspace_123")
        XCTAssertEqual(response.workspace.ownerUserId, "user_123")
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

    func testAuthenticatedRequestsUseCanonicalAutonomoAppId() {
        var request = URLRequest(url: URL(string: "https://api-account-av-preview.avalsys.com/v1/me")!)

        AutonomoAPIClient.addAuthenticatedHeaders(to: &request, bearerToken: "token_123")

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token_123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-appsav-app-id"), "autonomoav")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testSHA256Hex() {
        let digest = AutonomoAPIClient.sha256Hex(Data("abc".utf8))

        XCTAssertEqual(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
