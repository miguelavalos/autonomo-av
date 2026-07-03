import SwiftUI

struct AutonomoAVMacMenuBarView: View {
    let model: AutonomoAVMacModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Inbox") {
            openWindow(id: "main")
            AutonomoAVMacAppDelegate.bringMainWindowForward()
        }

        Button("Import Files") {
            openWindow(id: "main")
            Task { await model.pickAndImportFiles(source: .macosFiles) }
        }

        Button("Upload Pending") {
            Task { await model.syncSignedInIntake() }
        }
        .disabled(!model.accountIsSignedIn || model.isUploading || model.isImportingSharedInbox)

        Divider()

        Text("\(model.pendingCount) pending")
        Text(model.accountStatusText)

        Divider()

        SettingsLink {
            Text("Settings")
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
