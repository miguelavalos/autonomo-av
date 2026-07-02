import Foundation
import Observation
import OSLog

enum AutonomoAccessMode: String, CaseIterable, Codable, Identifiable {
    case guest
    case signedInFree
    case signedInPro

    var id: String { rawValue }
}

enum AutonomoPlanTier: String, Codable {
    case free
    case pro
}

struct AutonomoResolvedAccess: Equatable {
    let platformUserId: String?
    let planTier: AutonomoPlanTier
    let accessMode: AutonomoAccessMode
    let capabilities: AutonomoAccessCapabilities
    let limits: AutonomoAccessLimits

    static let guest = AutonomoResolvedAccess.localFallback(for: .guest)

    static func localFallback(for accessMode: AutonomoAccessMode) -> AutonomoResolvedAccess {
        AutonomoResolvedAccess(
            platformUserId: nil,
            planTier: accessMode == .signedInPro ? .pro : .free,
            accessMode: accessMode,
            capabilities: .forMode(accessMode),
            limits: .forMode(accessMode)
        )
    }
}

struct AutonomoAccessCapabilities: Codable, Equatable {
    let isSignedIn: Bool
    let canUseBackend: Bool
    let canUsePremiumFeatures: Bool
    let canUseCloudSync: Bool
    let canManagePlan: Bool

    var canUseIntake: Bool {
        canUsePremiumFeatures
    }

    static func forMode(_ accessMode: AutonomoAccessMode) -> AutonomoAccessCapabilities {
        switch accessMode {
        case .guest:
            AutonomoAccessCapabilities(
                isSignedIn: false,
                canUseBackend: true,
                canUsePremiumFeatures: false,
                canUseCloudSync: false,
                canManagePlan: false
            )
        case .signedInFree:
            AutonomoAccessCapabilities(
                isSignedIn: true,
                canUseBackend: true,
                canUsePremiumFeatures: false,
                canUseCloudSync: false,
                canManagePlan: true
            )
        case .signedInPro:
            AutonomoAccessCapabilities(
                isSignedIn: true,
                canUseBackend: true,
                canUsePremiumFeatures: true,
                canUseCloudSync: true,
                canManagePlan: true
            )
        }
    }

    init(
        isSignedIn: Bool,
        canUseBackend: Bool,
        canUsePremiumFeatures: Bool,
        canUseCloudSync: Bool,
        canManagePlan: Bool
    ) {
        self.isSignedIn = isSignedIn
        self.canUseBackend = canUseBackend
        self.canUsePremiumFeatures = canUsePremiumFeatures
        self.canUseCloudSync = canUseCloudSync
        self.canManagePlan = canManagePlan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isSignedIn = try container.decodeIfPresent(Bool.self, forKey: .isSignedIn) ?? false
        canUseBackend = try container.decodeIfPresent(Bool.self, forKey: .canUseBackend) ?? true
        canUsePremiumFeatures = try container.decodeIfPresent(Bool.self, forKey: .canUsePremiumFeatures) ?? false
        canUseCloudSync = try container.decodeIfPresent(Bool.self, forKey: .canUseCloudSync) ?? false
        canManagePlan = try container.decodeIfPresent(Bool.self, forKey: .canManagePlan) ?? isSignedIn
    }
}

struct AutonomoAccessLimits: Codable, Equatable {
    static func forMode(_ accessMode: AutonomoAccessMode) -> AutonomoAccessLimits {
        _ = accessMode
        return AutonomoAccessLimits()
    }
}

struct AutonomoMeAccessResponse: Decodable, Equatable {
    let viewer: AutonomoMeAccessViewer?
    let apps: [AutonomoAppAccess]
}

struct AutonomoMeAccessViewer: Decodable, Equatable {
    let isAuthenticated: Bool
    let userId: String?
    let identityProvider: String?
}

struct AutonomoAppAccess: Decodable, Equatable {
    let appId: String
    let accessMode: AutonomoAccessMode
    let planTier: AutonomoPlanTier
    let capabilities: AutonomoAccessCapabilities
    let limits: AutonomoAccessLimits

    init(
        appId: String,
        accessMode: AutonomoAccessMode,
        planTier: AutonomoPlanTier,
        capabilities: AutonomoAccessCapabilities,
        limits: AutonomoAccessLimits
    ) {
        self.appId = appId
        self.accessMode = accessMode
        self.planTier = planTier
        self.capabilities = capabilities
        self.limits = limits
    }

    enum CodingKeys: String, CodingKey {
        case appId
        case accessMode
        case planTier
        case capabilities
        case limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appId = try container.decode(String.self, forKey: .appId)
        accessMode = try container.decode(AutonomoAccessMode.self, forKey: .accessMode)
        planTier = try container.decode(AutonomoPlanTier.self, forKey: .planTier)
        capabilities = try container.decodeIfPresent(AutonomoAccessCapabilities.self, forKey: .capabilities)
            ?? .forMode(accessMode)
        limits = try container.decodeIfPresent(AutonomoAccessLimits.self, forKey: .limits)
            ?? .forMode(accessMode)
    }
}

