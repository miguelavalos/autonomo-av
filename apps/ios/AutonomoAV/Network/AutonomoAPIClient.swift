import Foundation
import CryptoKit
import OSLog

struct AccountSummaryResponse: Decodable, Equatable {
    let id: String
    let displayName: String?
    let emailAddress: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case emailAddress
        case displayName
        case name
        case user
    }

    init(id: String, displayName: String? = nil, emailAddress: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.emailAddress = emailAddress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let user = try container.decodeIfPresent(AccountSummaryUserResponse.self, forKey: .user)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? user?.id
            ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? user?.displayName
        emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress)
            ?? container.decodeIfPresent(String.self, forKey: .email)
            ?? user?.emailAddress
    }
}

private struct AccountSummaryUserResponse: Decodable, Equatable {
    let id: String?
    let displayName: String?
    let emailAddress: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case emailAddress
        case displayName
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress)
            ?? container.decodeIfPresent(String.self, forKey: .email)
    }
}

enum AutonomoUploadSource: String, Codable, CaseIterable {
    case adminUpload = "admin_upload"
    case iosCamera = "ios_camera"
    case iosFiles = "ios_files"
    case iosShare = "ios_share"
    case webUpload = "web_upload"
    case emailAttachment = "email_attachment"
    case emailBody = "email_body"
}

enum AutonomoDocumentStatus: String, Codable, CaseIterable {
    case uploaded
    case queued
    case processing
    case drafted
    case needsReview = "needs_review"
    case reviewed
    case duplicate
    case ignored
    case failed
    case quarantined

    var displayText: String {
        switch self {
        case .uploaded:
            return L10n.string("intake.status.uploaded")
        case .queued:
            return L10n.string("intake.queued")
        case .processing:
            return L10n.string("intake.processing")
        case .drafted:
            return L10n.string("intake.status.drafted")
        case .needsReview:
            return L10n.string("intake.needsReview")
        case .reviewed:
            return L10n.string("intake.reviewed")
        case .duplicate:
            return L10n.string("intake.status.duplicate")
        case .ignored:
            return L10n.string("intake.status.ignored")
        case .failed:
            return L10n.string("intake.failed")
        case .quarantined:
            return L10n.string("intake.status.quarantined")
        }
    }
}

struct AutonomoPrepareUploadRequest: Encodable, Equatable {
    let originalFilename: String
    let contentType: String
    let byteSize: Int
    let sha256: String
    let source: AutonomoUploadSource
}

struct AutonomoPrepareUploadResponse: Decodable, Equatable {
    let uploadId: String
    let uploadURL: URL?
    let uploadMethod: String?
    let maxBytes: Int?

    enum CodingKeys: String, CodingKey {
        case uploadId
        case uploadURL
        case uploadUrl
        case uploadMethod
        case method
        case maxBytes
    }

    init(
        uploadId: String,
        uploadURL: URL? = nil,
        uploadMethod: String? = nil,
        maxBytes: Int? = nil
    ) {
        self.uploadId = uploadId
        self.uploadURL = uploadURL
        self.uploadMethod = uploadMethod
        self.maxBytes = maxBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uploadId = try container.decode(String.self, forKey: .uploadId)
        uploadURL = try container.decodeIfPresent(URL.self, forKey: .uploadURL)
            ?? container.decodeIfPresent(URL.self, forKey: .uploadUrl)
        uploadMethod = try container.decodeIfPresent(String.self, forKey: .uploadMethod)
            ?? container.decodeIfPresent(String.self, forKey: .method)
        maxBytes = try container.decodeIfPresent(Int.self, forKey: .maxBytes)
    }
}

struct AutonomoCompleteUploadRequest: Encodable, Equatable {
    let source: AutonomoUploadSource
    let idempotencyKey: String
}

struct AutonomoCompleteUploadResponse: Decodable, Equatable {
    let documentId: String?
    let queueItemId: String?
    let status: AutonomoDocumentStatus?
}

struct AutonomoWorkspaceSummary: Decodable, Equatable {
    let workspaceId: String
    let ownerUserId: String
    let displayName: String
    let country: String
    let timezone: String
    let defaultCurrency: String
    let status: String
    let createdAt: Date?
    let updatedAt: Date?
}

