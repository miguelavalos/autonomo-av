import XCTest
@testable import AutonomoAV

final class LocalIntakeStoreTests: XCTestCase {
    func testPersistenceRoundTripsPendingItem() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(rootURL: rootURL)
        let sourceURL = rootURL.appending(path: "source.pdf")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: sourceURL)

        let item = try persistence.copyImportedFile(from: sourceURL, source: .iosFiles)
        try persistence.saveItems([item])

        let loadedItem = try XCTUnwrap(persistence.loadItems().first)
        XCTAssertEqual(loadedItem.id, item.id)
        XCTAssertEqual(loadedItem.fileName, item.fileName)
        XCTAssertEqual(loadedItem.mimeType, item.mimeType)
        XCTAssertEqual(loadedItem.byteSize, item.byteSize)
        XCTAssertEqual(loadedItem.relativePath, item.relativePath)
        XCTAssertEqual(loadedItem.source, item.source)
        XCTAssertEqual(loadedItem.status, item.status)
        XCTAssertEqual(loadedItem.idempotencyKey, item.idempotencyKey)
        XCTAssertEqual(loadedItem.createdAt.timeIntervalSince1970, item.createdAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loadedItem.updatedAt.timeIntervalSince1970, item.updatedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loadedItem.uploadId, item.uploadId)
        XCTAssertEqual(loadedItem.documentId, item.documentId)
        XCTAssertEqual(loadedItem.queueItemId, item.queueItemId)
        XCTAssertEqual(loadedItem.attemptCount, item.attemptCount)
        XCTAssertEqual(loadedItem.errorMessage, item.errorMessage)
        XCTAssertEqual(item.mimeType, "application/pdf")
        XCTAssertEqual(item.source, .iosFiles)
        XCTAssertEqual(item.status, .pending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistence.fileURL(for: item).path))
    }

    @MainActor
    func testIntakeStoreRestoresUploadingItemsAsPending() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(rootURL: rootURL)
        let sourceURL = rootURL.appending(path: "source.pdf")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: sourceURL)

        var item = try persistence.copyImportedFile(from: sourceURL, source: .iosFiles)
        item.status = .uploading
        item.errorMessage = "Interrupted"
        try persistence.saveItems([item])

        let store = IntakeStore(
            client: AutonomoAPIClient(baseURLProvider: { nil }, tokenProvider: { nil }, retryPolicy: .disabled),
            persistence: persistence,
            sharedInbox: SharedIntakeInbox(rootURL: nil)
        )

        let restoredItem = try XCTUnwrap(store.localItems.first)
        XCTAssertEqual(restoredItem.status, .pending)
        XCTAssertNil(restoredItem.errorMessage)

        let persistedItem = try XCTUnwrap(persistence.loadItems().first)
        XCTAssertEqual(persistedItem.status, .pending)
        XCTAssertNil(persistedItem.errorMessage)
    }

    func testUnsupportedFileTypeIsRejected() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(rootURL: rootURL)
        let sourceURL = rootURL.appending(path: "source.exe")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("not supported".utf8).write(to: sourceURL)

        XCTAssertThrowsError(try persistence.copyImportedFile(from: sourceURL, source: .iosFiles)) { error in
            XCTAssertEqual(error as? AutonomoDocumentIntakeError, .unsupportedFile)
        }
    }

    func testUnsupportedImageMimeTypeIsRejected() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(rootURL: rootURL)
        let sourceURL = rootURL.appending(path: "source.gif")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("not supported".utf8).write(to: sourceURL)

        XCTAssertThrowsError(try persistence.copyImportedFile(from: sourceURL, source: .iosFiles)) { error in
            XCTAssertEqual(error as? AutonomoDocumentIntakeError, .unsupportedFile)
        }
    }

    func testStoreDataRejectsUnsupportedMimeType() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(rootURL: rootURL)

        XCTAssertThrowsError(try persistence.storeData(
            Data("gif".utf8),
            fileName: "source.gif",
            mimeType: "image/gif",
            source: .iosFiles
        )) { error in
            XCTAssertEqual(error as? AutonomoDocumentIntakeError, .unsupportedFile)
        }
        XCTAssertTrue(persistence.loadItems().isEmpty)
    }

    func testTooLargeFileIsRejectedBeforeEnteringQueue() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(rootURL: rootURL)
        let sourceURL = rootURL.appending(path: "oversized.pdf")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sourceURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sourceURL)
        try handle.truncate(atOffset: UInt64(AutonomoDocumentAssetSupport.maxUploadByteSize + 1))
        try handle.close()

        XCTAssertThrowsError(try persistence.copyImportedFile(from: sourceURL, source: .iosFiles)) { error in
            XCTAssertEqual(error as? AutonomoDocumentIntakeError, .uploadTooLarge)
        }
        XCTAssertTrue(persistence.loadItems().isEmpty)
    }

    @MainActor
    func testSharedInboxDropsTooLargeFilesBeforeQueue() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }

        let pendingURL = rootURL.appending(path: "ShareInbox/Pending", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        let sharedURL = pendingURL.appending(path: "oversized.pdf")
        fileManager.createFile(atPath: sharedURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sharedURL)
        try handle.truncate(atOffset: UInt64(AutonomoDocumentAssetSupport.maxUploadByteSize + 1))
        try handle.close()

        let persistence = LocalIntakePersistence(rootURL: rootURL.appending(path: "LocalQueue", directoryHint: .isDirectory))
        let store = IntakeStore(
            client: AutonomoAPIClient(baseURLProvider: { nil }, tokenProvider: { nil }, retryPolicy: .disabled),
            persistence: persistence,
            sharedInbox: SharedIntakeInbox(rootURL: rootURL, fileManager: fileManager)
        )

        await store.importSharedInboxItems()

        XCTAssertTrue(store.localItems.isEmpty)
        XCTAssertFalse(fileManager.fileExists(atPath: sharedURL.path))
        XCTAssertEqual(try SharedIntakeInbox(rootURL: rootURL, fileManager: fileManager).pendingFileURLs(), [])
    }

    func testCopySharedInboxFileMarksShareSource() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(rootURL: rootURL)
        let sharedURL = rootURL.appending(path: "shared-invoice.pdf")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: sharedURL)

        let item = try persistence.copySharedInboxFile(from: sharedURL)

        XCTAssertEqual(item.fileName, "shared-invoice.pdf")
        XCTAssertEqual(item.mimeType, "application/pdf")
        XCTAssertEqual(item.source, .iosShare)
        XCTAssertEqual(item.status, .pending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistence.fileURL(for: item).path))
    }

    func testPersistenceCanUseMacOSIntakeDefaults() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(
            rootURL: rootURL,
            idempotencyKeyPrefix: "macos",
            sharedInboxSource: .macosShare
        )
        let sharedURL = rootURL.appending(path: "shared-invoice.pdf")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: sharedURL)

        let item = try persistence.copySharedInboxFile(from: sharedURL)

        XCTAssertEqual(item.source, .macosShare)
        XCTAssertTrue(item.idempotencyKey.hasPrefix("macos-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistence.fileURL(for: item).path))
    }

    func testSharedIntakeInboxListsAndRemovesPendingFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let inbox = SharedIntakeInbox(rootURL: rootURL)
        let pendingURL = try XCTUnwrap(inbox.pendingURL)
        try FileManager.default.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        let firstURL = pendingURL.appending(path: "first.pdf")
        let secondURL = pendingURL.appending(path: "second.jpg")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)

        let pendingFileNames = try inbox.pendingFileURLs().map(\.lastPathComponent)

        XCTAssertEqual(Set(pendingFileNames), ["first.pdf", "second.jpg"])
        try inbox.removePendingFile(at: firstURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
    }
}
