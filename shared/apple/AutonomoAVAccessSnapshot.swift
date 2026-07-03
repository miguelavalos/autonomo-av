import Foundation

struct AutonomoAVAccessSnapshot: Codable, Equatable {
    static let schemaVersion = 1
    static let appIdentifier = "autonomoav"

    let schemaVersion: Int
    let appId: String
    let platformUserId: String?
    let accessMode: String
    let planTier: String
    let isSignedIn: Bool
    let canUseIntake: Bool
    let verifiedAt: Date
    let environment: String?

    var grantsIntake: Bool {
        appId == Self.appIdentifier
            && isSignedIn
            && accessMode == "signedInPro"
            && planTier == "pro"
            && canUseIntake
    }

    init(
        appId: String = AutonomoAVAccessSnapshot.appIdentifier,
        platformUserId: String?,
        accessMode: String,
        planTier: String,
        isSignedIn: Bool,
        canUseIntake: Bool,
        verifiedAt: Date = Date(),
        environment: String?
    ) {
        self.schemaVersion = Self.schemaVersion
        self.appId = appId
        self.platformUserId = platformUserId
        self.accessMode = accessMode
        self.planTier = planTier
        self.isSignedIn = isSignedIn
        self.canUseIntake = canUseIntake
        self.verifiedAt = verifiedAt
        self.environment = environment
    }

    func isFresh(now: Date = Date(), maxAge: TimeInterval = AutonomoAVAccessSnapshotStore.defaultMaxAge) -> Bool {
        now.timeIntervalSince(verifiedAt) <= maxAge
    }
}

enum AutonomoAVAccessSnapshotStore {
    enum SnapshotError: Error {
        case missingAppGroup
    }

    static let defaultMaxAge: TimeInterval = 24 * 60 * 60

    static func write(
        _ snapshot: AutonomoAVAccessSnapshot,
        fileManager: FileManager = .default
    ) throws {
        guard let snapshotURL = snapshotURL(fileManager: fileManager) else {
            throw SnapshotError.missingAppGroup
        }
        try fileManager.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: [.atomic])
    }

    static func clear(fileManager: FileManager = .default) {
        guard let snapshotURL = snapshotURL(fileManager: fileManager) else { return }
        try? fileManager.removeItem(at: snapshotURL)
    }

    static func load(fileManager: FileManager = .default) throws -> AutonomoAVAccessSnapshot? {
        guard let snapshotURL = snapshotURL(fileManager: fileManager) else {
            throw SnapshotError.missingAppGroup
        }
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AutonomoAVAccessSnapshot.self, from: data)
    }

    static func loadFreshProSnapshot(
        now: Date = Date(),
        maxAge: TimeInterval = defaultMaxAge,
        fileManager: FileManager = .default
    ) -> AutonomoAVAccessSnapshot? {
        guard let snapshot = try? load(fileManager: fileManager),
              snapshot.grantsIntake,
              snapshot.isFresh(now: now, maxAge: maxAge) else {
            return nil
        }
        return snapshot
    }

    private static func snapshotURL(fileManager: FileManager) -> URL? {
        guard let rootURL = appGroupRootURL(fileManager: fileManager) else {
            return nil
        }
        return rootURL
            .appending(path: "Access", directoryHint: .isDirectory)
            .appending(path: "autonomoav-access.json")
    }

    private static func appGroupRootURL(fileManager: FileManager) -> URL? {
        guard let identifier = appGroupIdentifier() else {
            return nil
        }
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

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
}