struct AutonomoWorkspaceBootstrapResponse: Decodable, Equatable {
    let appId: String
    let workspace: AutonomoWorkspaceSummary
    let generatedAt: Date?
}

struct AutonomoDocumentSummary: Decodable, Equatable, Identifiable {
    let id: String
    let title: String?
    let fileName: String?
    let mimeType: String?
    let source: AutonomoUploadSource?
    let status: AutonomoDocumentStatus
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case documentId
        case title
        case fileName
        case originalFilename
        case mimeType
        case contentType
        case source
        case status
        case createdAt
        case updatedAt
    }

    init(
        id: String,
        title: String? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        source: AutonomoUploadSource? = nil,
        status: AutonomoDocumentStatus,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.mimeType = mimeType
        self.source = source
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .documentId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
            ?? container.decodeIfPresent(String.self, forKey: .originalFilename)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            ?? container.decodeIfPresent(String.self, forKey: .contentType)
        source = try container.decodeIfPresent(AutonomoUploadSource.self, forKey: .source)
        status = try container.decode(AutonomoDocumentStatus.self, forKey: .status)
        createdAt = try container.decodeFlexibleDateIfPresent(forKey: .createdAt)
        updatedAt = try container.decodeFlexibleDateIfPresent(forKey: .updatedAt)
    }
}

struct AutonomoDocumentsResponse: Decodable, Equatable {
    let documents: [AutonomoDocumentSummary]
}

private struct AutonomoPromoCodeRedeemRequest: Encodable {
    let code: String
}

struct AutonomoPromotionCodeRedemptionResponse: Decodable, Equatable {
    let appId: String
    let userId: String
    let code: String
    let campaignId: String
    let redemptionId: String
}

enum AutonomoPromoCodeClientError: LocalizedError, Equatable {
    case missingBaseURL
    case missingToken
    case requestFailed(statusCode: Int)
    case server(code: String, message: String, statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            L10n.string("promo.error.configuration")
        case .missingToken:
            L10n.string("upload.error.missingToken")
        case .requestFailed:
            L10n.string("promo.error.redeemFailed")
        case .server(_, let message, _):
            message
        }
    }

    static func decode(from data: Data, statusCode: Int) -> AutonomoPromoCodeClientError {
        if let decoded = try? JSONDecoder().decode(AutonomoPromoCodeErrorResponse.self, from: data) {
            return .server(
                code: decoded.error.code,
                message: decoded.error.message,
                statusCode: statusCode
            )
        }
        return .requestFailed(statusCode: statusCode)
    }
}

private struct AutonomoPromoCodeErrorResponse: Decodable {
    struct APIError: Decodable {
        let code: String
        let message: String
    }

    let error: APIError
}

enum AutonomoAPIClientError: LocalizedError, Equatable {
    case missingToken
    case missingBaseURL
    case requestFailed(statusCode: Int)
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .missingToken:
            L10n.string("upload.error.missingToken")
        case .missingBaseURL:
            L10n.string("upload.error.missingBaseURL")
        case .requestFailed(let statusCode):
            L10n.string("upload.error.requestFailed", statusCode)
        case .unsupportedFile:
            L10n.string("upload.error.unsupportedFile")
        }
    }
}

@MainActor
final class AutonomoAPIClient {
    nonisolated static let appIdentifier = "autonomoav"
    nonisolated private static let appIdHeaderValue = appIdentifier

    struct RetryPolicy: Equatable {
        let maxAttempts: Int
        let backoffNanoseconds: UInt64

        static let productAPI = RetryPolicy(maxAttempts: 2, backoffNanoseconds: 250_000_000)
        static let disabled = RetryPolicy(maxAttempts: 1, backoffNanoseconds: 0)

        func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
            attempt < maxAttempts && (500..<600).contains(statusCode)
        }

        func shouldRetry(error: Error, attempt: Int) -> Bool {
            guard attempt < maxAttempts, let urlError = error as? URLError else {
                return false
            }

            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }

