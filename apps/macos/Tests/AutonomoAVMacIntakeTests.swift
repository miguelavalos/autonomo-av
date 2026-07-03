import AppKit
import AccountAV
import XCTest
import UniformTypeIdentifiers
@testable import AutonomoAVMac

final class AutonomoAVMacIntakeTests: XCTestCase {
    @MainActor
    func testLocalIntakeRootCanBeOverriddenForSmokeRuns() {
        let key = "AUTONOMOAV_LOCAL_INTAKE_ROOT_URL"
        let previousValue = getenv(key).map { String(cString: $0) }
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVMacSmokeRoot-\(UUID().uuidString)", directoryHint: .isDirectory)

        setenv(key, rootURL.path, 1)
        defer {
            if let previousValue {
                setenv(key, previousValue, 1)
            } else {
                unsetenv(key)
            }
        }

        XCTAssertEqual(AppConfig.localIntakeRootURL.path, rootURL.path)
    }

    func testFilePickerAllowsBackendSupportedDocumentTypes() {
        let mimeTypes = Set(AutonomoAVMacFilePicker.allowedContentTypes.compactMap(\.preferredMIMEType))

        XCTAssertTrue(mimeTypes.contains("application/pdf"))
        XCTAssertTrue(mimeTypes.contains("image/jpeg"))
        XCTAssertTrue(mimeTypes.contains("image/png"))
        XCTAssertTrue(mimeTypes.contains("image/webp"))
        XCTAssertTrue(mimeTypes.contains("image/heic") || mimeTypes.contains("image/heif"))
    }

    func testMacAppRegistersFinderOpenWithDocumentTypes() throws {
        let documentTypes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let contentTypes = Set(documentTypes.flatMap { documentType in
            documentType["LSItemContentTypes"] as? [String] ?? []
        })

        XCTAssertTrue(contentTypes.contains(UTType.pdf.identifier))
        XCTAssertTrue(contentTypes.contains(UTType.jpeg.identifier))
        XCTAssertTrue(contentTypes.contains(UTType.png.identifier))
        XCTAssertTrue(contentTypes.contains("org.webmproject.webp"))
        XCTAssertTrue(contentTypes.contains("public.heic"))
        XCTAssertTrue(contentTypes.contains("public.heif"))
    }

    func testMacAppRegistersFileService() throws {
        let services = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSServices") as? [[String: Any]])
        let service = try XCTUnwrap(services.first)
        let menuItem = try XCTUnwrap(service["NSMenuItem"] as? [String: String])
        let sendFileTypes = Set(try XCTUnwrap(service["NSSendFileTypes"] as? [String]))

        XCTAssertEqual(menuItem["default"], "Send to Autonomo AV")
        XCTAssertEqual(service["NSMessage"] as? String, "sendFilesToAutonomoAV")
        XCTAssertNotNil(service["NSRequiredContext"] as? [String: Any])
        XCTAssertEqual(service["NSRestricted"] as? Bool, false)
        XCTAssertTrue(sendFileTypes.contains(UTType.pdf.identifier))
        XCTAssertTrue(sendFileTypes.contains(UTType.jpeg.identifier))
        XCTAssertTrue(sendFileTypes.contains(UTType.png.identifier))
        XCTAssertTrue(sendFileTypes.contains("org.webmproject.webp"))
        XCTAssertTrue(sendFileTypes.contains("public.heic"))
        XCTAssertTrue(sendFileTypes.contains("public.heif"))
    }

    func testMacShareExtensionIsEmbeddedAndRegistersShareService() throws {
        let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let extensionBundleURL = plugInsURL.appending(path: "Autonomo AV Inbox.appex", directoryHint: .isDirectory)
        let extensionBundle = try XCTUnwrap(Bundle(url: extensionBundleURL))
        let extensionDictionary = try XCTUnwrap(extensionBundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])
        let attributes = try XCTUnwrap(extensionDictionary["NSExtensionAttributes"] as? [String: Any])
        let activationRule = try XCTUnwrap(attributes["NSExtensionActivationRule"] as? [String: Any])

