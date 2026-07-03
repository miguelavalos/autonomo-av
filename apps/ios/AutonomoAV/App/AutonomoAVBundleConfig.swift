import AccountAV
import AVBrandFoundation
import AVDiagnosticsFoundation
import AVSettingsFoundation
import Foundation
import SwiftUI

enum AutonomoAVBundleConfig {
    static func stringValue(for key: String, in bundle: Bundle = .main) -> String {
        nonEmptyStringValue(for: key, in: bundle) ?? ""
    }

    static func boolValue(for key: String, in bundle: Bundle = .main, default defaultValue: Bool = false) -> Bool {
        guard let rawValue = nonEmptyStringValue(for: key, in: bundle) else {
            return defaultValue
        }

        switch rawValue.lowercased() {
        case "1", "true", "yes", "on", "enabled":
            return true
        case "0", "false", "no", "off", "disabled":
            return false
        default:
            return defaultValue
        }
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

    static var revenueCatPublicAPIKey: String? {
        AutonomoAVBundleConfig.nonEmptyStringValue(for: "AUTONOMOAV_REVENUECAT_PUBLIC_API_KEY")
    }

    static var revenueCatOfferingID: String? {
        AutonomoAVBundleConfig.nonEmptyStringValue(for: "AUTONOMOAV_REVENUECAT_OFFERING_ID")
    }

    static var revenueCatMonthlyPackageID: String? {
        AutonomoAVBundleConfig.nonEmptyStringValue(for: "AUTONOMOAV_REVENUECAT_MONTHLY_PACKAGE_ID")
    }

    static var isDebugForceProModeEnabled: Bool {
        AutonomoAVBundleConfig.boolValue(for: "AUTONOMOAV_DEBUG_FORCE_PRO_MODE")
    }

    static var diagnosticsConfiguration: AVDiagnosticsConfiguration {
        AVDiagnosticsConfiguration(
            dsn: diagnosticsDSN,
            environment: diagnosticsEnvironment,
            releaseName: diagnosticsReleaseName,
            tracesSampleRate: 0,
            isEnabled: isDiagnosticsEnabled
        )
    }

    static var isAccountAvailable: Bool {
        !accountPublishableKey.isEmpty
    }

    static var commonAppExperience: AVCommonAppExperience {
        let identity = AVAppIdentity(
            displayName: "Autonomo AV",
            shortName: "Autonomo",
            assistantName: "Avi",
            accountName: "Account AV"
        )
        return AVCommonAppExperience(
            identity: identity,
            legalLinks: AVAppLegalLinks(
                supportURL: supportURL,
                privacyURL: privacyURL,
                termsURL: termsURL,
                accountDeletionURL: deleteAccountURL
            ),
            brandPalette: AVBrandPalette(
                ink: AutonomoTheme.ink,
                accent: AutonomoTheme.accent,
                canvas: AutonomoTheme.background,
                launchSurfaceStart: AutonomoTheme.background,
                launchSurfaceMid: AutonomoTheme.surface
            ),
            visualAssets: AVCommonAppVisualAssets(
                headerLogoName: "AutonomoHeaderWordmark",
                splashLogoName: "AutonomoLaunchScreenLogo",
                splashHeroName: "AutonomoSplashHero",
                onboardingBrandName: "AutonomoLaunchLogo",
                onboardingHeroName: "AutonomoOnboardingHero",
                onboardingCTACompanionName: "AviOnboardingCTA",
                onboardingAuthPanelCompanionName: "AviLoginSheetPeek",
                footerAssistantName: "AviAutonomoAssistant"
            ),
            splashTagline: L10n.string("splash.tagline"),
            splashStatus: L10n.string("splash.status"),
            onboardingTitle: L10n.string("onboarding.title"),
            onboardingSubtitle: L10n.string("onboarding.subtitle"),
            onboardingPrimaryTitle: L10n.string("onboarding.primary"),
            onboardingSecondaryTitle: L10n.string("onboarding.proInfo"),
            onboardingBackgroundStart: AutonomoTheme.background,
            onboardingBackgroundMid: AutonomoTheme.surface,
            onboardingBackgroundEnd: AutonomoTheme.surfaceMuted
        )
    }

    static func configureAccountAVIfPossible() {
        AccountAVClerk.configureIfPossible(
            publishableKey: accountPublishableKey,
            keychainService: AutonomoAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_SERVICE"),
            keychainAccessGroup: AutonomoAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_ACCESS_GROUP")
        )
    }

    private static var diagnosticsEnvironment: AVDiagnosticsEnvironment {
        switch AutonomoAVBundleConfig.stringValue(for: "AUTONOMOAV_CONFIG_ENVIRONMENT").lowercased() {
        case "prod", "production":
            return .production
        case "staging", "preview":
            return .preview
        case "dev", "debug":
            return .debug
        default:
            return .debug
        }
    }

    private static var diagnosticsReleaseName: String? {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.avalsys.autonomoav"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(bundleIdentifier)@\(version)+\(build)"
    }

    private static var diagnosticsDSN: String {
        AutonomoAVBundleConfig.stringValue(for: "AUTONOMOAV_IOS_SENTRY_DSN")
    }

    private static var isDiagnosticsEnabled: Bool {
        #if DEBUG
        false
        #else
        !diagnosticsDSN.isEmpty
        #endif
    }
}