        func sleep(beforeAttempt attempt: Int) async throws {
            guard attempt > 1, backoffNanoseconds > 0 else { return }
            try await Task.sleep(nanoseconds: backoffNanoseconds)
        }
    }

    private let baseURLProvider: () -> URL?
    private let tokenProvider: () async throws -> String?
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let retryPolicy: RetryPolicy
    private let logger = Logger(subsystem: "com.avalsys.autonomoav", category: "network")

    init(
        baseURLProvider: @escaping () -> URL? = { AppConfig.autonomoAPIBaseURL },
        tokenProvider: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        retryPolicy: RetryPolicy = .productAPI
    ) {
        self.baseURLProvider = baseURLProvider
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.retryPolicy = retryPolicy

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeAutonomoDate)
        self.decoder = decoder
    }

    var isConfigured: Bool {
        baseURLProvider() != nil
    }

    func fetchAccountSummary() async throws -> AccountSummaryResponse {
        try await request(path: "/v1/me")
    }

    func fetchMeAccess() async throws -> AutonomoMeAccessResponse {
        try await request(path: "/v1/me/access")
    }

    func redeemPromotionCode(_ code: String) async throws -> AutonomoPromotionCodeRedemptionResponse {
        guard let token = try await tokenProvider(), !token.isEmpty else {
            throw AutonomoPromoCodeClientError.missingToken
        }
        guard let baseURL = baseURLProvider() else {
            throw AutonomoPromoCodeClientError.missingBaseURL
        }

        var request = URLRequest(url: Self.url(baseURL: baseURL, path: "/v1/apps/\(Self.appIdentifier)/promotions/redeem"))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(AutonomoPromoCodeRedeemRequest(code: code))
        Self.addAuthenticatedHeaders(to: &request, bearerToken: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response, _) = try await performDataTask(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AutonomoPromoCodeClientError.requestFailed(statusCode: -1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AutonomoPromoCodeClientError.decode(from: data, statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(AutonomoPromotionCodeRedemptionResponse.self, from: data)
    }

    func bootstrapWorkspace() async throws -> AutonomoWorkspaceBootstrapResponse {
        try await request(path: "/v1/apps/autonomo/workspace/bootstrap", method: "POST")
    }

    func prepareUpload(_ request: AutonomoPrepareUploadRequest) async throws -> AutonomoPrepareUploadResponse {
        try await jsonRequest(
            path: "/v1/apps/autonomo/uploads/prepare",
            method: "POST",
            body: request
        )
    }

    func uploadData(_ data: Data, uploadId: String, mimeType: String) async throws {
        _ = try await requestData(
            path: "/v1/apps/autonomo/uploads/\(uploadId)",
            method: "PUT",
            body: data,
            headers: ["Content-Type": mimeType]
        )
    }

    func uploadData(
        _ data: Data,
        preparedUpload: AutonomoPrepareUploadResponse,
        mimeType: String
    ) async throws {
        if let uploadURL = preparedUpload.uploadURL {
            try await uploadData(
                data,
                uploadURL: uploadURL,
                uploadMethod: preparedUpload.uploadMethod,
                mimeType: mimeType
            )
        } else {
            try await uploadData(data, uploadId: preparedUpload.uploadId, mimeType: mimeType)
        }
    }

    func completeUpload(
        uploadId: String,
        source: AutonomoUploadSource,
        idempotencyKey: String
    ) async throws -> AutonomoCompleteUploadResponse {
        try await request(path: "/v1/apps/autonomo/uploads/\(uploadId)/complete", method: "POST")
    }

    func fetchRecentDocuments(limit: Int = 25) async throws -> [AutonomoDocumentSummary] {
        let response: AutonomoDocumentsResponse = try await request(path: "/v1/apps/autonomo/documents?limit=\(limit)")
        return response.documents
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
        let data = try await requestData(path: path, method: method, body: body, headers: headers)
        return try decoder.decode(T.self, from: data)
    }

    func jsonRequest<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> T {
        try await request(
            path: path,
            method: method,
            body: encoder.encode(body),
            headers: ["Content-Type": "application/json"]
        )
    }

    func requestData(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        guard let token = try await tokenProvider(), !token.isEmpty else {
            throw AutonomoAPIClientError.missingToken
        }
        guard let baseURL = baseURLProvider() else {
            throw AutonomoAPIClientError.missingBaseURL
        }

        var request = URLRequest(url: Self.url(baseURL: baseURL, path: path))
        request.httpMethod = method
        request.httpBody = body
        Self.addAuthenticatedHeaders(to: &request, bearerToken: token)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let startedAt = Date()
        let (data, response, attempts) = try await performDataTask(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            logger.error("Autonomo API request failed method=\(method, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) attempts=\(attempts, privacy: .public)")
            throw AutonomoAPIClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        logger.info("Autonomo API request completed method=\(method, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) duration_ms=\(durationMilliseconds, privacy: .public)")
        return data
    }

    private func performDataTask(for request: URLRequest) async throws -> (Data, URLResponse, Int) {
        var attempt = 1

        while true {
            do {
                let (data, response) = try await urlSession.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   retryPolicy.shouldRetry(statusCode: httpResponse.statusCode, attempt: attempt),
                   !Task.isCancelled {
                    try await retryPolicy.sleep(beforeAttempt: attempt + 1)
                    attempt += 1
                    continue
                }
                return (data, response, attempt)
            } catch {
                guard retryPolicy.shouldRetry(error: error, attempt: attempt), !Task.isCancelled else {
                    throw error
                }
                try await retryPolicy.sleep(beforeAttempt: attempt + 1)
                attempt += 1
            }
        }
    }

    private func uploadData(
        _ data: Data,
        uploadURL: URL,
        uploadMethod: String?,
        mimeType: String
    ) async throws {
        let baseURL = baseURLProvider()
        let resolvedUploadURL = Self.resolvedPreparedUploadURL(uploadURL, baseURL: baseURL)
        let method = uploadMethod?.trimmingCharacters(in: .whitespacesAndNewlines)
        var request = URLRequest(url: resolvedUploadURL)
        request.httpMethod = method?.isEmpty == false ? method : "PUT"
        request.httpBody = data
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        if Self.shouldAuthorizePreparedUpload(uploadURL: resolvedUploadURL, baseURL: baseURL) {
            guard let token = try await tokenProvider(), !token.isEmpty else {
                throw AutonomoAPIClientError.missingToken
            }
            Self.addAuthenticatedHeaders(to: &request, bearerToken: token)
        }

        let startedAt = Date()
        let (_, response, attempts) = try await performDataTask(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            logger.error("Autonomo prepared upload failed method=\(request.httpMethod ?? "unknown", privacy: .public) status=\(httpResponse.statusCode, privacy: .public) attempts=\(attempts, privacy: .public)")
            throw AutonomoAPIClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        logger.info("Autonomo prepared upload completed method=\(request.httpMethod ?? "unknown", privacy: .public) status=\(httpResponse.statusCode, privacy: .public) duration_ms=\(durationMilliseconds, privacy: .public)")
    }

    nonisolated static func url(baseURL: URL, path: String) -> URL {
        let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let pathAndQuery = sanitizedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let url = baseURL.appending(path: String(pathAndQuery.first ?? ""))
        guard pathAndQuery.count == 2,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.percentEncodedQuery = String(pathAndQuery[1])
        return components.url ?? url
    }

    nonisolated static func resolvedPreparedUploadURL(_ uploadURL: URL, baseURL: URL?) -> URL {
        guard uploadURL.scheme == nil, let baseURL else {
            return uploadURL
        }
        return URL(string: uploadURL.relativeString, relativeTo: baseURL)?.absoluteURL ?? uploadURL
    }

    nonisolated static func shouldAuthorizePreparedUpload(uploadURL: URL, baseURL: URL?) -> Bool {
        guard let baseURL,
              let uploadHost = uploadURL.host,
              let baseHost = baseURL.host else {
            return false
        }
        return uploadURL.scheme == baseURL.scheme &&
            uploadHost == baseHost &&
            uploadURL.port == baseURL.port
    }

    nonisolated static func addAuthenticatedHeaders(to request: inout URLRequest, bearerToken: String) {
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(appIdHeaderValue, forHTTPHeaderField: "x-appsav-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    nonisolated static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    nonisolated static func decodeAutonomoDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = parseAutonomoDate(value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDateIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return parseAutonomoDate(value)
    }
}

private func parseAutonomoDate(_ value: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: value) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
