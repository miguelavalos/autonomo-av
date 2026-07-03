import Foundation
import UniformTypeIdentifiers

struct AutonomoAVShareAttachment: @unchecked Sendable {
    let provider: NSItemProvider
    let typeIdentifier: String
    let suggestedName: String?
    let isFileURL: Bool

    init?(provider: NSItemProvider) {
        if let supportedTypeIdentifier = AutonomoAVShareExtensionInboxWriter.supportedPayloadTypeIdentifier(
            from: provider.registeredTypeIdentifiers
        ) {
            typeIdentifier = supportedTypeIdentifier
            isFileURL = false
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            typeIdentifier = UTType.fileURL.identifier
            isFileURL = true
        } else {
            return nil
        }

        self.provider = provider
        self.suggestedName = provider.suggestedName
    }

    static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url.isFileURL ? url : nil
        }
        guard let nsURL = item as? NSURL else {
            return nil
        }
        let url = nsURL as URL
        return url.isFileURL ? url : nil
    }
}

enum AutonomoAVShareExtensionInboxWriter {
    enum InboxError: Error {
        case missingAppGroup
        case unsupportedFile
        case uploadTooLarge
    }

    static func preparePendingURL(fileManager: FileManager = .default) throws -> URL {
        guard let rootURL = appGroupRootURL(fileManager: fileManager) else {
            throw InboxError.missingAppGroup
        }

        let pendingURL = rootURL.appending(path: "ShareInbox/Pending", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        return pendingURL
    }

    static func copyTemporaryFile(
        from temporaryURL: URL,
        suggestedName: String?,
        typeIdentifier: String,
        to pendingURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard Self.isSupportedPayloadTypeIdentifier(typeIdentifier) else {
            throw InboxError.unsupportedFile
        }
        let byteSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard byteSize <= Self.maxUploadByteSize else {
            throw InboxError.uploadTooLarge
        }

        let destination = uniqueDestinationURL(
            suggestedName: suggestedName ?? temporaryURL.lastPathComponent,
            typeIdentifier: typeIdentifier,
            pendingURL: pendingURL,
            fileManager: fileManager
        )
        try fileManager.copyItem(at: temporaryURL, to: destination)
    }

    static func copyFileURL(
        from fileURL: URL,
        suggestedName: String?,
        to pendingURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard let typeIdentifier = supportedTypeIdentifier(for: fileURL) else {
            throw InboxError.unsupportedFile
        }

        try copyTemporaryFile(
            from: fileURL,
            suggestedName: suggestedName ?? fileURL.lastPathComponent,
            typeIdentifier: typeIdentifier,
            to: pendingURL,
            fileManager: fileManager
        )
    }

    static func writeData(
        _ data: Data,
        suggestedName: String?,
        typeIdentifier: String,
        to pendingURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard Self.isSupportedPayloadTypeIdentifier(typeIdentifier) else {
            throw InboxError.unsupportedFile
        }
        guard data.count <= Self.maxUploadByteSize else {
            throw InboxError.uploadTooLarge
        }

        let destination = uniqueDestinationURL(
            suggestedName: suggestedName,
            typeIdentifier: typeIdentifier,
            pendingURL: pendingURL,
            fileManager: fileManager
        )
        try data.write(to: destination, options: [.atomic])
    }

    static func supportedPayloadTypeIdentifier(from typeIdentifiers: [String]) -> String? {
        for typeIdentifier in typeIdentifiers {
            if isSupportedPayloadTypeIdentifier(typeIdentifier) {
                return typeIdentifier
            }
        }
        return nil
    }

    private static func appGroupRootURL(fileManager: FileManager) -> URL? {
        guard let identifier = appGroupIdentifier() else {
            return nil
        }
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    private static func supportedTypeIdentifier(for fileURL: URL) -> String? {
        switch fileURL.pathExtension.lowercased() {
        case "pdf":
            return UTType.pdf.identifier
        case "jpg", "jpeg":
            return UTType.jpeg.identifier
        case "png":
            return UTType.png.identifier
        case "webp":
            return "org.webmproject.webp"
        case "heic":
            return "public.heic"
        case "heif":
            return "public.heif"
        default:
            return nil
        }
    }

    private static func isSupportedPayloadTypeIdentifier(_ typeIdentifier: String) -> Bool {
        if supportedPayloadTypeIdentifiers.contains(typeIdentifier) {
            return true
        }
        guard let type = UTType(typeIdentifier) else {
            return false
        }
        return supportedPayloadTypeIdentifiers.contains { supportedTypeIdentifier in
            guard let supportedType = UTType(supportedTypeIdentifier) else {
                return false
            }
            return type.conforms(to: supportedType)
        }
    }

    private static let supportedPayloadTypeIdentifiers: Set<String> = [
        UTType.pdf.identifier,
        UTType.jpeg.identifier,
        UTType.png.identifier,
        "org.webmproject.webp",
        "public.heic",
        "public.heif",
    ]
    private static let maxUploadByteSize = 25 * 1024 * 1024

    private static func appGroupIdentifier(bundle: Bundle = .main) -> String? {
        if let configured = bundle.object(forInfoDictionaryKey: "AUTONOMOAV_APP_GROUP_IDENTIFIER") as? String {
            let identifier = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if !identifier.isEmpty, identifier != "$(AUTONOMOAV_APP_GROUP_IDENTIFIER)" {
                return identifier
            }
        }

        guard let bundleIdentifier = bundle.bundleIdentifier else {
            return nil
        }

        let containingBundleIdentifier: String
        if bundleIdentifier.hasSuffix(".share") {
            containingBundleIdentifier = String(bundleIdentifier.dropLast(".share".count))
        } else {
            containingBundleIdentifier = bundleIdentifier
        }
        return "group.\(containingBundleIdentifier)"
    }

    private static func uniqueDestinationURL(
        suggestedName: String?,
        typeIdentifier: String,
        pendingURL: URL,
        fileManager: FileManager
    ) -> URL {
        let fileName = sanitizedFileName(suggestedName, typeIdentifier: typeIdentifier)
        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension

        var candidate = pendingURL.appending(path: fileName)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let suffixedName: String
            if pathExtension.isEmpty {
                suffixedName = "\(baseName)-\(suffix)"
            } else {
                suffixedName = "\(baseName)-\(suffix).\(pathExtension)"
            }
            candidate = pendingURL.appending(path: suffixedName)
            suffix += 1
        }
        return candidate
    }

    private static func sanitizedFileName(_ suggestedName: String?, typeIdentifier: String) -> String {
        let fallbackExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "dat"
        let fallbackName = "shared-\(UUID().uuidString).\(fallbackExtension)"
        let rawName = suggestedName?.isEmpty == false ? suggestedName ?? fallbackName : fallbackName
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        let sanitized = rawName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            return fallbackName
        }
        if (sanitized as NSString).pathExtension.isEmpty {
            return "\(sanitized).\(fallbackExtension)"
        }
        return sanitized
    }
}
