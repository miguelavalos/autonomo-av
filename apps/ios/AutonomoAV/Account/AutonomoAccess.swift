import Foundation
import Observation
import OSLog

@MainActor
protocol AutonomoAccessProviding {
    var isConfigured: Bool { get }

    func fetchMeAccess() async throws -> AutonomoMeAccessResponse
}

extension AutonomoAPIClient: AutonomoAccessProviding {}

@MainActor
private struct NoopAutonomoPromotionCodeRedeemer: AutonomoPromotionCodeRedeeming {
    func redeemPromotionCode(_ code: String) async throws -> AutonomoPromotionCodeRedemptionResponse {
        throw AutonomoSubscriptionPurchaseError.missingConfiguration
    }
}

@MainActor
@Observable
final class AutonomoAccessController {
    enum SubscriptionReconciliationSource: Equatable {
        case purchase
        case restore
        case redeemCode
    }

    private let apiClient: AutonomoAccessProviding
    private let subscriptionPurchasing: AutonomoSubscriptionPurchasing
    private let promotionCodeRedeemer: AutonomoPromotionCodeRedeeming
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
        promotionCodeRedeemer: AutonomoPromotionCodeRedeeming? = nil,
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
        self.promotionCodeRedeemer = promotionCodeRedeemer ?? NoopAutonomoPromotionCodeRedeemer()
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

    func claimPromotionCode(_ code: String, for user: AutonomoAccountUser?) async throws {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else { return }
        guard user != nil else {
            subscriptionError = .missingAccountUser
            throw AutonomoSubscriptionPurchaseError.missingAccountUser
        }

        isSubscriptionOperationInProgress = true
        subscriptionError = nil
        defer {
            isSubscriptionOperationInProgress = false
        }

        do {
            _ = try await promotionCodeRedeemer.redeemPromotionCode(normalizedCode)
            isWaitingForSubscriptionReconciliation = true
            subscriptionReconciliationSource = .redeemCode
            await refreshAccess(for: user)
            await retrySubscriptionReconciliationIfNeeded(for: user)
        } catch let error as AutonomoSubscriptionPurchaseError {
            subscriptionError = error
            throw error
        } catch {
            let mappedError = AutonomoSubscriptionPurchaseError.underlying(error.localizedDescription)
            subscriptionError = mappedError
            throw mappedError
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
        publishAccessSnapshot(for: resolvedAccess)

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

    private func publishAccessSnapshot(for resolvedAccess: AutonomoResolvedAccess) {
        guard resolvedAccess.accessMode == .signedInPro, resolvedAccess.capabilities.canUseIntake else {
            AutonomoAVAccessSnapshotStore.clear()
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
