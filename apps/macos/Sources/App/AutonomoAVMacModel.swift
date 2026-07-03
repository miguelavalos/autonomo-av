import Foundation
import Observation

@MainActor
protocol AutonomoAVMacAccessProviding {
    var isConfigured: Bool { get }

    func fetchMeAccess() async throws -> AutonomoMeAccessResponse
}

extension AutonomoAPIClient: AutonomoAVMacAccessProviding {}

@MainActor
@Observable
final class AutonomoAVMacModel {
    private let accountService: AutonomoAccountServicing
    private let apiClient: AutonomoAPIClient
    private let accessProvider: AutonomoAVMacAccessProviding
    private let uploader: AutonomoPreparedDocumentUploader
    private let persistence: LocalIntakePersistence
    private let sharedInbox: SharedIntakeInbox

    let accountController: AccountController
    private(set) var localItems: [LocalIntakeItem]
    private(set) var remoteDocuments: [AutonomoDocumentSummary] = []
    private(set) var isImporting = false
    private(set) var isImportingSharedInbox = false
    private(set) var isUploading = false
    private(set) var isRefreshingRemoteDocuments = false
    private(set) var isRefreshingAccess = false
    private(set) var accessMode: AutonomoAccessMode = .guest
    private(set) var planTier: AutonomoPlanTier = .free
    private(set) var accessCapabilities = AutonomoAccessCapabilities.forMode(.guest)
    private(set) var platformUserId: String?
    var lastErrorMessage: String?
    private var workspaceBootstrapped = false

    init(
        accountService: AutonomoAccountServicing = DefaultAutonomoAccountService(),
        persistence: LocalIntakePersistence = LocalIntakePersistence(
            rootURL: AppConfig.localIntakeRootURL,
            idempotencyKeyPrefix: "macos",
            sharedInboxSource: .macosShare
        ),
        sharedInbox: SharedIntakeInbox = SharedIntakeInbox(),
        userDefaults: UserDefaults = .standard
    ) {
        self.accountService = accountService
        self.persistence = persistence
        self.sharedInbox = sharedInbox
        let apiClient = AutonomoAPIClient(tokenProvider: { try await accountService.getToken() })
        self.apiClient = apiClient
        self.accessProvider = apiClient
        self.uploader = AutonomoPreparedDocumentUploader(backend: apiClient)
        self.accountController = AccountController(
            accountService: accountService,
            profileResolver: PlatformAccountProfileResolver(apiClient: apiClient),
            userDefaults: userDefaults
        )

        let normalizedItems = AutonomoLocalIntakeQueue.normalizeLoadedItems(persistence.loadItems())
        self.localItems = normalizedItems.items.sorted { $0.createdAt > $1.createdAt }
        if normalizedItems.didChange {
            try? persistence.saveItems(self.localItems)
        }
    }

    var currentAccountUser: AutonomoAccountUser? {
        accountController.currentUser
    }

    var accountIsSignedIn: Bool {
        accountController.state.isSignedIn
    }

    var hasProAccess: Bool {
        accessMode == .signedInPro && accessCapabilities.isSignedIn && accessCapabilities.canUseIntake
    }

    var accountStatusText: String {
        switch accountController.state {
        case .restoring:
            return "Restoring account"
        case .signedOut:
            return "Signed out"
        case .temporarilyUnavailable(let user):
            return user == nil ? "Account unavailable" : "Using last account"
        case .signedIn(let user):
            return user.emailAddress ?? user.displayName
        }
    }

    var accessStatusText: String {
        guard accountIsSignedIn else {
            return "Sign in required"
        }

        switch accessMode {
        case .guest:
            return "Checking access"
        case .signedInFree:
            return "Pro required"
        case .signedInPro:
            return "Pro active"
        }
    }

    var pendingCount: Int {
        localItems.filter { $0.status == .pending || $0.status == .uploading }.count
    }

    var failedCount: Int {
        localItems.filter { $0.status == .failed }.count
    }

    var uploadedCount: Int {
        localItems.filter { $0.status == .uploaded }.count
    }

    var hasUploadableItems: Bool {
        localItems.contains { $0.status == .pending || $0.status == .failed }
    }

    func restoreAccount() async {
        AutonomoAVMacTelemetry.app.info("Account restore requested")
        await accountController.restore()
        await refreshAccess()
        if hasProAccess {
            AutonomoAVMacTelemetry.app.info("Account restore resolved signed-in user")
            await syncSignedInIntake()
        } else {
            AutonomoAVMacTelemetry.app.info("Account restore completed without signed-in user")
        }
    }

