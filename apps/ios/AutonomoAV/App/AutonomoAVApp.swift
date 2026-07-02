import AVSettingsFoundation
import SwiftUI

@main
struct AutonomoAVApp: App {
    @State private var accountController: AccountController
    @State private var accessController: AutonomoAccessController
    @State private var intakeStore: IntakeStore

    init() {
        AppConfig.configureAccountAVIfPossible()
        let accountService = DefaultAutonomoAccountService()
        let apiClient = AutonomoAPIClient(
            tokenProvider: { try await accountService.getToken() }
        )
        _accountController = State(initialValue: AccountController(
            accountService: accountService,
            profileResolver: PlatformAccountProfileResolver(apiClient: apiClient)
        ))
        _accessController = State(initialValue: AutonomoAccessController(apiClient: apiClient))
        _intakeStore = State(initialValue: IntakeStore(client: apiClient))
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