@MainActor
protocol AutonomoAccessProviding {
    var isConfigured: Bool { get }

    func fetchMeAccess() async throws -> AutonomoMeAccessResponse
}

extension AutonomoAPIClient: AutonomoAccessProviding {}

@MainActor
@Observable
final class AutonomoAccessController {
    enum SubscriptionReconciliationSource: Equatable {
        case purchase
        case restore
    }

    private let apiClient: AutonomoAccessProviding
    private let subscriptionPurchasing: AutonomoSubscriptionPurchasing
    private let debugForceProModeProvider: () -> Bool
    private let logger = Logger(subsystem: "com.avalsys.autonomoav", category: "account-access")
    private let subscriptionReconciliationRetryDelaysNanoseconds: [UInt64]
    private let sleepNanoseconds: (UInt64) async -> Void
    private var accessRefreshGeneration = 0

    private(set) var accessMode: AutonomoAccessMode
    private(set) var planTier: AutonomoPlanTier
    private(set) var capabilities: AutonomoAccessCapabilities
    private(set) var limits: AutonomoAccessLimits
    private(set) var platformUserId: String?
    private(set) var subscriptionOffer: AutonomoSubscriptionOffer?
    private(set) var subscriptionError: AutonomoSubscriptionPurchaseError?
    private(set) var isRefreshingAccess: Bool
    private(set) var isSubscriptionOperationInProgress: Bool
    private(set) var isWaitingForSubscriptionReconciliation: Bool
    private(set) var subscriptionReconciliationSource: SubscriptionReconciliationSource?

    init(
        apiClient: AutonomoAccessProviding,
        subscriptionPurchasing: AutonomoSubscriptionPurchasing = RevenueCatAutonomoSubscriptionPurchasing(),
        debugForceProModeProvider: @escaping () -> Bool = { AppConfig.isDebugForceProModeEnabled },
        subscriptionReconciliationRetryDelaysNanoseconds: [UInt64] = [
            1_000_000_000,
            2_000_000_000,
            3_000_000_000,
            5_000_000_000
        ],
        sleepNanoseconds: @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.apiClient = apiClient
        self.subscriptionPurchasing = subscriptionPurchasing
        self.debugForceProModeProvider = debugForceProModeProvider
        self.subscriptionReconciliationRetryDelaysNanoseconds = subscriptionReconciliationRetryDelaysNanoseconds
        self.sleepNanoseconds = sleepNanoseconds
        self.accessMode = .guest
        self.planTier = .free
        self.capabilities = .forMode(.guest)
        self.limits = .forMode(.guest)
        self.platformUserId = nil
        self.subscriptionOffer = nil
        self.subscriptionError = nil
        self.isRefreshingAccess = false
        self.isSubscriptionOperationInProgress = false
        self.isWaitingForSubscriptionReconciliation = false
        self.subscriptionReconciliationSource = nil
    }

    var isSignedIn: Bool {
        accessMode != .guest
    }

    var hasProAccess: Bool {
        accessMode == .signedInPro && capabilities.canUseIntake
    }

    func refreshAccess(for user: AutonomoAccountUser?) async {
        accessRefreshGeneration += 1
        let generation = accessRefreshGeneration
        let fallbackAccess = resolveLocalAccess(for: user)
        guard user != nil else {
            applyResolvedAccess(fallbackAccess)
            return
        }

        isRefreshingAccess = true
        defer {
            if generation == accessRefreshGeneration {
                isRefreshingAccess = false
            }
        }

        guard apiClient.isConfigured else {
            logger.error("Unable to refresh Autonomo AV access: missing API base URL")
            applyResolvedAccess(fallbackAccess)
            return
        }

        do {
            let payload = try await apiClient.fetchMeAccess()
            guard let appAccess = payload.apps.first(where: { $0.appId == AutonomoAPIClient.appIdentifier }) else {
                logger.error("Unable to refresh Autonomo AV access: autonomoav entry missing")
                applyResolvedAccess(fallbackAccess)
                return
            }

            guard generation == accessRefreshGeneration else { return }
            let remoteAccess = AutonomoResolvedAccess(
                platformUserId: payload.viewer?.userId,
                planTier: appAccess.planTier,
                accessMode: appAccess.accessMode,
                capabilities: appAccess.capabilities,
                limits: appAccess.limits
            )
            applyResolvedAccess(resolvedAccessApplyingDebugOverride(remoteAccess, user: user))
        } catch {
            logger.error("Unable to refresh Autonomo AV access")
            guard generation == accessRefreshGeneration else { return }
            applyResolvedAccess(fallbackAccess)
        }
    }

