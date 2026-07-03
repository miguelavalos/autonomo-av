import AppKit

@MainActor
final class AutonomoAVMacFileServiceProvider: NSObject {
    var importHandler: (([URL]) -> Void)?

    @objc func sendFilesToAutonomoAV(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let urls = Self.fileURLs(from: pasteboard)
        guard !urls.isEmpty else {
            AutonomoAVMacTelemetry.services.info("Services request rejected: no compatible file URLs")
            error.pointee = "No compatible files were provided." as NSString
            return
        }

        AutonomoAVMacTelemetry.services.info("Services request accepted count=\(urls.count, privacy: .public)")
        importHandler?(urls)
    }

    nonisolated static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        return objects.compactMap { object -> URL? in
            if let url = object as? URL {
                return url.isFileURL ? url : nil
            }
            guard let nsURL = object as? NSURL else {
                return nil
            }
            let url = nsURL as URL
            return url.isFileURL ? url : nil
        }
    }
}