        XCTAssertEqual(extensionDictionary["NSExtensionPointIdentifier"] as? String, "com.apple.share-services")
        XCTAssertEqual(activationRule["NSExtensionActivationSupportsFileWithMaxCount"] as? Int, 10)
        XCTAssertEqual(activationRule["NSExtensionActivationSupportsImageWithMaxCount"] as? Int, 10)
        XCTAssertNotNil(extensionBundle.object(forInfoDictionaryKey: "AUTONOMOAV_APP_GROUP_IDENTIFIER") as? String)
    }

    func testFileServiceProviderReadsFileURLsFromPasteboard() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVMacServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceURL = rootURL.appending(path: "service.pdf")
        try Data("pdf".utf8).write(to: sourceURL)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("AutonomoAVMacServiceTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceURL as NSURL]))

        XCTAssertEqual(AutonomoAVMacFileServiceProvider.fileURLs(from: pasteboard), [sourceURL])
    }

    func testShareAttachmentAcceptsFileURLProviders() throws {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier, fileOptions: [], visibility: .all) { completion in
            completion(URL(fileURLWithPath: "/tmp/invoice.pdf"), false, nil)
            return nil
        }

        let attachment = try XCTUnwrap(AutonomoAVShareAttachment(provider: provider))

        XCTAssertTrue(attachment.isFileURL)
        XCTAssertEqual(attachment.typeIdentifier, UTType.fileURL.identifier)
    }

    func testShareAttachmentUsesConcreteSupportedImageType() throws {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(Data("png".utf8), nil)
            return nil
        }

        let attachment = try XCTUnwrap(AutonomoAVShareAttachment(provider: provider))

        XCTAssertFalse(attachment.isFileURL)
        XCTAssertEqual(attachment.typeIdentifier, UTType.png.identifier)
    }

    func testShareAttachmentPrefersConcretePayloadTypeOverFileURL() throws {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier, fileOptions: [], visibility: .all) { completion in
            completion(URL(fileURLWithPath: "/tmp/invoice.pdf"), false, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.pdf.identifier, visibility: .all) { completion in
            completion(Data("pdf".utf8), nil)
            return nil
        }

        let attachment = try XCTUnwrap(AutonomoAVShareAttachment(provider: provider))

        XCTAssertFalse(attachment.isFileURL)
        XCTAssertEqual(attachment.typeIdentifier, UTType.pdf.identifier)
    }

    func testShareAttachmentRejectsUnsupportedGenericImages() {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.tiff.identifier, visibility: .all) { completion in
            completion(Data("tiff".utf8), nil)
            return nil
        }

        XCTAssertNil(AutonomoAVShareAttachment(provider: provider))
    }

    func testShareExtensionInboxWriterCopiesSupportedFileURLs() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVMacShareFileURLTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }
        let pendingURL = rootURL.appending(path: "Pending", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)

        let sourceURL = rootURL.appending(path: "receipt.webp")
        try Data("webp".utf8).write(to: sourceURL)

        try AutonomoAVShareExtensionInboxWriter.copyFileURL(
            from: sourceURL,
            suggestedName: nil,
            to: pendingURL,
            fileManager: fileManager
        )

        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: pendingURL.path), ["receipt.webp"])

        let unsupportedURL = rootURL.appending(path: "notes.txt")
        try Data("text".utf8).write(to: unsupportedURL)
        XCTAssertThrowsError(try AutonomoAVShareExtensionInboxWriter.copyFileURL(
            from: unsupportedURL,
            suggestedName: nil,
            to: pendingURL,
            fileManager: fileManager
        )) { error in
            guard case AutonomoAVShareExtensionInboxWriter.InboxError.unsupportedFile = error else {
                return XCTFail("Expected unsupportedFile, got \(error)")
            }
        }
    }

    func testTooLargeFilesAreRejectedBeforeEnteringMacQueue() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVMacTooLargeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(
            rootURL: rootURL,
            idempotencyKeyPrefix: "macos",
            sharedInboxSource: .macosShare
        )
        let sourceURL = rootURL.appending(path: "oversized.pdf")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sourceURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sourceURL)
        try handle.truncate(atOffset: UInt64(AutonomoDocumentAssetSupport.maxUploadByteSize + 1))
        try handle.close()

        XCTAssertThrowsError(try persistence.copyImportedFile(from: sourceURL, source: .macosFiles)) { error in
            XCTAssertEqual(error as? AutonomoDocumentIntakeError, .uploadTooLarge)
        }
        XCTAssertTrue(persistence.loadItems().isEmpty)
    }

    func testStoreDataRejectsUnsupportedMimeTypeBeforeEnteringMacQueue() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVMacUnsupportedDataTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(
            rootURL: rootURL,
            idempotencyKeyPrefix: "macos",
            sharedInboxSource: .macosShare
        )

        XCTAssertThrowsError(try persistence.storeData(
            Data("gif".utf8),
            fileName: "source.gif",
            mimeType: "image/gif",
            source: .macosFiles
        )) { error in
            XCTAssertEqual(error as? AutonomoDocumentIntakeError, .unsupportedFile)
        }
        XCTAssertTrue(persistence.loadItems().isEmpty)
    }

    func testShareExtensionInboxWriterRejectsTooLargeFiles() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVMacShareTooLargeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceURL = rootURL.appending(path: "oversized.pdf")
        fileManager.createFile(atPath: sourceURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sourceURL)
        try handle.truncate(atOffset: UInt64(AutonomoDocumentAssetSupport.maxUploadByteSize + 1))
        try handle.close()
        let pendingURL = rootURL.appending(path: "Pending", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try AutonomoAVShareExtensionInboxWriter.copyFileURL(
            from: sourceURL,
            suggestedName: nil,
            to: pendingURL,
            fileManager: fileManager
        )) { error in
            guard case AutonomoAVShareExtensionInboxWriter.InboxError.uploadTooLarge = error else {
                return XCTFail("Expected uploadTooLarge, got \(error)")
            }
        }
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: pendingURL.path), [])
    }

    @MainActor
    func testMacSharedInboxDropsTooLargeFilesBeforeQueue() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVMacSharedInboxTooLargeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }

        let pendingURL = rootURL.appending(path: "ShareInbox/Pending", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        let sharedURL = pendingURL.appending(path: "oversized.pdf")
        fileManager.createFile(atPath: sharedURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sharedURL)
        try handle.truncate(atOffset: UInt64(AutonomoDocumentAssetSupport.maxUploadByteSize + 1))
        try handle.close()

        let model = AutonomoAVMacModel(
            persistence: LocalIntakePersistence(
                rootURL: rootURL.appending(path: "LocalQueue", directoryHint: .isDirectory),
                fileManager: fileManager,
                idempotencyKeyPrefix: "macos",
                sharedInboxSource: .macosShare
            ),
            sharedInbox: SharedIntakeInbox(rootURL: rootURL, fileManager: fileManager)
        )
        model.enableProAccessForTesting()

        await model.importSharedInboxItems()

        XCTAssertTrue(model.localItems.isEmpty)
        XCTAssertFalse(fileManager.fileExists(atPath: sharedURL.path))
        XCTAssertEqual(try SharedIntakeInbox(rootURL: rootURL, fileManager: fileManager).pendingFileURLs(), [])
    }

    @MainActor
    func testMacModelDoesNotTreatLastKnownUserAsSignedInForUploads() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVMacLastKnownGateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }

        let suiteName = "AutonomoAVMacLastKnownGateTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let lastKnownUser = AutonomoAccountUser(
            id: "apps-user-1",
            displayName: "Apps User",
            emailAddress: "owner@example.test"
        )
        userDefaults.set(
            try JSONEncoder().encode(lastKnownUser),
            forKey: "autonomoav.account.lastKnownUser"
        )

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceURL = rootURL.appending(path: "invoice.pdf")
        try Data("pdf".utf8).write(to: sourceURL)

        let persistence = LocalIntakePersistence(
            rootURL: rootURL.appending(path: "LocalQueue", directoryHint: .isDirectory),
            fileManager: fileManager,
            idempotencyKeyPrefix: "macos",
            sharedInboxSource: .macosShare
        )
        let item = try persistence.copyImportedFile(from: sourceURL, source: .macosFiles)
        try persistence.saveItems([item])

        let accountService = TemporarilyUnavailableAccountService()
        let model = AutonomoAVMacModel(
            accountService: accountService,
            persistence: persistence,
            sharedInbox: SharedIntakeInbox(rootURL: rootURL, fileManager: fileManager),
            userDefaults: userDefaults
        )

        await model.restoreAccount()
        await model.uploadPending()

        XCTAssertEqual(model.currentAccountUser, lastKnownUser)
        XCTAssertFalse(model.accountIsSignedIn)
        XCTAssertEqual(model.localItems.first?.status, .pending)
        XCTAssertEqual(model.lastErrorMessage, "Sign in with Account AV before sending documents.")
        XCTAssertEqual(accountService.tokenRequestCount, 0)
    }

    @MainActor
    func testMacModelDoesNotStageFilesWithoutProAccess() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVMacProGateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceURL = rootURL.appending(path: "invoice.pdf")
        try Data("pdf".utf8).write(to: sourceURL)

        let persistence = LocalIntakePersistence(
            rootURL: rootURL.appending(path: "LocalQueue", directoryHint: .isDirectory),
            fileManager: fileManager,
            idempotencyKeyPrefix: "macos",
            sharedInboxSource: .macosShare
        )
        let model = AutonomoAVMacModel(
            persistence: persistence,
            sharedInbox: SharedIntakeInbox(rootURL: rootURL, fileManager: fileManager)
        )

        await model.importFiles([sourceURL], source: .macosFiles)

        XCTAssertTrue(model.localItems.isEmpty)
        XCTAssertTrue(persistence.loadItems().isEmpty)
        XCTAssertEqual(model.lastErrorMessage, "Sign in with Account AV before sending documents.")
    }

    func testMacPersistenceImportsWithMacOSDefaults() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AutonomoAVMacTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = LocalIntakePersistence(
            rootURL: rootURL,
            idempotencyKeyPrefix: "macos",
            sharedInboxSource: .macosShare
        )
        let sourceURL = rootURL.appending(path: "invoice.pdf")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: sourceURL)

        let item = try persistence.copyImportedFile(from: sourceURL, source: .macosDragDrop)
        try persistence.saveItems([item])

        let loadedItem = try XCTUnwrap(persistence.loadItems().first)
        XCTAssertEqual(loadedItem.source, .macosDragDrop)
        XCTAssertTrue(loadedItem.idempotencyKey.hasPrefix("macos-"))
        XCTAssertEqual(loadedItem.mimeType, "application/pdf")
        XCTAssertEqual(loadedItem.status, .pending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistence.fileURL(for: loadedItem).path))
    }

    func testSharedInboxImportsAsMacOSShare() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVMacSharedInboxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }

        let pendingURL = rootURL.appending(path: "ShareInbox/Pending", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        let sharedFileURL = pendingURL.appending(path: "receipt.pdf")
        try Data("pdf".utf8).write(to: sharedFileURL)

        let inbox = SharedIntakeInbox(rootURL: rootURL, fileManager: fileManager)
        let persistence = LocalIntakePersistence(
            rootURL: rootURL.appending(path: "LocalQueue", directoryHint: .isDirectory),
            fileManager: fileManager,
            idempotencyKeyPrefix: "macos",
            sharedInboxSource: .macosShare
        )

        let pendingFile = try XCTUnwrap(try inbox.pendingFileURLs().first)
        let item = try persistence.copySharedInboxFile(from: pendingFile)
        try inbox.removePendingFile(at: pendingFile)

        XCTAssertEqual(item.source, .macosShare)
        XCTAssertEqual(item.mimeType, "application/pdf")
        XCTAssertTrue(item.idempotencyKey.hasPrefix("macos-"))
        XCTAssertFalse(fileManager.fileExists(atPath: sharedFileURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: persistence.fileURL(for: item).path))
    }

    func testShareExtensionInboxWriterSanitizesNamesAndAvoidsCollisions() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVMacShareWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try AutonomoAVShareExtensionInboxWriter.writeData(
            Data("first".utf8),
            suggestedName: "Vendor:2026/receipt",
            typeIdentifier: UTType.pdf.identifier,
            to: rootURL,
            fileManager: fileManager
        )
        try AutonomoAVShareExtensionInboxWriter.writeData(
            Data("second".utf8),
            suggestedName: "Vendor:2026/receipt",
            typeIdentifier: UTType.pdf.identifier,
            to: rootURL,
            fileManager: fileManager
        )

        let fileNames = try fileManager.contentsOfDirectory(atPath: rootURL.path).sorted()
        XCTAssertEqual(fileNames, ["Vendor-2026-receipt-2.pdf", "Vendor-2026-receipt.pdf"])
    }

    func testShareExtensionInboxWriterKeepsConcretePayloadExtensions() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVMacSharePayloadTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try AutonomoAVShareExtensionInboxWriter.writeData(
            Data("png".utf8),
            suggestedName: nil,
            typeIdentifier: UTType.png.identifier,
            to: rootURL,
            fileManager: fileManager
        )

        let savedFileName = try XCTUnwrap(try fileManager.contentsOfDirectory(atPath: rootURL.path).first)
        XCTAssertEqual((savedFileName as NSString).pathExtension, "png")
    }

    func testShareExtensionInboxWriterRejectsGenericImagePayloads() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appending(path: "AutonomoAVMacShareGenericImageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try AutonomoAVShareExtensionInboxWriter.writeData(
            Data("image".utf8),
            suggestedName: nil,
            typeIdentifier: UTType.image.identifier,
            to: rootURL,
            fileManager: fileManager
        )) { error in
            guard case AutonomoAVShareExtensionInboxWriter.InboxError.unsupportedFile = error else {
                return XCTFail("Expected unsupportedFile, got \(error)")
            }
        }
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: rootURL.path), [])
    }
}

@MainActor
private final class TemporarilyUnavailableAccountService: AutonomoAccountServicing {
    var isAvailable: Bool { true }
    var providerSessionUser: AccountAVUser? { nil }
    private(set) var tokenRequestCount = 0

    func restoreSession() async -> AccountAVSessionRestoreResult {
        .temporarilyUnavailable(nil)
    }

    func getToken() async throws -> String? {
        tokenRequestCount += 1
        return "provider-token"
    }

    func signInWithApple() async throws {}

    func signInWithGoogle() async throws {}

    func signOut() async throws {}
}
