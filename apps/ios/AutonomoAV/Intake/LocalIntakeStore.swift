import Foundation
import Observation
import UniformTypeIdentifiers

enum LocalIntakeStatus: String, Codable, Equatable {
    case pending
    case uploading
    case uploaded
    case failed

    var displayText: String {
        switch self {
        case .pending:
            return L10n.string("intake.pending")
        case .uploading:
            return L10n.string("intake.uploading")
        case .uploaded:
            return L10n.string("intake.status.uploaded")
        case .failed:
            return L10n.string("intake.failed")
        }
    }
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
}

struct ScannedDocumentPage: Equatable {
    let fileName: String
    let data: Data
}

struct LocalIntakePersistence {
    let rootURL: URL
    private let fileManager: FileManager

    init(
        rootURL: URL = LocalIntakePersistence.defaultRootURL(),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
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

        try ensureDirectories()
        let id = UUID()
        let fileName = url.lastPathComponent.isEmpty ? "document-\(id.uuidString).pdf" : url.lastPathComponent
        guard let mimeType = Self.mimeType(for: url) else {
            throw AutonomoAPIClientError.unsupportedFile
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

    func storeScannedPage(_ page: ScannedDocumentPage, source: AutonomoUploadSource = .iosCamera) throws -> LocalIntakeItem {
        try ensureDirectories()
        let id = UUID()
        let destination = uploadsURL.appending(path: "\(id.uuidString)-\(page.fileName)")
        try page.data.write(to: destination, options: [.atomic])
        return try makeItem(
            id: id,
            fileName: page.fileName,
            mimeType: "image/jpeg",
            source: source,
            destination: destination
        )
    }

    func fileURL(for item: LocalIntakeItem) -> URL {
        rootURL.appending(path: item.relativePath)
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
            idempotencyKey: "ios-\(id.uuidString)",
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

    static func mimeType(for url: URL) -> String? {
        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .pdf) || type.conforms(to: .image) {
            return type.preferredMIMEType ?? fallbackMimeType(forExtension: url.pathExtension)
        }
        return fallbackMimeType(forExtension: url.pathExtension)
    }

    static func fallbackMimeType(forExtension pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "pdf":
            return "application/pdf"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        case "tif", "tiff":
            return "image/tiff"
        default:
            return nil
        }
    }

    static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "AutonomoAV", directoryHint: .isDirectory)
    }
}

@MainActor
@Observable
final class IntakeStore {
    private let client: AutonomoAPIClient
    private let persistence: LocalIntakePersistence

    private(set) var localItems: [LocalIntakeItem]
    private(set) var remoteDocuments: [AutonomoDocumentSummary] = []
    private(set) var isRefreshingRemoteDocuments = false
    private(set) var isUploading = false
    var lastErrorMessage: String?

    init(client: AutonomoAPIClient, persistence: LocalIntakePersistence = LocalIntakePersistence()) {
        self.client = client
        self.persistence = persistence
        self.localItems = persistence.loadItems().sorted { $0.createdAt > $1.createdAt }
    }

    var pendingOrFailedItems: [LocalIntakeItem] {
        localItems.filter { $0.status == .pending || $0.status == .failed || $0.status == .uploading }
    }

    var needsReviewCount: Int {
        remoteDocuments.filter { $0.status == .needsReview }.count
    }

    func importFiles(from urls: [URL], source: AutonomoUploadSource = .iosFiles) async {
        do {
            let items = try urls.map { try persistence.copyImportedFile(from: $0, source: source) }
            localItems.insert(contentsOf: items, at: 0)
            try save()
            await uploadPending()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func importScannedPages(_ pages: [ScannedDocumentPage]) async {
        do {
            let items = try pages.map { try persistence.storeScannedPage($0) }
            localItems.insert(contentsOf: items, at: 0)
            try save()
            await uploadPending()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func retry(_ item: LocalIntakeItem) async {
        updateItem(id: item.id) { current in
            current.status = .pending
            current.errorMessage = nil
            current.updatedAt = Date()
        }
        try? save()
        await uploadPending()
    }

    func uploadPending() async {
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }

        for item in localItems where item.status == .pending {
            await upload(item)
        }
    }

    func refreshRemoteDocuments() async {
        guard client.isConfigured else {
            lastErrorMessage = L10n.string("account.apiMissing")
            return
        }

        isRefreshingRemoteDocuments = true
        defer { isRefreshingRemoteDocuments = false }

        do {
            remoteDocuments = try await client.fetchRecentDocuments()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func upload(_ item: LocalIntakeItem) async {
        updateItem(id: item.id) { current in
            current.status = .uploading
            current.attemptCount += 1
            current.updatedAt = Date()
            current.errorMessage = nil
        }
        try? save()

        do {
            let current = localItems.first { $0.id == item.id } ?? item
            let fileURL = persistence.fileURL(for: current)
            let data = try Data(contentsOf: fileURL)
            let prepared = try await client.prepareUpload(AutonomoPrepareUploadRequest(
                fileName: current.fileName,
                mimeType: current.mimeType,
                byteSize: data.count,
                source: current.source,
                idempotencyKey: current.idempotencyKey,
                clientCreatedAt: current.createdAt
            ))
            try await client.uploadData(data, uploadId: prepared.uploadId, mimeType: current.mimeType)
            let completed = try await client.completeUpload(
                uploadId: prepared.uploadId,
                source: current.source,
                idempotencyKey: current.idempotencyKey
            )

            updateItem(id: item.id) { uploaded in
                uploaded.status = .uploaded
                uploaded.uploadId = prepared.uploadId
                uploaded.documentId = completed.documentId
                uploaded.queueItemId = completed.queueItemId
                uploaded.updatedAt = Date()
                uploaded.errorMessage = nil
            }
            try save()
            await refreshRemoteDocuments()
        } catch {
            updateItem(id: item.id) { failed in
                failed.status = .failed
                failed.errorMessage = error.localizedDescription
                failed.updatedAt = Date()
            }
            try? save()
        }
    }

    private func updateItem(id: UUID, mutate: (inout LocalIntakeItem) -> Void) {
        guard let index = localItems.firstIndex(where: { $0.id == id }) else { return }
        mutate(&localItems[index])
        localItems.sort { $0.createdAt > $1.createdAt }
    }

    private func save() throws {
        try persistence.saveItems(localItems)
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
