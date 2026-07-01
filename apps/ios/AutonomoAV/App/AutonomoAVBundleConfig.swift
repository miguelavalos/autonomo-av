import AccountAV
import Foundation

enum AutonomoAVBundleConfig {
    static func stringValue(for key: String, in bundle: Bundle = .main) -> String {
        nonEmptyStringValue(for: key, in: bundle) ?? ""
    }

    static func nonEmptyStringValue(for key: String, in bundle: Bundle = .main) -> String? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "$(inherited)" {
            return nil
        }
        return trimmed
    }

    static func urlValue(for key: String, in bundle: Bundle = .main) -> URL? {
        guard let rawValue = nonEmptyStringValue(for: key, in: bundle) else {
            return nil
        }
        return URL(string: rawValue)
    }

    static func supportURL(explicitURL: URL?, email: String?) -> URL? {
        if let explicitURL {
            return explicitURL
        }
        guard let email else { return nil }
        let subject = "Autonomo AV Support".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Autonomo%20AV%20Support"
        return URL(string: "mailto:\(email)?subject=\(subject)")
    }
}

@MainActor
enum AppConfig {
    static var accountPublishableKey: String {
        AutonomoAVBundleConfig.stringValue(for: "ACCOUNTAV_PUBLISHABLE_KEY")
    }

    static var accountAPIBaseURL: URL? {
        AutonomoAVBundleConfig.urlValue(for: "ACCOUNTAV_API_BASE_URL")
    }

    static var autonomoAPIBaseURL: URL? {
        AutonomoAVBundleConfig.urlValue(for: "AUTONOMOAV_API_BASE_URL") ?? accountAPIBaseURL
    }

    static var appGroupIdentifier: String? {
        AutonomoAVBundleConfig.nonEmptyStringValue(for: "AUTONOMOAV_APP_GROUP_IDENTIFIER")
    }

    static var accountManagementURL: URL? {
        AutonomoAVBundleConfig.urlValue(for: "ACCOUNTAV_MANAGEMENT_URL")
    }

    static var deleteAccountURL: URL? {
        AutonomoAVBundleConfig.urlValue(for: "AUTONOMOAV_DELETE_ACCOUNT_URL") ?? accountManagementURL
    }

    static var termsURL: URL? {
        AutonomoAVBundleConfig.urlValue(for: "AUTONOMOAV_TERMS_URL")
    }

    static var privacyURL: URL? {
        AutonomoAVBundleConfig.urlValue(for: "AUTONOMOAV_PRIVACY_URL")
    }

    static var supportURL: URL? {
        AutonomoAVBundleConfig.supportURL(
            explicitURL: AutonomoAVBundleConfig.urlValue(for: "SUPPORTAV_BASE_URL"),
            email: AutonomoAVBundleConfig.nonEmptyStringValue(for: "SUPPORT_EMAIL_TO")
        )
    }

    static var isAccountAvailable: Bool {
        !accountPublishableKey.isEmpty
    }

    static func configureAccountAVIfPossible() {
        AccountAVClerk.configureIfPossible(
            publishableKey: accountPublishableKey,
            keychainService: AutonomoAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_SERVICE"),
            keychainAccessGroup: AutonomoAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_ACCESS_GROUP")
        )
    }
}
