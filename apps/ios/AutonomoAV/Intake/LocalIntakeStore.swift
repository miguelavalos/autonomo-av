import Foundation
import Observation

extension LocalIntakeStatus {
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

struct ScannedDocumentPage: Equatable {
    let fileName: String
    let data: Data
}

extension LocalIntakePersistence {
    func storeScannedPage(_ page: ScannedDocumentPage, source: AutonomoUploadSource = .iosCamera) throws -> LocalIntakeItem {
        try storeData(
            page.data,
            fileName: page.fileName,
            mimeType: "image/jpeg",
            source: source
        )
    }
}

@MainActor
@Observable
final class IntakeStore {
    private let client: AutonomoAPIClient
    private let uploader: AutonomoPreparedDocumentUploader
    private let persistence: LocalIntakePersistence
    private let sharedInbox: SharedIntakeInbox
    private let canUseIntakeProvider: () -> Bool

    private(set) var localItems: [LocalIntakeItem]
    private(set) var remoteDocuments: [AutonomoDocumentSummary] = []
    private(set) var isImportingSharedInbox = false
    private(set) var isRefreshingRemoteDocuments = false
    private(set) var isUploading = false
    var lastErrorMessage: String?
    private var workspaceBootstrapped = false

    init(
        client: AutonomoAPIClient,
        persistence: LocalIntakePersistence = LocalIntakePersistence(),
        sharedInbox: SharedIntakeInbox = SharedIntakeInbox(),
        canUseIntakeProvider: @escaping () -> Bool = { false }
    ) {
        self.client = client
        self.uploader = AutonomoPreparedDocumentUploader(backend: client)
        self.persistence = persistence
        self.sharedInbox = sharedInbox
        self.canUseIntakeProvider = canUseIntakeProvider

        let normalizedItems = AutonomoLocalIntakeQueue.normalizeLoadedItems(persistence.loadItems())
        self.localItems = normalizedItems.items.sorted { $0.createdAt > $1.createdAt }
        if normalizedItems.didChange {
            try? persistence.saveItems(self.localItems)
        }
    }

    var pendingOrFailedItems: [LocalIntakeItem] {
        localItems.filter { $0.status == .pending || $0.status == .failed || $0.status == .uploading }
    }

    var needsReviewCount: Int {
        remoteDocuments.filter { $0.status == .needsReview }.count
    }

