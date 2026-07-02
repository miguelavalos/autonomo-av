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

    private func makeController(
        provider: StubAutonomoAccessProvider,
        debugForceProModeIsEnabled: Bool
    ) -> AutonomoAccessController {
        AutonomoAccessController(
            apiClient: provider,
            subscriptionPurchasing: NoopAutonomoSubscriptionPurchasing(),
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
}
