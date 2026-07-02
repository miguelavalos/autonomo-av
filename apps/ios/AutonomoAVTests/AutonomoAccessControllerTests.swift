import XCTest
@testable import AutonomoAV

@MainActor
final class AutonomoAccessControllerTests: XCTestCase {
    func testGuestRemainsGuestWhenDebugForceProModeIsEnabled() async {
        let controller = makeController(
            provider: StubAutonomoAccessProvider(response: .free),
            debugForceProModeIsEnabled: true
        )

        await controller.refreshAccess(for: nil)

        XCTAssertEqual(controller.accessMode, .guest)
        XCTAssertEqual(controller.planTier, .free)
        XCTAssertFalse(controller.hasProAccess)
    }

    func testDebugForceProModeUnlocksSignedInUserWhenBackendReturnsFree() async {
        let controller = makeController(
            provider: StubAutonomoAccessProvider(response: .free),
            debugForceProModeIsEnabled: true
        )

        await controller.refreshAccess(for: user())

        XCTAssertEqual(controller.platformUserId, "apps-av-user-1")
        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertEqual(controller.planTier, .pro)
        XCTAssertTrue(controller.capabilities.canUsePremiumFeatures)
        XCTAssertTrue(controller.hasProAccess)
    }

    func testSignedInUserUsesBackendFreeAccessWhenDebugForceProModeIsDisabled() async {
        let controller = makeController(
            provider: StubAutonomoAccessProvider(response: .free),
            debugForceProModeIsEnabled: false
        )

        await controller.refreshAccess(for: user())

        XCTAssertEqual(controller.accessMode, .signedInFree)
        XCTAssertEqual(controller.planTier, .free)
        XCTAssertFalse(controller.hasProAccess)
    }

    func testDebugForceProModeFallsBackToProWhenBackendIsUnavailable() async {
        let controller = makeController(
            provider: StubAutonomoAccessProvider(response: .free, configured: false),
            debugForceProModeIsEnabled: true
        )

        await controller.refreshAccess(for: user())

        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertEqual(controller.planTier, .pro)
        XCTAssertTrue(controller.hasProAccess)
    }

    func testClaimPromotionCodeRedeemsWithBackendAndRefreshesAccess() async throws {
        let promotionCodeRedeemer = StubAutonomoPromotionCodeRedeemer()
        let controller = makeController(
            provider: StubAutonomoAccessProvider(response: .pro),
            promotionCodeRedeemer: promotionCodeRedeemer,
            debugForceProModeIsEnabled: false
        )

        try await controller.claimPromotionCode(" AUTONOMO-PRO ", for: user())

        XCTAssertEqual(promotionCodeRedeemer.redeemedCodes, ["AUTONOMO-PRO"])
        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertEqual(controller.planTier, .pro)
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)
    }

    func testClaimPromotionCodeSurfacesBackendError() async {
        let promotionCodeRedeemer = StubAutonomoPromotionCodeRedeemer(error: AutonomoPromoCodeClientError.server(
            code: "promo_code_unavailable",
            message: "This promo code is not available.",
            statusCode: 404
        ))
        let controller = makeController(
            provider: StubAutonomoAccessProvider(response: .free),
            promotionCodeRedeemer: promotionCodeRedeemer,
            debugForceProModeIsEnabled: false
        )

        do {
            try await controller.claimPromotionCode("AUTONOMO-PRO", for: user())
            XCTFail("Expected promo redemption to fail.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "This promo code is not available.")
            XCTAssertEqual(controller.subscriptionError?.errorDescription, "This promo code is not available.")
            XCTAssertFalse(controller.isSubscriptionOperationInProgress)
        }
    }

    private func makeController(
        provider: StubAutonomoAccessProvider,
        promotionCodeRedeemer: AutonomoPromotionCodeRedeeming? = nil,
        debugForceProModeIsEnabled: Bool
    ) -> AutonomoAccessController {
        AutonomoAccessController(
            apiClient: provider,
            subscriptionPurchasing: NoopAutonomoSubscriptionPurchasing(),
            promotionCodeRedeemer: promotionCodeRedeemer,
            debugForceProModeProvider: { debugForceProModeIsEnabled },
            subscriptionReconciliationRetryDelaysNanoseconds: []
        )
    }

    private func user() -> AutonomoAccountUser {
        AutonomoAccountUser(
            id: "provider-user-1",
            displayName: "Autonomo User",
            emailAddress: "autonomo@example.com"
        )
    }
}

private final class StubAutonomoPromotionCodeRedeemer: AutonomoPromotionCodeRedeeming {
    private(set) var redeemedCodes: [String] = []
    var error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func redeemPromotionCode(_ code: String) async throws -> AutonomoPromotionCodeRedemptionResponse {
        if let error {
            throw error
        }
        redeemedCodes.append(code)
        return AutonomoPromotionCodeRedemptionResponse(
            appId: AutonomoAPIClient.appIdentifier,
            userId: "apps-av-user-1",
            code: code,
            campaignId: "campaign-1",
            redemptionId: "redemption-1",
            entitlement: AutonomoPromoCodeEntitlement(
                appId: AutonomoAPIClient.appIdentifier,
                userId: "apps-av-user-1",
                planTier: "pro",
                accessMode: "signedInPro",
                status: "active",
                source: "promo"
            )
        )
    }
}

private struct StubAutonomoAccessProvider: AutonomoAccessProviding {
    var response: AutonomoMeAccessResponse
    var configured = true

    var isConfigured: Bool {
        configured
    }

    func fetchMeAccess() async throws -> AutonomoMeAccessResponse {
        response
    }
}

private extension AutonomoMeAccessResponse {
    static let free = AutonomoMeAccessResponse(
        viewer: AutonomoMeAccessViewer(
            isAuthenticated: true,
            userId: "apps-av-user-1",
            identityProvider: "clerk"
        ),
        apps: [
            AutonomoAppAccess(
                appId: AutonomoAPIClient.appIdentifier,
                accessMode: .signedInFree,
                planTier: .free,
                capabilities: .forMode(.signedInFree),
                limits: .forMode(.signedInFree)
            )
        ]
    )

    static let pro = AutonomoMeAccessResponse(
        viewer: AutonomoMeAccessViewer(
            isAuthenticated: true,
            userId: "apps-av-user-1",
            identityProvider: "clerk"
        ),
        apps: [
            AutonomoAppAccess(
                appId: AutonomoAPIClient.appIdentifier,
                accessMode: .signedInPro,
                planTier: .pro,
                capabilities: .forMode(.signedInPro),
                limits: .forMode(.signedInPro)
            )
        ]
    )
}
