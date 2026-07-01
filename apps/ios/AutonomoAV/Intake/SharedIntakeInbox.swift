import Foundation

struct SharedIntakeInbox {
    private let rootURL: URL?
    private let fileManager: FileManager

    init(
        rootURL: URL? = Self.defaultRootURL(),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    var pendingURL: URL? {
        rootURL?.appending(path: "ShareInbox/Pending", directoryHint: .isDirectory)
    }

    func pendingFileURLs() throws -> [URL] {
        guard let pendingURL else { return [] }
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)

        let urls = try fileManager.contentsOfDirectory(
            at: pendingURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }
                return lhsDate > rhsDate
            }
    }

    func removePendingFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    static func defaultRootURL(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let rawIdentifier = bundle.object(forInfoDictionaryKey: "AUTONOMOAV_APP_GROUP_IDENTIFIER") as? String else {
            return nil
        }

        let identifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, identifier != "$(AUTONOMOAV_APP_GROUP_IDENTIFIER)" else {
            return nil
        }

        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
