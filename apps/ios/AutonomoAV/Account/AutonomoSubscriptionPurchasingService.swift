import Foundation
import OSLog

#if canImport(RevenueCat)
import RevenueCat
#endif

struct AutonomoSubscriptionOffer: Equatable {
    let identifier: String
    let productIdentifier: String
    let localizedTitle: String
    let localizedPrice: String
}

struct AutonomoPurchaseOutcome: Equatable {
    let shouldRefreshAccess: Bool
    let customerUserID: String
}

enum AutonomoSubscriptionPurchaseError: LocalizedError, Equatable {
    case missingAccountUser
    case missingConfiguration
    case offeringUnavailable
    case monthlyPackageUnavailable
    case purchaseCancelled
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .missingAccountUser:
            L10n.string("subscription.error.signInRequired")
        case .missingConfiguration:
            L10n.string("subscription.error.configuration")
        case .offeringUnavailable:
            L10n.string("subscription.error.offerUnavailable")
        case .monthlyPackageUnavailable:
            L10n.string("subscription.error.productUnavailable")
        case .purchaseCancelled:
            L10n.string("subscription.error.cancelled")
        case .underlying(let message):
            message
        }
    }
}

@MainActor
protocol AutonomoSubscriptionPurchasing {
    func prepare(for user: AutonomoAccountUser?) async throws
    func loadMonthlyOffer(for user: AutonomoAccountUser?) async throws -> AutonomoSubscriptionOffer
    func purchaseMonthlyPro(for user: AutonomoAccountUser?) async throws -> AutonomoPurchaseOutcome
    func restorePurchases(for user: AutonomoAccountUser?) async throws -> AutonomoPurchaseOutcome
}

@MainActor
final class NoopAutonomoSubscriptionPurchasing: AutonomoSubscriptionPurchasing {
    func prepare(for user: AutonomoAccountUser?) async throws {
        guard user != nil else {
            throw AutonomoSubscriptionPurchaseError.missingAccountUser
        }
        throw AutonomoSubscriptionPurchaseError.missingConfiguration
    }

    func loadMonthlyOffer(for user: AutonomoAccountUser?) async throws -> AutonomoSubscriptionOffer {
        try await prepare(for: user)
        throw AutonomoSubscriptionPurchaseError.missingConfiguration
    }

    func purchaseMonthlyPro(for user: AutonomoAccountUser?) async throws -> AutonomoPurchaseOutcome {
        try await prepare(for: user)
        throw AutonomoSubscriptionPurchaseError.missingConfiguration
    }

    func restorePurchases(for user: AutonomoAccountUser?) async throws -> AutonomoPurchaseOutcome {
        try await prepare(for: user)
        throw AutonomoSubscriptionPurchaseError.missingConfiguration
    }
}

#if canImport(RevenueCat)
@MainActor
final class RevenueCatAutonomoSubscriptionPurchasing: AutonomoSubscriptionPurchasing {
    private let apiKeyProvider: () -> String?
    private let offeringIDProvider: () -> String?
    private let monthlyPackageIDProvider: () -> String?
    private var configuredUserID: String?
    private let purchaseLogger = Logger(subsystem: "com.avalsys.autonomoav", category: "subscription")

    init(
        apiKeyProvider: @escaping () -> String? = { AppConfig.revenueCatPublicAPIKey },
        offeringIDProvider: @escaping () -> String? = { AppConfig.revenueCatOfferingID },
        monthlyPackageIDProvider: @escaping () -> String? = { AppConfig.revenueCatMonthlyPackageID }
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.offeringIDProvider = offeringIDProvider
        self.monthlyPackageIDProvider = monthlyPackageIDProvider
    }

    func prepare(for user: AutonomoAccountUser?) async throws {
        let userID = try requireUserID(user)
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw AutonomoSubscriptionPurchaseError.missingConfiguration
        }

        if configuredUserID == userID, Purchases.isConfigured {
            return
        }

