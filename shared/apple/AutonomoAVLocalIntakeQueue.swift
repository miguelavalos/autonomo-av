import Foundation

enum AutonomoDocumentIntakeError: LocalizedError, Equatable {
    case unsupportedFile
    case uploadTooLarge

    var isDeterministicRejection: Bool {
        switch self {
        case .unsupportedFile, .uploadTooLarge:
            return true
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "This file type is not supported."
        case .uploadTooLarge:
            return "This file is too large."
        }
    }
}

enum LocalIntakeStatus: String, Codable, Equatable {
    case pending
    case uploading
    case uploaded
    case failed
}

struct LocalIntakeItem: Codable, Equatable, Identifiable {
    let id: UUID
    var fileName: String
    var mimeType: String
    var byteSize: Int
    var relativePath: String
    var source: AutonomoUploadSource
    var status: LocalIntakeStatus
    var idempotencyKey: String
    var createdAt: Date
    var updatedAt: Date
    var uploadId: String?
    var documentId: String?
    var queueItemId: String?
    var attemptCount: Int
    var errorMessage: String?

    mutating func markPendingForRetry(now: Date = Date()) {
        status = .pending
        errorMessage = nil
        updatedAt = now
    }

    mutating func markUploading(now: Date = Date()) {
        status = .uploading
        attemptCount += 1
        updatedAt = now
        errorMessage = nil
    }

    mutating func markUploaded(_ uploadResult: AutonomoDocumentUploadResult, now: Date = Date()) {
        status = .uploaded
        uploadId = uploadResult.uploadId
        documentId = uploadResult.documentId
        queueItemId = uploadResult.queueItemId
        updatedAt = now
        errorMessage = nil
    }

    mutating func markFailed(_ message: String, now: Date = Date()) {
        status = .failed
        errorMessage = message
        updatedAt = now
    }
}

enum AutonomoLocalIntakeQueue {
    static func normalizeLoadedItems(
        _ items: [LocalIntakeItem],
        now: Date = Date()
    ) -> (items: [LocalIntakeItem], didChange: Bool) {
        var didChange = false
        let normalizedItems = items.map { item -> LocalIntakeItem in
            guard item.status == .uploading else {
                return item
            }

            var normalizedItem = item
            normalizedItem.status = .pending
            normalizedItem.errorMessage = nil
            normalizedItem.updatedAt = now
            didChange = true
            return normalizedItem
        }

        return (normalizedItems, didChange)
    }
}

struct LocalIntakePersistence {
    let rootURL: URL
    private let fileManager: FileManager
    private let idempotencyKeyPrefix: String
    private let sharedInboxSource: AutonomoUploadSource

    init(
        rootURL: URL = LocalIntakePersistence.defaultRootURL(),
        fileManager: FileManager = .default,
        idempotencyKeyPrefix: String = "ios",
        sharedInboxSource: AutonomoUploadSource = .iosShare
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.idempotencyKeyPrefix = idempotencyKeyPrefix
        self.sharedInboxSource = sharedInboxSource
    }

    var uploadsURL: URL {
        rootURL.appending(path: "Uploads", directoryHint: .isDirectory)
    }

    var metadataURL: URL {
        rootURL.appending(path: "intake-items.json")
    }

    func loadItems() -> [LocalIntakeItem] {
        guard let data = try? Data(contentsOf: metadataURL) else {
            return []
        }
        return (try? JSONDecoder.autonomo.decode([LocalIntakeItem].self, from: data)) ?? []
    }

    func saveItems(_ items: [LocalIntakeItem]) throws {
        try ensureDirectories()
        let data = try JSONEncoder.autonomo.encode(items)
        try data.write(to: metadataURL, options: [.atomic])
    }

    func copyImportedFile(from url: URL, source: AutonomoUploadSource) throws -> LocalIntakeItem {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try copyFile(from: url, source: source)
    }

    func copySharedInboxFile(from url: URL, source: AutonomoUploadSource? = nil) throws -> LocalIntakeItem {
        try copyFile(from: url, source: source ?? sharedInboxSource)
    }

    func storeData(
        _ data: Data,
        fileName: String,
        mimeType: String,
        source: AutonomoUploadSource
    ) throws -> LocalIntakeItem {
        guard data.count <= AutonomoDocumentAssetSupport.maxUploadByteSize else {
            throw AutonomoDocumentIntakeError.uploadTooLarge
        }
        let normalizedMimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard AutonomoDocumentAssetSupport.supportedMimeTypes.contains(normalizedMimeType) else {
            throw AutonomoDocumentIntakeError.unsupportedFile
        }

        try ensureDirectories()
        let id = UUID()
        let destination = uploadsURL.appending(path: "\(id.uuidString)-\(fileName)")
        try data.write(to: destination, options: [.atomic])
        return try makeItem(
            id: id,
            fileName: fileName,
            mimeType: normalizedMimeType,
            source: source,
            destination: destination
        )
    }

    func fileURL(for item: LocalIntakeItem) -> URL {
        rootURL.appending(path: item.relativePath)
    }

    private func copyFile(from url: URL, source: AutonomoUploadSource) throws -> LocalIntakeItem {
        try ensureDirectories()
        let id = UUID()
        let fileName = url.lastPathComponent.isEmpty ? "document-\(id.uuidString).pdf" : url.lastPathComponent
        guard let mimeType = AutonomoDocumentAssetSupport.mimeType(for: url) else {
            throw AutonomoDocumentIntakeError.unsupportedFile
        }
        let byteSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard byteSize <= AutonomoDocumentAssetSupport.maxUploadByteSize else {
            throw AutonomoDocumentIntakeError.uploadTooLarge
        }
        let destination = uploadsURL.appending(path: "\(id.uuidString)-\(fileName)")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: url, to: destination)
        return try makeItem(
            id: id,
            fileName: fileName,
            mimeType: mimeType,
            source: source,
            destination: destination
        )
    }

    private func makeItem(
        id: UUID,
        fileName: String,
        mimeType: String,
        source: AutonomoUploadSource,
        destination: URL
    ) throws -> LocalIntakeItem {
        let byteSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let now = Date()
        let relativePath = destination.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        return LocalIntakeItem(
            id: id,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: byteSize,
            relativePath: relativePath,
            source: source,
            status: .pending,
            idempotencyKey: AutonomoDocumentAssetSupport.idempotencyKey(prefix: idempotencyKeyPrefix, id: id),
            createdAt: now,
            updatedAt: now,
            uploadId: nil,
            documentId: nil,
            queueItemId: nil,
            attemptCount: 0,
            errorMessage: nil
        )
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: uploadsURL, withIntermediateDirectories: true)
    }

    static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "AutonomoAV", directoryHint: .isDirectory)
    }
}

private extension JSONEncoder {
    static let autonomo: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let autonomo: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