    func signInWithApple() async {
        AutonomoAVMacTelemetry.app.info("Apple sign-in requested")
        await accountController.signInWithApple()
        await refreshAccess()
        if hasProAccess {
            AutonomoAVMacTelemetry.app.info("Apple sign-in resolved signed-in user")
            await syncSignedInIntake()
        }
    }

    func signInWithGoogle() async {
        AutonomoAVMacTelemetry.app.info("Google sign-in requested")
        await accountController.signInWithGoogle()
        await refreshAccess()
        if hasProAccess {
            AutonomoAVMacTelemetry.app.info("Google sign-in resolved signed-in user")
            await syncSignedInIntake()
        }
    }

    func signOut() async {
        AutonomoAVMacTelemetry.app.info("Sign-out requested")
        await accountController.signOut()
        applyResolvedAccess(.guest)
        remoteDocuments = []
        workspaceBootstrapped = false
    }

    func pickAndImportFiles(source: AutonomoUploadSource) async {
        guard requireIntakeAccess() else { return }
        guard let urls = AutonomoAVMacFilePicker.pickDocuments() else {
            AutonomoAVMacTelemetry.intake.info("File picker cancelled")
            return
        }
        await importFiles(urls, source: source)
    }

    func importFiles(_ urls: [URL], source: AutonomoUploadSource) async {
        guard !urls.isEmpty else { return }
        guard requireIntakeAccess() else { return }
        AutonomoAVMacTelemetry.intake.info("Import requested source=\(source.rawValue, privacy: .public) count=\(urls.count, privacy: .public)")
        isImporting = true
        defer { isImporting = false }

        var importedItems: [LocalIntakeItem] = []
        var rejectedCount = 0
        var failedCount = 0

        for url in urls {
            do {
                importedItems.append(try persistence.copyImportedFile(from: url, source: source))
            } catch {
                if (error as? AutonomoDocumentIntakeError)?.isDeterministicRejection == true {
                    rejectedCount += 1
                } else {
                    failedCount += 1
                }
            }
        }

        if !importedItems.isEmpty {
            localItems.insert(contentsOf: importedItems, at: 0)
            try? save()
        }

        if failedCount > 0 || rejectedCount > 0 {
            lastErrorMessage = "\(importSurfaceLabel(for: source)) finished with \(failedCount) failed file(s) and \(rejectedCount) unsupported or too-large file(s)."
        } else if !importedItems.isEmpty {
            lastErrorMessage = nil
        }

        AutonomoAVMacTelemetry.intake.info(
            "Import completed source=\(source.rawValue, privacy: .public) imported=\(importedItems.count, privacy: .public) failed=\(failedCount, privacy: .public) rejected=\(rejectedCount, privacy: .public)"
        )

        if !importedItems.isEmpty {
            await uploadPending()
        }
    }

    func syncSignedInIntake() async {
        guard requireIntakeAccess() else { return }
        AutonomoAVMacTelemetry.intake.info("Signed-in intake sync requested")
        await importSharedInboxItems()
        await uploadPending()
        await refreshRemoteDocuments()
    }

    func retry(_ item: LocalIntakeItem) async {
        guard requireIntakeAccess() else { return }
        AutonomoAVMacTelemetry.intake.info("Retry requested itemID=\(item.id.uuidString, privacy: .public)")
        updateItem(id: item.id) { current in
            current.markPendingForRetry()
        }
        try? save()
        await uploadPending()
    }

    func uploadPending() async {
        guard requireIntakeAccess() else { return }
        guard hasUploadableItems else {
            AutonomoAVMacTelemetry.intake.info("Upload pending skipped because there are no uploadable items")
            return
        }
        guard !isUploading else {
            AutonomoAVMacTelemetry.intake.info("Upload pending skipped because upload is already active")
            return
        }

        AutonomoAVMacTelemetry.intake.info("Upload pending started pending=\(self.pendingCount, privacy: .public) failed=\(self.failedCount, privacy: .public)")
        isUploading = true
        defer { isUploading = false }

        do {
            try await bootstrapWorkspaceIfNeeded()
        } catch {
            lastErrorMessage = error.localizedDescription
            AutonomoAVMacTelemetry.intake.error("Upload pending failed during workspace bootstrap")
            return
        }

        for item in localItems where item.status == .pending || item.status == .failed {
            await upload(item)
        }
        AutonomoAVMacTelemetry.intake.info("Upload pending completed pending=\(self.pendingCount, privacy: .public) failed=\(self.failedCount, privacy: .public)")
    }

