import XCTest
@testable import AutonomoAV

@MainActor
final class AutonomoSharedAppleSupportTests: XCTestCase {
    override func tearDown() {
        AutonomoTestURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testPromoCodeClientRedeemsAgainstBackendPromotionEndpoint() async throws {
        AutonomoTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/v1/apps/autonomoav/promotions/redeem")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-appsav-app-id"), "autonomoav")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(Self.requestBodyData(from: request))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["code"] as? String, "AUTONOMO-PRO")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                """
                {
                  "appId": "autonomoav",
                  "userId": "apps-av-user",
                  "code": "AUTONOMO-PRO",
                  "campaignId": "campaign-1",
                  "redemptionId": "redemption-1",
                  "entitlement": {
                    "appId": "autonomoav",
                    "userId": "apps-av-user",
                    "planTier": "pro",
                    "accessMode": "signedInPro",
                    "status": "active",
                    "source": "promo"
                  }
                }
                """.utf8
            )
            return (response, data)
        }

        let client = AutonomoPromoCodeClient(
            baseURL: URL(string: "https://api.example.test"),
            urlSession: makeURLSession(),
            tokenProvider: { "token-123" }
        )

        let response = try await client.redeemPromotionCode("AUTONOMO-PRO")

        XCTAssertEqual(response.appId, "autonomoav")
        XCTAssertEqual(response.redemptionId, "redemption-1")
        XCTAssertEqual(response.entitlement?.planTier, "pro")
    }

    func testPromoCodeClientSurfacesBackendErrorMessage() async {
        AutonomoTestURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                """
                {
                  "error": {
                    "code": "promo_code_unavailable",
                    "message": "This promo code is not available."
                  }
                }
                """.utf8
            )
            return (response, data)
        }

        let client = AutonomoPromoCodeClient(
            baseURL: URL(string: "https://api.example.test"),
            urlSession: makeURLSession(),
            tokenProvider: { "token-123" }
        )

        do {
            _ = try await client.redeemPromotionCode("AUTONOMO-PRO")
            XCTFail("Expected promo code redemption to fail.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "This promo code is not available.")
        }
    }

    func testDocumentAssetSupportRecognizesAllowedUploadMimeTypes() {
        XCTAssertEqual(
            AutonomoDocumentAssetSupport.mimeType(for: URL(fileURLWithPath: "/tmp/invoice.PDF")),
            "application/pdf"
        )
        XCTAssertEqual(
            AutonomoDocumentAssetSupport.mimeType(for: URL(fileURLWithPath: "/tmp/receipt.webp")),
            "image/webp"
        )
        XCTAssertEqual(
            AutonomoDocumentAssetSupport.mimeType(for: URL(fileURLWithPath: "/tmp/photo.heif")),
            "image/heif"
        )
        XCTAssertNil(AutonomoDocumentAssetSupport.mimeType(for: URL(fileURLWithPath: "/tmp/animation.gif")))
    }

    func testDocumentAssetSupportProvidesStableAppleUploadSources() {
        XCTAssertTrue(AutonomoUploadSource.allCases.contains(.iosShare))
        XCTAssertTrue(AutonomoUploadSource.allCases.contains(.macosFiles))
        XCTAssertTrue(AutonomoUploadSource.allCases.contains(.macosDragDrop))
        XCTAssertTrue(AutonomoUploadSource.allCases.contains(.macosShare))
        XCTAssertTrue(AutonomoUploadSource.allCases.contains(.macosService))
        XCTAssertFalse(AutonomoUploadSource.allCases.map(\.rawValue).contains("mail_message"))
    }

    func testDocumentAssetSupportBuildsChecksumAndIdempotencyKey() {
        let id = UUID(uuidString: "F4F21B55-5E1C-49B2-89EF-3E1A5A8DD08B")!

        XCTAssertEqual(
            AutonomoDocumentAssetSupport.sha256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            AutonomoDocumentAssetSupport.idempotencyKey(prefix: "ios", id: id),
            "ios-F4F21B55-5E1C-49B2-89EF-3E1A5A8DD08B"
        )
        XCTAssertEqual(
            AutonomoDocumentAssetSupport.idempotencyKey(prefix: "macos", id: id),
            "macos-F4F21B55-5E1C-49B2-89EF-3E1A5A8DD08B"
        )
    }

    func testLocalIntakeQueueRestoresInterruptedUploadsAsPending() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var interruptedItem = Self.makeLocalIntakeItem()
        interruptedItem.status = .uploading
        interruptedItem.errorMessage = "Interrupted"

        let normalized = AutonomoLocalIntakeQueue.normalizeLoadedItems([interruptedItem], now: now)

        XCTAssertTrue(normalized.didChange)
        XCTAssertEqual(normalized.items.first?.status, .pending)
        XCTAssertNil(normalized.items.first?.errorMessage)
        XCTAssertEqual(normalized.items.first?.updatedAt, now)
    }

    func testLocalIntakeItemUploadTransitions() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_001)
        let failedAt = Date(timeIntervalSince1970: 1_800_000_002)
        let retriedAt = Date(timeIntervalSince1970: 1_800_000_003)
        let uploadedAt = Date(timeIntervalSince1970: 1_800_000_004)
        var item = Self.makeLocalIntakeItem()

        item.markUploading(now: startedAt)
        XCTAssertEqual(item.status, .uploading)
        XCTAssertEqual(item.attemptCount, 1)
        XCTAssertEqual(item.updatedAt, startedAt)
        XCTAssertNil(item.errorMessage)

        item.markFailed("Network unavailable", now: failedAt)
        XCTAssertEqual(item.status, .failed)
        XCTAssertEqual(item.errorMessage, "Network unavailable")
        XCTAssertEqual(item.updatedAt, failedAt)

        item.markPendingForRetry(now: retriedAt)
        XCTAssertEqual(item.status, .pending)
        XCTAssertNil(item.errorMessage)
        XCTAssertEqual(item.updatedAt, retriedAt)

        item.markUploaded(
            AutonomoDocumentUploadResult(
                uploadId: "upload_123",
                documentId: "document_123",
                queueItemId: "queue_123",
                status: "queued"
            ),
            now: uploadedAt
        )
        XCTAssertEqual(item.status, .uploaded)
        XCTAssertEqual(item.uploadId, "upload_123")
        XCTAssertEqual(item.documentId, "document_123")
        XCTAssertEqual(item.queueItemId, "queue_123")
        XCTAssertEqual(item.updatedAt, uploadedAt)
        XCTAssertNil(item.errorMessage)
    }

    func testPreparedDocumentUploaderRunsPreparePutComplete() async throws {
        let backend = FakeDocumentUploadBackend()
        let uploader = AutonomoPreparedDocumentUploader(backend: backend)
        let data = Data("abc".utf8)

        let result = try await uploader.upload(AutonomoDocumentUploadPayload(
            originalFilename: "macos-drop.pdf",
            contentType: "application/pdf",
            data: data,
            source: .macosDragDrop
        ))

        XCTAssertEqual(backend.preparedRequest?.originalFilename, "macos-drop.pdf")
        XCTAssertEqual(backend.preparedRequest?.contentType, "application/pdf")
        XCTAssertEqual(backend.preparedRequest?.byteSize, data.count)
        XCTAssertEqual(
            backend.preparedRequest?.sha256,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(backend.preparedRequest?.source, .macosDragDrop)
        XCTAssertEqual(backend.uploadedData, data)
        XCTAssertEqual(backend.uploadedPreparedUpload?.uploadId, "upload_123")
        XCTAssertEqual(backend.uploadedMimeType, "application/pdf")
        XCTAssertEqual(backend.completedUploadId, "upload_123")
        XCTAssertEqual(result.uploadId, "upload_123")
        XCTAssertEqual(result.documentId, "document_123")
        XCTAssertEqual(result.queueItemId, "queue_123")
        XCTAssertEqual(result.status, "queued")
    }

    private static func makeLocalIntakeItem() -> LocalIntakeItem {
        let id = UUID(uuidString: "F4F21B55-5E1C-49B2-89EF-3E1A5A8DD08B")!
        return LocalIntakeItem(
            id: id,
            fileName: "invoice.pdf",
            mimeType: "application/pdf",
            byteSize: 123,
            relativePath: "Uploads/invoice.pdf",
            source: .macosFiles,
            status: .pending,
            idempotencyKey: AutonomoDocumentAssetSupport.idempotencyKey(prefix: "macos", id: id),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            uploadId: nil,
            documentId: nil,
            queueItemId: nil,
            attemptCount: 0,
            errorMessage: nil
        )
    }

    private func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutonomoTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func requestBodyData(from request: URLRequest) throws -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }

        return data
    }
}

