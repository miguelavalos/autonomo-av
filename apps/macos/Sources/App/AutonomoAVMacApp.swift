import AppKit
import SwiftUI

@main
struct AutonomoAVMacApp: App {
    @NSApplicationDelegateAdaptor(AutonomoAVMacAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AutonomoAVMacModel()

    init() {
        AppConfig.configureAccountAVIfPossible()
    }

    var body: some Scene {
        WindowGroup("Autonomo AV", id: "main") {
            AutonomoAVMacRootView(model: model)
                .frame(minWidth: 980, minHeight: 620)
                .task {
                    appDelegate.configureFileService { urls in
                        AutonomoAVMacTelemetry.services.info("Services import handler invoked count=\(urls.count, privacy: .public)")
                        AutonomoAVMacAppDelegate.bringMainWindowForward()
                        Task { await model.importFiles(urls, source: .macosService) }
                    }
                    await model.restoreAccount()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    AutonomoAVMacTelemetry.app.info("Scene became active")
                    Task { await model.syncSignedInIntake() }
                }
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    AutonomoAVMacTelemetry.intake.info("Open file URL received")
                    AutonomoAVMacAppDelegate.bringMainWindowForward()
                    Task { await model.importFiles([url], source: .macosFiles) }
                }
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandMenu("Intake") {
                Button("Import Files") {
                    AutonomoAVMacTelemetry.intake.info("Import files command selected")
                    Task { await model.pickAndImportFiles(source: .macosFiles) }
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Upload Pending") {
                    AutonomoAVMacTelemetry.intake.info("Upload pending command selected")
                    Task { await model.uploadPending() }
                }
                .keyboardShortcut("u", modifiers: [.command])
                .disabled(!model.hasUploadableItems)

                Button("Refresh Inbox") {
                    AutonomoAVMacTelemetry.intake.info("Refresh inbox command selected")
                    Task { await model.syncSignedInIntake() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra("Autonomo AV", systemImage: "tray.and.arrow.up") {
            AutonomoAVMacMenuBarView(model: model)
        }

        Settings {
            AutonomoAVMacSettingsView()
        }
    }
}

@MainActor
final class AutonomoAVMacAppDelegate: NSObject, NSApplicationDelegate {
    private let fileServiceProvider = AutonomoAVMacFileServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AutonomoAVMacTelemetry.app.info("Application finished launching")
        NSApp.servicesProvider = fileServiceProvider
        NSUpdateDynamicServices()
        NSApp.setActivationPolicy(.regular)
        Self.bringMainWindowForward()
    }

    func configureFileService(importHandler: @escaping ([URL]) -> Void) {
        AutonomoAVMacTelemetry.services.info("Configuring Services provider")
        fileServiceProvider.importHandler = importHandler
        NSApp.servicesProvider = fileServiceProvider
        NSUpdateDynamicServices()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AutonomoAVMacTelemetry.app.info("Application reopen requested hasVisibleWindows=\(flag, privacy: .public)")
        Self.bringMainWindowForward()
        return true
    }

    static func bringMainWindowForward() {
        NSApp.unhide(nil)
        DispatchQueue.main.async {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.windows
                .filter { $0.canBecomeKey || $0.canBecomeMain }
                .forEach { window in
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
                    window.makeKeyAndOrderFront(nil)
                }
        }
    }
}