        if Purchases.isConfigured {
            _ = try await logInRevenueCat(userID)
        } else {
            Purchases.configure(withAPIKey: apiKey, appUserID: userID)
        }
        configuredUserID = userID
    }

    func loadMonthlyOffer(for user: AutonomoAccountUser?) async throws -> AutonomoSubscriptionOffer {
        try await prepare(for: user)
        let package = try await loadMonthlyPackage()
        let productIdentifier = package.storeProduct.productIdentifier
        let localizedPrice = package.storeProduct.localizedPriceString
        purchaseLogger.info(
            "Loaded monthly offer product=\(productIdentifier, privacy: .public) displayPrice=\(localizedPrice, privacy: .public) priceSource=revenuecat"
        )
        return AutonomoSubscriptionOffer(
            identifier: package.identifier,
            productIdentifier: productIdentifier,
            localizedTitle: package.storeProduct.localizedTitle,
            localizedPrice: localizedPrice
        )
    }

    func purchaseMonthlyPro(for user: AutonomoAccountUser?) async throws -> AutonomoPurchaseOutcome {
        let userID = try requireUserID(user)
        try await prepare(for: user)
        let package = try await loadMonthlyPackage()
        purchaseLogger.info(
            "Starting RevenueCat purchase userID=\(userID, privacy: .private) product=\(package.storeProduct.productIdentifier, privacy: .public)"
        )
        let result = try await purchase(package)
        guard !result.userCancelled else {
            throw AutonomoSubscriptionPurchaseError.purchaseCancelled
        }
        purchaseLogger.info(
            "Finished RevenueCat purchase userID=\(userID, privacy: .private) product=\(package.storeProduct.productIdentifier, privacy: .public)"
        )
        return AutonomoPurchaseOutcome(shouldRefreshAccess: true, customerUserID: userID)
    }

    func restorePurchases(for user: AutonomoAccountUser?) async throws -> AutonomoPurchaseOutcome {
        let userID = try requireUserID(user)
        try await prepare(for: user)
        purchaseLogger.info("Starting RevenueCat restore userID=\(userID, privacy: .private)")
        _ = try await restorePurchases()
        purchaseLogger.info("Finished RevenueCat restore userID=\(userID, privacy: .private)")
        return AutonomoPurchaseOutcome(shouldRefreshAccess: true, customerUserID: userID)
    }

    private func requireUserID(_ user: AutonomoAccountUser?) throws -> String {
        guard let userID = user?.id, !userID.isEmpty else {
            throw AutonomoSubscriptionPurchaseError.missingAccountUser
        }
        return userID
    }

    private func loadMonthlyPackage() async throws -> Package {
        let offerings = try await getOfferings()
        let offering: Offering?
        if let offeringID = offeringIDProvider(), !offeringID.isEmpty {
            offering = offerings.offering(identifier: offeringID)
        } else {
            offering = offerings.current
        }

        guard let offering else {
            throw AutonomoSubscriptionPurchaseError.offeringUnavailable
        }

        if let packageID = monthlyPackageIDProvider(), !packageID.isEmpty,
           let package = offering.package(identifier: packageID) {
            return package
        }

        guard let package = offering.monthly else {
            throw AutonomoSubscriptionPurchaseError.monthlyPackageUnavailable
        }
        return package
    }

    private func getOfferings() async throws -> Offerings {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.getOfferings { offerings, error in
                if let offerings {
                    continuation.resume(returning: offerings)
                } else {
                    continuation.resume(throwing: Self.purchaseError(from: error))
                }
            }
        }
    }

    private func purchase(_ package: Package) async throws -> PurchaseResultData {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.purchase(package: package) { transaction, customerInfo, error, userCancelled in
                if let error {
                    continuation.resume(throwing: Self.purchaseError(from: error))
                } else if let customerInfo {
                    continuation.resume(
                        returning: PurchaseResultData(
                            transaction: transaction,
                            customerInfo: customerInfo,
                            userCancelled: userCancelled
                        )
                    )
                } else {
                    continuation.resume(throwing: Self.purchaseError(from: nil))
                }
            }
        }
    }

    private func restorePurchases() async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.restorePurchases { customerInfo, error in
                if let customerInfo {
                    continuation.resume(returning: customerInfo)
                } else {
                    continuation.resume(throwing: Self.purchaseError(from: error))
                }
            }
        }
    }

    private func logInRevenueCat(_ userID: String) async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.logIn(userID) { customerInfo, _, error in
                if let customerInfo {
                    continuation.resume(returning: customerInfo)
                } else {
                    continuation.resume(throwing: Self.purchaseError(from: error))
                }
            }
        }
    }

    private static func purchaseError(from error: Error?) -> AutonomoSubscriptionPurchaseError {
        if let error {
            return .underlying(error.localizedDescription)
        }
        return .underlying(L10n.string("subscription.error.unknown"))
    }
}
#else
typealias RevenueCatAutonomoSubscriptionPurchasing = NoopAutonomoSubscriptionPurchasing
#endif
