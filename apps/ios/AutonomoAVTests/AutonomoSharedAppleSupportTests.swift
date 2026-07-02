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
