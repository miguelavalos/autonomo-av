import Foundation

extension LocalIntakeStatus {
    var macDisplayText: String {
        switch self {
        case .pending:
            return "Pending"
        case .uploading:
            return "Uploading"
        case .uploaded:
            return "Uploaded"
        case .failed:
            return "Failed"
        }
    }

    var macSystemImage: String {
        switch self {
        case .pending:
            return "clock"
        case .uploading:
            return "arrow.up.circle"
        case .uploaded:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}

extension AutonomoUploadSource {
    var macDisplayText: String {
        switch self {
        case .iosCamera:
            return "iOS Camera"
        case .iosFiles:
            return "iOS Files"
        case .iosShare:
            return "iOS Share"
        case .macosFiles:
            return "Mac Files"
        case .macosDragDrop:
            return "Mac Drag"
        case .macosShare:
            return "Mac Share"
        case .macosService:
            return "Mac Service"
        case .webUpload:
            return "Web Upload"
        }
    }
}

extension Int {
    var macByteCountText: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}

extension Date {
    var macShortDateTimeText: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