    func importSharedInboxItems() async {
        guard requireIntakeAccess() else { return }
        guard !isImportingSharedInbox else {
            AutonomoAVMacTelemetry.intake.info("Share inbox import skipped because import is already active")
            return
        }
        isImportingSharedInbox = true
        defer { isImportingSharedInbox = false }

        let pendingURLs: [URL]
        do {
            pendingURLs = try sharedInbox.pendingFileURLs()
        } catch {
            lastErrorMessage = error.localizedDescription
            AutonomoAVMacTelemetry.intake.error("Share inbox import failed while listing pending files")
            return
        }

        guard !pendingURLs.isEmpty else { return }
        AutonomoAVMacTelemetry.intake.info("Share inbox import requested count=\(pendingURLs.count, privacy: .public)")

        var importedItems: [LocalIntakeItem] = []
        var rejectedCount = 0
        var failedCount = 0

        for url in pendingURLs {
            do {
                let item = try persistence.copySharedInboxFile(from: url)
                importedItems.append(item)
                try sharedInbox.removePendingFile(at: url)
            } catch {
                if (error as? AutonomoDocumentIntakeError)?.isDeterministicRejection == true {
                    rejectedCount += 1
                    try? sharedInbox.removePendingFile(at: url)
                } else {
                    failedCount += 1
                }
            }
        }

        if !importedItems.isEmpty {
            localItems.insert(contentsOf: importedItems, at: 0)
            try? save()
        }

        if failedCount > 0 || rejectedCount > 0 {
            lastErrorMessage = "Shared inbox import finished with \(failedCount) failed file(s) and \(rejectedCount) unsupported or too-large file(s)."
        } else if !importedItems.isEmpty {
            lastErrorMessage = nil
        }

        AutonomoAVMacTelemetry.intake.info(
            "Share inbox import completed imported=\(importedItems.count, privacy: .public) failed=\(failedCount, privacy: .public) rejected=\(rejectedCount, privacy: .public)"
        )
    }

    func refreshRemoteDocuments() async {
        guard requireIntakeAccess() else { return }
        guard apiClient.isConfigured else {
            lastErrorMessage = L10n.string("account.apiMissing")
            AutonomoAVMacTelemetry.intake.info("Remote document refresh skipped: API base URL missing")
            return
        }

        AutonomoAVMacTelemetry.intake.info("Remote document refresh started")
        isRefreshingRemoteDocuments = true
        defer { isRefreshingRemoteDocuments = false }

        do {
            try await bootstrapWorkspaceIfNeeded()
            remoteDocuments = try await apiClient.fetchRecentDocuments()
            lastErrorMessage = nil
            AutonomoAVMacTelemetry.intake.info("Remote document refresh completed count=\(self.remoteDocuments.count, privacy: .public)")
        } catch {
            lastErrorMessage = error.localizedDescription
            AutonomoAVMacTelemetry.intake.error("Remote document refresh failed")
        }
    }

    func refreshAccess() async {
        guard accountIsSignedIn else {
            applyResolvedAccess(.guest)
            return
        }

        guard accessProvider.isConfigured else {
            AutonomoAVMacTelemetry.app.error("Access refresh skipped: API base URL missing")
            applyResolvedAccess(.localFallback(for: .signedInFree))
            return
        }

        isRefreshingAccess = true
        defer { isRefreshingAccess = false }

        do {
            let payload = try await accessProvider.fetchMeAccess()
            guard let appAccess = payload.apps.first(where: { $0.appId == AutonomoAPIClient.appIdentifier }) else {
                AutonomoAVMacTelemetry.app.error("Access refresh did not include autonomoav")
                applyResolvedAccess(.localFallback(for: .signedInFree))
                return
            }

            applyResolvedAccess(AutonomoResolvedAccess(
                platformUserId: payload.viewer?.userId,
                planTier: appAccess.planTier,
                accessMode: appAccess.accessMode,
                capabilities: appAccess.capabilities,
                limits: appAccess.limits
            ))
        } catch {
            AutonomoAVMacTelemetry.app.error("Access refresh failed")
            applyResolvedAccess(.localFallback(for: .signedInFree))
        }
    }

