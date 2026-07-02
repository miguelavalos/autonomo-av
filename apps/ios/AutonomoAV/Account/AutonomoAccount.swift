import AccountAV
import Foundation
import Observation

struct AutonomoAccountUser: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let emailAddress: String?
}

@MainActor
protocol AutonomoAccountServicing {
    var isAvailable: Bool { get }
    var providerSessionUser: AccountAVUser? { get }

    func restoreSession() async -> AccountAVSessionRestoreResult
    func getToken() async throws -> String?
    func signInWithApple() async throws
    func signInWithGoogle() async throws
    func signOut() async throws
}

@MainActor
struct DefaultAutonomoAccountService: AutonomoAccountServicing {
    private let service = ClerkAccountAVService(
        publishableKeyProvider: { AppConfig.accountPublishableKey },
        keychainServiceProvider: { AutonomoAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_SERVICE") },
        keychainAccessGroupProvider: { AutonomoAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_ACCESS_GROUP") },
        fallbackDisplayName: "Autonomo AV",
        loggerSubsystem: "com.avalsys.autonomoav"
    )

    var isAvailable: Bool {
        service.isAvailable
    }

    var providerSessionUser: AccountAVUser? {
        service.providerSessionUser
    }

    func restoreSession() async -> AccountAVSessionRestoreResult {
        await service.restoreSession()
    }

    func getToken() async throws -> String? {
        try await service.getToken()
    }

    func signInWithApple() async throws {
        try await service.signInWithApple()
    }

    func signInWithGoogle() async throws {
        try await service.signInWithGoogle()
    }

    func signOut() async throws {
        try await service.signOut()
    }
}

@MainActor
protocol AccountProfileResolving {
    func resolveCurrentAccountUser() async throws -> AutonomoAccountUser
}

@MainActor
struct PlatformAccountProfileResolver: AccountProfileResolving {
    let apiClient: AutonomoAPIClient

    func resolveCurrentAccountUser() async throws -> AutonomoAccountUser {
        let response = try await apiClient.fetchAccountSummary()
        let displayName: String
        if let resolvedDisplayName = response.displayName, !resolvedDisplayName.isEmpty {
            displayName = resolvedDisplayName
        } else {
            displayName = L10n.string("app.name")
        }
        return AutonomoAccountUser(
            id: response.id,
            displayName: displayName,
            emailAddress: response.emailAddress
        )
    }
}

enum AccountState: Equatable {
    case restoring
    case signedOut
    case temporarilyUnavailable(AutonomoAccountUser?)
    case signedIn(AutonomoAccountUser)

    var user: AutonomoAccountUser? {
        switch self {
        case .signedIn(let user), .temporarilyUnavailable(let user?):
            return user
        case .restoring, .signedOut, .temporarilyUnavailable(nil):
            return nil
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

@MainActor
@Observable
final class AccountController {
    private let accountService: AutonomoAccountServicing
    private let profileResolver: AccountProfileResolving
    private let userDefaults: UserDefaults
    private let lastKnownUserKey = "autonomoav.account.lastKnownUser"

    private(set) var state: AccountState = .restoring
    var lastErrorMessage: String?
    private(set) var isAuthenticating = false

    init(
        accountService: AutonomoAccountServicing,
        profileResolver: AccountProfileResolving,
        userDefaults: UserDefaults = .standard
    ) {
        self.accountService = accountService
        self.profileResolver = profileResolver
        self.userDefaults = userDefaults
        state = .temporarilyUnavailable(Self.lastKnownUser(from: userDefaults))
    }

    var accountIsAvailable: Bool {
        accountService.isAvailable
    }

    var currentUser: AutonomoAccountUser? {
        state.user
    }

    func restore() async {
        state = .restoring
        await syncFromAccountProvider()
    }

    func syncFromAccountProvider() async {
        switch await accountService.restoreSession() {
        case .signedOut, .invalidated:
            clearAccountState()
        case .temporarilyUnavailable:
            state = .temporarilyUnavailable(Self.lastKnownUser(from: userDefaults))
        case .active:
            await resolveInternalUser(presentsError: false)
        }
    }

    func signInWithApple() async {
        await runAuthentication {
            try await accountService.signInWithApple()
        }
    }

    func signInWithGoogle() async {
        await runAuthentication {
            try await accountService.signInWithGoogle()
        }
    }

    func signOut() async {
        do {
            try await accountService.signOut()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        clearAccountState()
    }

    private func runAuthentication(_ operation: () async throws -> Void) async {
        guard accountService.isAvailable else {
            lastErrorMessage = L10n.string("auth.unavailable")
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await operation()
            await resolveInternalUser(presentsError: true)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func resolveInternalUser(presentsError: Bool) async {
        do {
            let user = try await profileResolver.resolveCurrentAccountUser()
            state = .signedIn(user)
            persistLastKnownUser(user)
            lastErrorMessage = nil
        } catch {
            state = .temporarilyUnavailable(Self.lastKnownUser(from: userDefaults))
            if presentsError {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func clearAccountState() {
        state = .signedOut
        userDefaults.removeObject(forKey: lastKnownUserKey)
    }

    private func persistLastKnownUser(_ user: AutonomoAccountUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        userDefaults.set(data, forKey: lastKnownUserKey)
    }

    private static func lastKnownUser(from userDefaults: UserDefaults) -> AutonomoAccountUser? {
        guard let data = userDefaults.data(forKey: "autonomoav.account.lastKnownUser") else {
            return nil
        }
        return try? JSONDecoder().decode(AutonomoAccountUser.self, from: data)
    }
}
