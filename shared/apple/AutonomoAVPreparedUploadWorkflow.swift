import Foundation

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
    let headers: [String: String]
    let maxBytes: Int?

    enum CodingKeys: String, CodingKey {
        case uploadId
        case uploadURL
        case uploadUrl
        case uploadMethod
        case method
        case headers
        case maxBytes
    }

    init(
        uploadId: String,
        uploadURL: URL? = nil,
        uploadMethod: String? = nil,
        headers: [String: String] = [:],
        maxBytes: Int? = nil
    ) {
        self.uploadId = uploadId
        self.uploadURL = uploadURL
        self.uploadMethod = uploadMethod
        self.headers = headers
        self.maxBytes = maxBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uploadId = try container.decode(String.self, forKey: .uploadId)
        uploadURL = try container.decodeIfPresent(URL.self, forKey: .uploadURL)
            ?? container.decodeIfPresent(URL.self, forKey: .uploadUrl)
        uploadMethod = try container.decodeIfPresent(String.self, forKey: .uploadMethod)
            ?? container.decodeIfPresent(String.self, forKey: .method)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        maxBytes = try container.decodeIfPresent(Int.self, forKey: .maxBytes)
    }
}

struct AutonomoCompleteUploadResponse: Decodable, Equatable {
    let documentId: String?
    let queueItemId: String?
    let status: String?
}

struct AutonomoDocumentUploadPayload: Equatable {
    let originalFilename: String
    let contentType: String
    let data: Data
    let source: AutonomoUploadSource
}

struct AutonomoDocumentUploadResult: Equatable {
    let uploadId: String
    let documentId: String?
    let queueItemId: String?
    let status: String?
}

@MainActor
protocol AutonomoDocumentUploadBackend {
    func prepareUpload(_ request: AutonomoPrepareUploadRequest) async throws -> AutonomoPrepareUploadResponse
    func uploadData(
        _ data: Data,
        preparedUpload: AutonomoPrepareUploadResponse,
        mimeType: String
    ) async throws
    func completeUpload(uploadId: String) async throws -> AutonomoCompleteUploadResponse
}

@MainActor
struct AutonomoPreparedDocumentUploader {
    private let backend: any AutonomoDocumentUploadBackend

    init(backend: any AutonomoDocumentUploadBackend) {
        self.backend = backend
    }

    func upload(_ payload: AutonomoDocumentUploadPayload) async throws -> AutonomoDocumentUploadResult {
        let prepared = try await backend.prepareUpload(AutonomoPrepareUploadRequest(
            originalFilename: payload.originalFilename,
            contentType: payload.contentType,
            byteSize: payload.data.count,
            sha256: AutonomoDocumentAssetSupport.sha256Hex(payload.data),
            source: payload.source
        ))
        try await backend.uploadData(
            payload.data,
            preparedUpload: prepared,
            mimeType: payload.contentType
        )
        let completed = try await backend.completeUpload(uploadId: prepared.uploadId)
        return AutonomoDocumentUploadResult(
            uploadId: prepared.uploadId,
            documentId: completed.documentId,
            queueItemId: completed.queueItemId,
            status: completed.status
        )
    }
}
