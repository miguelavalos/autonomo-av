import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AccountController.self) private var accountController
    @Environment(AutonomoAccessController.self) private var accessController
    @Environment(IntakeStore.self) private var intakeStore

    var body: some View {
        Group {
            switch accountController.state {
            case .restoring:
                AutonomoLaunchStateView()
            case .signedIn:
                AutonomoAppShellView()
            case .signedOut, .temporarilyUnavailable:
                AuthGateView()
            }
        }
        .task {
            await accountController.restore()
        }
        .task(id: accountController.state.isSignedIn) {
            await accessController.refreshAccess(for: accountController.currentUser)
            guard accountController.state.isSignedIn, accessController.hasProAccess else { return }
            await syncSignedInIntake()
            await intakeStore.uploadPending()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await accountController.syncFromAccountProvider()
            await accessController.refreshAccess(for: accountController.currentUser)
            guard accountController.state.isSignedIn, accessController.hasProAccess else { return }
            await syncSignedInIntake()
        }
        .onChange(of: accessController.hasProAccess) { _, hasProAccess in
            guard hasProAccess else { return }
            Task {
                await syncSignedInIntake()
                await intakeStore.uploadPending()
            }
        }
    }

    private func syncSignedInIntake() async {
        await intakeStore.importSharedInboxItems()
        await intakeStore.refreshRemoteDocuments()
    }
}
