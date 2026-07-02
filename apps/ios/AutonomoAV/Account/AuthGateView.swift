import SwiftUI

struct AuthGateView: View {
    @Environment(AccountController.self) private var accountController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Spacer(minLength: 20)

                    Image("AutonomoLaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 276)
                        .accessibilityLabel(L10n.string("app.name"))

                    Image("AutonomoSplashHero")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 352, maxHeight: 176)
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

                    AutonomoProOnboardingCard()

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

private struct AutonomoProOnboardingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(L10n.string("auth.pro.badge"), systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AutonomoTheme.accentDeep)

                Spacer(minLength: 10)

                Text(L10n.string("auth.pro.monthly"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AutonomoTheme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AutonomoTheme.surfaceMuted, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                AutonomoProBenefitRow(
                    systemImage: "tray.and.arrow.down.fill",
                    text: L10n.string("auth.pro.inbox")
                )
                AutonomoProBenefitRow(
                    systemImage: "sparkles",
                    text: L10n.string("auth.pro.ai")
                )
                AutonomoProBenefitRow(
                    systemImage: "creditcard.fill",
                    text: L10n.string("auth.pro.access")
                )
            }
        }
        .padding(14)
        .background(AutonomoTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AutonomoTheme.border, lineWidth: 1)
        }
    }
}

private struct AutonomoProBenefitRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AutonomoTheme.accentDeep)
                .frame(width: 22, height: 22)

            Text(text)
                .font(.footnote.weight(.bold))
                .foregroundStyle(AutonomoTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    AuthGateView()
        .environment(AccountController(
            accountService: PreviewAccountService(),
            profileResolver: PreviewAccountResolver()
        ))
}
