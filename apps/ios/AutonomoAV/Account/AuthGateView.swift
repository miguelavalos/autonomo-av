import AVSettingsFoundation
import SwiftUI

struct AuthGateView: View {
    @Environment(AccountController.self) private var accountController
    @State private var authOptionsArePresented = false
    @State private var activeProvider: AVAuthProvider?
    @State private var isShowingProPaywall = false

    var body: some View {
        AVAuthConfiguredOnboardingScreen(
            authOptionsArePresented: $authOptionsArePresented,
            primaryAction: showAuthOptions,
            secondaryAction: showProPaywall,
            brandWidth: 160,
            ctaCompanionOffset: CGSize(width: -2, height: -112),
            heroArtwork: {
                AutonomoOnboardingHeroArtwork()
            },
            authPanel: {
                AuthOptionsPanel(
                    accountIsAvailable: accountController.accountIsAvailable,
                    activeProvider: activeProvider,
                    onAppleTap: startAppleSignIn,
                    onGoogleTap: startGoogleSignIn
                )
            }
        )
        .alert(L10n.string("auth.failed.title"), isPresented: errorIsPresented) {
            Button(L10n.string("auth.close"), role: .cancel) {
                accountController.lastErrorMessage = nil
            }
        } message: {
            Text(accountController.lastErrorMessage ?? "")
        }
        .sheet(isPresented: $isShowingProPaywall) {
            AutonomoProPaywallView(startSignInFlow: showAuthOptions)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { accountController.lastErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    accountController.lastErrorMessage = nil
                }
            }
        )
    }

    private func showAuthOptions() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            authOptionsArePresented = true
        }
    }

    private func showProPaywall() {
        isShowingProPaywall = true
    }

    private func startAppleSignIn() {
        startSignIn(provider: .apple) {
            await accountController.signInWithApple()
        }
    }

    private func startGoogleSignIn() {
        startSignIn(provider: .google) {
            await accountController.signInWithGoogle()
        }
    }

    private func startSignIn(provider: AVAuthProvider, operation: @escaping () async -> Void) {
        guard accountController.accountIsAvailable else {
            accountController.lastErrorMessage = L10n.string("auth.unavailable")
            return
        }
        guard activeProvider == nil else { return }

        activeProvider = provider
        Task { @MainActor in
            await operation()
            activeProvider = nil
            if accountController.state.isSignedIn {
                authOptionsArePresented = false
            }
        }
    }
}

private struct AutonomoOnboardingHeroArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: min(proxy.size.height * 0.34, 285))

                Image("AutonomoSplashHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(proxy.size.width * 0.92, 360))
                    .opacity(0.84)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

private struct AuthOptionsPanel: View {
    let accountIsAvailable: Bool
    let activeProvider: AVAuthProvider?
    let onAppleTap: () -> Void
    let onGoogleTap: () -> Void

    var body: some View {
        AVAuthOptionsPanel(
            title: L10n.string("auth.options.title"),
            subtitle: L10n.string("auth.options.subtitle"),
            legalConsentText: legalConsentText,
            unavailableMessage: accountIsAvailable ? nil : L10n.string("auth.unavailable"),
            skipTitle: nil,
            appleTitle: L10n.string("auth.apple"),
            googleTitle: L10n.string("auth.google"),
            isBusy: activeProvider != nil,
            activeProvider: activeProvider,
            isAvailable: accountIsAvailable,
            appleAccessibilityIdentifier: "autonomo.onboarding.auth.apple",
            googleAccessibilityIdentifier: "autonomo.onboarding.auth.google",
            onApple: onAppleTap,
            onGoogle: onGoogleTap
        ) {
            AVAuthConfiguredCompanionArtwork(
                placement: .authPanel,
                imageWidth: 126,
                imageHeight: 126,
                frameWidth: 140,
                frameHeight: 110,
                imageOffset: CGSize(width: 0, height: -5),
                groundShadowColor: nil
            )
            .offset(x: -44, y: -91)
            .allowsHitTesting(false)
        }
    }

    private var legalConsentText: AttributedString {
        let termsURL = AppConfig.termsURL?.absoluteString ?? "https://www.avalsys.com/account-av/autonomo-av/terms"
        let privacyURL = AppConfig.privacyURL?.absoluteString ?? "https://www.avalsys.com/account-av/autonomo-av/privacy"
        let markdown = L10n.string("auth.legal.markdown", termsURL, privacyURL)
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(L10n.string("auth.legal.fallback"))
    }
}

#Preview {
    AuthGateView()
        .environment(AccountController(
            accountService: PreviewAccountService(),
            profileResolver: PreviewAccountResolver()
        ))
}
