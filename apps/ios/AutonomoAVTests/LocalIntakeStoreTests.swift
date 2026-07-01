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

        XCTAssertEqual(persistence.loadItems(), [item])
        XCTAssertEqual(item.mimeType, "application/pdf")
        XCTAssertEqual(item.source, .iosFiles)
        XCTAssertEqual(item.status, .pending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistence.fileURL(for: item).path))
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
            XCTAssertEqual(error as? AutonomoAPIClientError, .unsupportedFile)
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
            XCTAssertEqual(error as? AutonomoAPIClientError, .unsupportedFile)
        }
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