    func loadMonthlySubscriptionOffer(for user: AutonomoAccountUser?) async {
        guard user != nil else {
            subscriptionError = .missingAccountUser
            return
        }

        do {
            subscriptionOffer = try await subscriptionPurchasing.loadMonthlyOffer(for: subscriptionAccountUser(from: user))
            subscriptionError = nil
        } catch let error as AutonomoSubscriptionPurchaseError {
            subscriptionError = error
        } catch {
            subscriptionError = .underlying(error.localizedDescription)
        }
    }

    func purchaseMonthlyPro(for user: AutonomoAccountUser?) async {
        await runSubscriptionOperation(for: user, source: .purchase) {
            try await subscriptionPurchasing.purchaseMonthlyPro(for: subscriptionAccountUser(from: user))
        }
    }

    func restorePurchases(for user: AutonomoAccountUser?) async {
        await runSubscriptionOperation(for: user, source: .restore) {
            try await subscriptionPurchasing.restorePurchases(for: subscriptionAccountUser(from: user))
        }
    }

    private func runSubscriptionOperation(
        for user: AutonomoAccountUser?,
        source: SubscriptionReconciliationSource,
        _ operation: () async throws -> AutonomoPurchaseOutcome
    ) async {
        guard user != nil else {
            subscriptionError = .missingAccountUser
            return
        }

        isSubscriptionOperationInProgress = true
        subscriptionError = nil
        defer {
            isSubscriptionOperationInProgress = false
        }

        do {
            let outcome = try await operation()
            guard outcome.shouldRefreshAccess else { return }
            isWaitingForSubscriptionReconciliation = true
            subscriptionReconciliationSource = source
            await refreshAccess(for: user)
            await retrySubscriptionReconciliationIfNeeded(for: user)
        } catch let error as AutonomoSubscriptionPurchaseError {
            if error != .purchaseCancelled {
                subscriptionError = error
            }
        } catch {
            subscriptionError = .underlying(error.localizedDescription)
        }
    }

    private func retrySubscriptionReconciliationIfNeeded(for user: AutonomoAccountUser?) async {
        guard accessMode != .signedInPro else {
            clearSubscriptionReconciliationState()
            return
        }

        for delay in subscriptionReconciliationRetryDelaysNanoseconds {
            guard isWaitingForSubscriptionReconciliation else { return }
            await sleepNanoseconds(delay)
            guard isWaitingForSubscriptionReconciliation else { return }
            await refreshAccess(for: user)
            if accessMode == .signedInPro {
                clearSubscriptionReconciliationState()
                return
            }
        }
    }

    private func resolveLocalAccess(for user: AutonomoAccountUser?) -> AutonomoResolvedAccess {
        guard user != nil else { return .guest }
        if debugForceProModeProvider() {
            return .localFallback(for: .signedInPro)
        }
        return .localFallback(for: .signedInFree)
    }

    private func resolvedAccessApplyingDebugOverride(
        _ resolvedAccess: AutonomoResolvedAccess,
        user: AutonomoAccountUser?
    ) -> AutonomoResolvedAccess {
        guard user != nil, debugForceProModeProvider() else {
            return resolvedAccess
        }

        return AutonomoResolvedAccess(
            platformUserId: resolvedAccess.platformUserId ?? user?.id,
            planTier: .pro,
            accessMode: .signedInPro,
            capabilities: .forMode(.signedInPro),
            limits: .forMode(.signedInPro)
        )
    }

    private func applyResolvedAccess(_ resolvedAccess: AutonomoResolvedAccess) {
        accessMode = resolvedAccess.accessMode
        planTier = resolvedAccess.planTier
        capabilities = resolvedAccess.capabilities
        limits = resolvedAccess.limits
        platformUserId = resolvedAccess.platformUserId

        if resolvedAccess.accessMode == .guest {
            clearSubscriptionState()
        }
        if resolvedAccess.accessMode == .signedInPro {
            clearSubscriptionReconciliationState()
        }
    }

    private func clearSubscriptionState() {
        subscriptionOffer = nil
        subscriptionError = nil
        isSubscriptionOperationInProgress = false
        clearSubscriptionReconciliationState()
    }

    private func clearSubscriptionReconciliationState() {
        isWaitingForSubscriptionReconciliation = false
        subscriptionReconciliationSource = nil
    }

    private func subscriptionAccountUser(from user: AutonomoAccountUser?) -> AutonomoAccountUser? {
        guard let user else { return nil }
        guard let platformUserId, !platformUserId.isEmpty else { return user }
        return AutonomoAccountUser(
            id: platformUserId,
            displayName: user.displayName,
            emailAddress: user.emailAddress
        )
    }
}
