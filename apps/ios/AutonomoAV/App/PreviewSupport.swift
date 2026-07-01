import AccountAV
import Foundation

@MainActor
struct PreviewAccountService: AutonomoAccountServicing {
    var isAvailable: Bool { true }
    var providerSessionUser: AccountAVUser? {
        AccountAVUser(id: "provider_preview", displayName: "Preview User", emailAddress: "preview@example.com")
    }

    func restoreSession() async -> AccountAVSessionRestoreResult {
        .active(providerSessionUser!)
    }

    func getToken() async throws -> String? {
        "preview-token"
    }

    func signInWithApple() async throws {}
    func signInWithGoogle() async throws {}
    func signOut() async throws {}
}

@MainActor
struct PreviewAccountResolver: AccountProfileResolving {
    func resolveCurrentAccountUser() async throws -> AutonomoAccountUser {
        AutonomoAccountUser(id: "user_preview", displayName: "Preview User", emailAddress: "preview@example.com")
    }
}