@MainActor
private final class FakeDocumentUploadBackend: AutonomoDocumentUploadBackend {
    var preparedRequest: AutonomoPrepareUploadRequest?
    var uploadedData: Data?
    var uploadedPreparedUpload: AutonomoPrepareUploadResponse?
    var uploadedMimeType: String?
    var completedUploadId: String?

    func prepareUpload(_ request: AutonomoPrepareUploadRequest) async throws -> AutonomoPrepareUploadResponse {
        preparedRequest = request
        return AutonomoPrepareUploadResponse(
            uploadId: "upload_123",
            uploadURL: URL(string: "/v1/apps/autonomo/uploads/upload_123"),
            uploadMethod: "PUT",
            headers: ["Content-Type": "application/pdf"]
        )
    }

    func uploadData(
        _ data: Data,
        preparedUpload: AutonomoPrepareUploadResponse,
        mimeType: String
    ) async throws {
        uploadedData = data
        uploadedPreparedUpload = preparedUpload
        uploadedMimeType = mimeType
    }

    func completeUpload(uploadId: String) async throws -> AutonomoCompleteUploadResponse {
        completedUploadId = uploadId
        return AutonomoCompleteUploadResponse(
            documentId: "document_123",
            queueItemId: "queue_123",
            status: "queued"
        )
    }
}

private final class AutonomoTestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
