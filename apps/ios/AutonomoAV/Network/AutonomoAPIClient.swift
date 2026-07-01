import Foundation
import OSLog

struct AccountSummaryResponse: Decodable, Equatable {
    let id: String
    let displayName: String?
    let emailAddress: String?
}

enum AutonomoUploadSource: String, Codable, CaseIterable {
    case iosCamera = "ios_camera"
    case iosFiles = "ios_files"
    case iosShare = "ios_share"
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
    let fileName: String
    let mimeType: String
    let byteSize: Int
    let source: AutonomoUploadSource
    let idempotencyKey: String
    let clientCreatedAt: Date
}

struct AutonomoPrepareUploadResponse: Decodable, Equatable {
    let uploadId: String
    let uploadURL: URL?
    let uploadMethod: String?
    let maxBytes: Int?
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
        case mimeType
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
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        source = try container.decodeIfPresent(AutonomoUploadSource.self, forKey: .source)
        status = try container.decode(AutonomoDocumentStatus.self, forKey: .status)
        createdAt = try container.decodeFlexibleDateIfPresent(forKey: .createdAt)
        updatedAt = try container.decodeFlexibleDateIfPresent(forKey: .updatedAt)
    }
}

struct AutonomoDocumentsResponse: Decodable, Equatable {
    let documents: [AutonomoDocumentSummary]
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
        decoder.dateDecodingStrategy = .custom(Self.decodeDate)
        self.decoder = decoder
    }

    var isConfigured: Bool {
        baseURLProvider() != nil
    }

    func fetchAccountSummary() async throws -> AccountSummaryResponse {
        try await request(path: "/v1/me")
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

    func completeUpload(
        uploadId: String,
        source: AutonomoUploadSource,
        idempotencyKey: String
    ) async throws -> AutonomoCompleteUploadResponse {
        try await jsonRequest(
            path: "/v1/apps/autonomo/uploads/\(uploadId)/complete",
            method: "POST",
            body: AutonomoCompleteUploadRequest(source: source, idempotencyKey: idempotencyKey)
        )
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
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("autonomo", forHTTPHeaderField: "x-appsav-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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

    nonisolated private static func decodeDate(from decoder: Decoder) throws -> Date {
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
