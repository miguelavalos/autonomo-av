import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum AutonomoUploadSource: String, Codable, CaseIterable {
    case iosCamera = "ios_camera"
    case iosFiles = "ios_files"
    case iosShare = "ios_share"
    case macosFiles = "macos_files"
    case macosDragDrop = "macos_drag_drop"
    case macosShare = "macos_share"
    case macosService = "macos_service"
    case webUpload = "web_upload"
}

enum AutonomoDocumentAssetSupport {
    static let maxUploadByteSize = 25 * 1024 * 1024

    static let supportedMimeTypes: Set<String> = [
        "application/pdf",
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/heic",
        "image/heif"
    ]

    static func mimeType(for url: URL) -> String? {
        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .pdf) || type.conforms(to: .image) {
            let mimeType = type.preferredMIMEType ?? fallbackMimeType(forExtension: url.pathExtension)
            return supportedMimeTypes.contains(mimeType ?? "") ? mimeType : nil
        }
        guard let fallbackMimeType = fallbackMimeType(forExtension: url.pathExtension) else {
            return nil
        }
        return supportedMimeTypes.contains(fallbackMimeType) ? fallbackMimeType : nil
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
        case "heif":
            return "image/heif"
        case "webp":
            return "image/webp"
        default:
            return nil
        }
    }

    static func idempotencyKey(prefix: String, id: UUID) -> String {
        "\(prefix)-\(id.uuidString)"
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