    func importFiles(from urls: [URL], source: AutonomoUploadSource = .iosFiles) async {
        guard !urls.isEmpty else { return }
        guard requireIntakeAccess() else { return }

        do {
            var importedItems: [LocalIntakeItem] = []
            var rejectedCount = 0
            var failedCount = 0

            for url in urls {
                do {
                    importedItems.append(try persistence.copyImportedFile(from: url, source: source))
                } catch {
                    if (error as? AutonomoDocumentIntakeError)?.isDeterministicRejection == true {
                        rejectedCount += 1
                    } else {
                        failedCount += 1
                    }
                }
            }

            if !importedItems.isEmpty {
                localItems.insert(contentsOf: importedItems, at: 0)
                try save()
            }

            if failedCount > 0 || rejectedCount > 0 {
                lastErrorMessage = L10n.string(
                    "intake.import.partialFailure",
                    failedCount,
                    rejectedCount
                )
            } else if !importedItems.isEmpty {
                lastErrorMessage = nil
            }

            if !importedItems.isEmpty {
                await uploadPending()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func importScannedPages(_ pages: [ScannedDocumentPage]) async {
        guard !pages.isEmpty else { return }
        guard requireIntakeAccess() else { return }

        do {
            let items = try pages.map { try persistence.storeScannedPage($0) }
            localItems.insert(contentsOf: items, at: 0)
            try save()
            await uploadPending()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func importSharedInboxItems() async {
        guard requireIntakeAccess() else { return }
        guard !isImportingSharedInbox else { return }
        isImportingSharedInbox = true
        defer { isImportingSharedInbox = false }

        do {
            let urls = try sharedInbox.pendingFileURLs()
            guard !urls.isEmpty else { return }

            var importedItems: [LocalIntakeItem] = []
            var rejectedCount = 0
            var failedCount = 0

            for url in urls {
                do {
                    let item = try persistence.copySharedInboxFile(from: url)
                    try sharedInbox.removePendingFile(at: url)
                    importedItems.append(item)
                } catch {
                    if (error as? AutonomoDocumentIntakeError)?.isDeterministicRejection == true {
                        rejectedCount += 1
                        try? sharedInbox.removePendingFile(at: url)
                    } else {
                        failedCount += 1
                    }
                }
            }

            if !importedItems.isEmpty {
                localItems.insert(contentsOf: importedItems, at: 0)
                try save()
                await uploadPending()
            }

            if failedCount > 0 || rejectedCount > 0 {
                lastErrorMessage = L10n.string(
                    "intake.shareImport.partialFailure",
                    failedCount,
                    rejectedCount
                )
            } else if !importedItems.isEmpty {
                lastErrorMessage = nil
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func retry(_ item: LocalIntakeItem) async {
        guard requireIntakeAccess() else { return }
        updateItem(id: item.id) { current in
            current.markPendingForRetry()
        }
        try? save()
        await uploadPending()
    }

    func uploadPending() async {
        guard requireIntakeAccess() else { return }
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }

        do {
            try await bootstrapWorkspaceIfNeeded()
        } catch {
            lastErrorMessage = error.localizedDescription
            return
        }

        for item in localItems where item.status == .pending {
            await upload(item)
        }
    }

    func refreshRemoteDocuments() async {
        guard requireIntakeAccess() else { return }
        guard client.isConfigured else {
            lastErrorMessage = L10n.string("account.apiMissing")
            return
        }

        isRefreshingRemoteDocuments = true
        defer { isRefreshingRemoteDocuments = false }

        do {
            try await bootstrapWorkspaceIfNeeded()
            remoteDocuments = try await client.fetchRecentDocuments()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearBackendStateForLockedAccess() {
        remoteDocuments = []
        workspaceBootstrapped = false
    }

    private func upload(_ item: LocalIntakeItem) async {
        updateItem(id: item.id) { current in
            current.markUploading()
        }
        try? save()

        do {
            let current = localItems.first { $0.id == item.id } ?? item
            let fileURL = persistence.fileURL(for: current)
            let data = try Data(contentsOf: fileURL)
            let uploadResult = try await uploader.upload(AutonomoDocumentUploadPayload(
                originalFilename: current.fileName,
                contentType: current.mimeType,
                data: data,
                source: current.source
            ))

            updateItem(id: item.id) { uploaded in
                uploaded.markUploaded(uploadResult)
            }
            try save()
            await refreshRemoteDocuments()
        } catch {
            updateItem(id: item.id) { failed in
                failed.markFailed(error.localizedDescription)
            }
            try? save()
        }
    }

    private func updateItem(id: UUID, mutate: (inout LocalIntakeItem) -> Void) {
        guard let index = localItems.firstIndex(where: { $0.id == id }) else { return }
        mutate(&localItems[index])
        localItems.sort { $0.createdAt > $1.createdAt }
    }

    private func bootstrapWorkspaceIfNeeded() async throws {
        guard !workspaceBootstrapped else { return }
        guard client.isConfigured else {
            throw AutonomoAPIClientError.missingBaseURL
        }
        _ = try await client.bootstrapWorkspace()
        workspaceBootstrapped = true
    }

    private func save() throws {
        try persistence.saveItems(localItems)
    }

    private func requireIntakeAccess() -> Bool {
        guard canUseIntakeProvider() else {
            lastErrorMessage = L10n.string("intake.proRequired")
            return false
        }
        return true
    }
}
