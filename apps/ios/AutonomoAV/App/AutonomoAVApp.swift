import AVDiagnosticsFoundation
import AVSettingsFoundation
import SwiftUI

@main
struct AutonomoAVApp: App {
    @State private var accountController: AccountController
    @State private var accessController: AutonomoAccessController
    @State private var intakeStore: IntakeStore

    init() {
        AppConfig.configureAccountAVIfPossible()
        AVDiagnostics.configure(AppConfig.diagnosticsConfiguration)
        let accountService = DefaultAutonomoAccountService()
        let apiClient = AutonomoAPIClient(
            tokenProvider: { try await accountService.getToken() }
        )
        let promoCodeClient = AutonomoPromoCodeClient(
            baseURL: AppConfig.autonomoAPIBaseURL,
            tokenProvider: { try await accountService.getToken() }
        )
        let accessController = AutonomoAccessController(
            apiClient: apiClient,
            promotionCodeRedeemer: promoCodeClient
        )
        _accountController = State(initialValue: AccountController(
            accountService: accountService,
            profileResolver: PlatformAccountProfileResolver(apiClient: apiClient)
        ))
        _accessController = State(initialValue: accessController)
        _intakeStore = State(initialValue: IntakeStore(
            client: apiClient,
            canUseIntakeProvider: { accessController.hasProAccess }
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(accountController)
                .environment(accessController)
                .environment(intakeStore)
                .avCommonAppExperience(AppConfig.commonAppExperience)
        }
    }
}
