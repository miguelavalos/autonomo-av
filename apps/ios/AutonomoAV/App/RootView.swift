import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AccountController.self) private var accountController
    @Environment(IntakeStore.self) private var intakeStore

    var body: some View {
        Group {
            switch accountController.state {
            case .restoring:
                ProgressView()
                    .controlSize(.large)
            case .signedIn:
                IntakeShellView()
            case .signedOut, .temporarilyUnavailable:
                AuthGateView()
            }
        }
        .task {
            await accountController.restore()
        }
        .task(id: accountController.state.isSignedIn) {
            guard accountController.state.isSignedIn else { return }
            await syncSignedInIntake()
            await intakeStore.uploadPending()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await accountController.syncFromAccountProvider()
            guard accountController.state.isSignedIn else { return }
            await syncSignedInIntake()
        }
    }

    private func syncSignedInIntake() async {
        await intakeStore.importSharedInboxItems()
        await intakeStore.refreshRemoteDocuments()
    }
}
