import SwiftUI

struct AutonomoAVMacSidebarView: View {
    let model: AutonomoAVMacModel

    var body: some View {
        List {
            Section("Account") {
                Label(model.accountStatusText, systemImage: model.currentAccountUser == nil ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.checkmark")
                    .lineLimit(1)

                if model.currentAccountUser == nil {
                    Button {
                        Task { await model.signInWithApple() }
                    } label: {
                        Label("Sign in with Apple", systemImage: "apple.logo")
                    }
                    .disabled(model.accountController.isAuthenticating)

                    Button {
                        Task { await model.signInWithGoogle() }
                    } label: {
                        Label("Sign in with Google", systemImage: "person.badge.key")
                    }
                    .disabled(model.accountController.isAuthenticating)
                } else {
                    Button {
                        Task { await model.signOut() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(model.accountController.isAuthenticating)
                }
            }

            Section("Queue") {
                Label("\(model.pendingCount) pending", systemImage: "clock")
                Label("\(model.uploadedCount) uploaded", systemImage: "checkmark.circle")
                Label("\(model.failedCount) failed", systemImage: "exclamationmark.triangle")
            }

            if let lastErrorMessage = model.lastErrorMessage {
                Section("Status") {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Autonomo AV")
    }
}
