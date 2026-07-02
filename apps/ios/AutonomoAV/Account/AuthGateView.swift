import SwiftUI

struct AuthGateView: View {
    @Environment(AccountController.self) private var accountController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 20)

                    Image("AutonomoLaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 292)
                        .accessibilityLabel(L10n.string("app.name"))

                    Image("AutonomoSplashHero")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 340, maxHeight: 220)
                        .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text(L10n.string("auth.title"))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(AutonomoTheme.ink)
                            .multilineTextAlignment(.center)

                        Text(L10n.string("auth.subtitle"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AutonomoTheme.graphite)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AutonomoAviBriefCard(
                        title: L10n.string("auth.avi.title"),
                        detail: L10n.string("auth.avi.detail")
                    )

                    VStack(spacing: 12) {
                        Button {
                            Task { await accountController.signInWithApple() }
                        } label: {
                            Label(L10n.string("auth.apple"), systemImage: "apple.logo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AutonomoTheme.ink)
                        .controlSize(.large)
                        .disabled(!accountController.accountIsAvailable || accountController.isAuthenticating)

                        Button {
                            Task { await accountController.signInWithGoogle() }
                        } label: {
                            Label(L10n.string("auth.google"), systemImage: "globe")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AutonomoTheme.ink)
                        .controlSize(.large)
                        .disabled(!accountController.accountIsAvailable || accountController.isAuthenticating)
                    }

                    if !accountController.accountIsAvailable {
                        Text(L10n.string("auth.unavailable"))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AutonomoTheme.graphite)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: 20)
                }
                .padding(24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .background(AutonomoTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert(L10n.string("auth.failed.title"), isPresented: errorIsPresented) {
            Button(L10n.string("auth.close"), role: .cancel) {
                accountController.lastErrorMessage = nil
            }
        } message: {
            Text(accountController.lastErrorMessage ?? "")
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
}

#Preview {
    AuthGateView()
        .environment(AccountController(
            accountService: PreviewAccountService(),
            profileResolver: PreviewAccountResolver()
        ))
}
