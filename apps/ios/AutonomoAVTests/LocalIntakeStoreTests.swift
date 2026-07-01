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
}
