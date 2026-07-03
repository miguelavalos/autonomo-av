import AppKit
import UniformTypeIdentifiers

enum AutonomoAVMacFilePicker {
    static let allowedContentTypes: [UTType] = [
        .pdf,
        .jpeg,
        .png,
        UTType(filenameExtension: "webp"),
        UTType(filenameExtension: "heic"),
        UTType(filenameExtension: "heif")
    ].compactMap { $0 }

    @MainActor
    static func pickDocuments() -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = allowedContentTypes
        panel.prompt = "Import"
        panel.message = "PDF, JPEG, PNG, WebP, HEIC, HEIF"

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.urls
    }
}