    #if DEBUG
    func enableProAccessForTesting() {
        applyResolvedAccess(.localFallback(for: .signedInPro), publishSnapshot: false)
    }
    #endif

    private func upload(_ item: LocalIntakeItem) async {
        AutonomoAVMacTelemetry.intake.info("Upload item started source=\(item.source.rawValue, privacy: .public) itemID=\(item.id.uuidString, privacy: .public)")
        updateItem(id: item.id) { current in
            current.markUploading()
        }
        try? save()

        do {
            let current = localItems.first { $0.id == item.id } ?? item
            let fileURL = persistence.fileURL(for: current)
            let data = try Data(contentsOf: fileURL)
            let uploadResult = try await uploader.upload(AutonomoDocumentUploadPayload(
                originalFilename: current.fileName,
                contentType: current.mimeType,
                data: data,
                source: current.source
            ))
            updateItem(id: item.id) { uploaded in
                uploaded.markUploaded(uploadResult)
            }
            try save()
            lastErrorMessage = nil
            AutonomoAVMacTelemetry.intake.info("Upload item completed source=\(current.source.rawValue, privacy: .public) itemID=\(item.id.uuidString, privacy: .public)")
        } catch {
            updateItem(id: item.id) { failed in
                failed.markFailed(error.localizedDescription)
            }
            try? save()
            AutonomoAVMacTelemetry.intake.error("Upload item failed source=\(item.source.rawValue, privacy: .public) itemID=\(item.id.uuidString, privacy: .public)")
        }
    }

    private func updateItem(id: UUID, mutate: (inout LocalIntakeItem) -> Void) {
        guard let index = localItems.firstIndex(where: { $0.id == id }) else { return }
        mutate(&localItems[index])
        localItems.sort { $0.createdAt > $1.createdAt }
    }

    private func bootstrapWorkspaceIfNeeded() async throws {
        guard !workspaceBootstrapped else { return }
        guard apiClient.isConfigured else {
            throw AutonomoAPIClientError.missingBaseURL
        }
        _ = try await apiClient.bootstrapWorkspace()
        workspaceBootstrapped = true
    }

    private func save() throws {
        try persistence.saveItems(localItems)
    }

    private func requireIntakeAccess() -> Bool {
        guard accessMode != .guest else {
            AutonomoAVMacTelemetry.intake.info("Intake blocked: signed out pending=\(self.pendingCount, privacy: .public) failed=\(self.failedCount, privacy: .public)")
            lastErrorMessage = "Sign in with Account AV before sending documents."
            return false
        }

        guard hasProAccess else {
            AutonomoAVMacTelemetry.intake.info("Intake blocked: Pro access required")
            lastErrorMessage = "Autonomo AV Pro is required before importing or uploading documents."
            return false
        }

        return true
    }

    private func applyResolvedAccess(_ resolvedAccess: AutonomoResolvedAccess, publishSnapshot: Bool = true) {
        accessMode = resolvedAccess.accessMode
        planTier = resolvedAccess.planTier
        accessCapabilities = resolvedAccess.capabilities
        platformUserId = resolvedAccess.platformUserId

        guard publishSnapshot else {
            return
        }

        guard resolvedAccess.accessMode == .signedInPro, resolvedAccess.capabilities.canUseIntake else {
            AutonomoAVAccessSnapshotStore.clear()
            remoteDocuments = []
            workspaceBootstrapped = false
            return
        }

        let snapshot = AutonomoAVAccessSnapshot(
            platformUserId: resolvedAccess.platformUserId,
            accessMode: resolvedAccess.accessMode.rawValue,
            planTier: resolvedAccess.planTier.rawValue,
            isSignedIn: resolvedAccess.capabilities.isSignedIn,
            canUseIntake: resolvedAccess.capabilities.canUseIntake,
            environment: AppConfig.environmentName
        )
        try? AutonomoAVAccessSnapshotStore.write(snapshot)
    }

    private func importSurfaceLabel(for source: AutonomoUploadSource) -> String {
        switch source {
        case .macosFiles:
            return "File import"
        case .macosDragDrop:
            return "Drag and drop import"
        case .macosService:
            return "Services import"
        case .macosShare:
            return "Share inbox import"
        default:
            return "\(source.macDisplayText) import"
        }
    }
}
