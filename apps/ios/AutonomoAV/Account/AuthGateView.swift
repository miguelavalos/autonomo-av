import SwiftUI

struct AuthGateView: View {
    @Environment(AccountController.self) private var accountController

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 32)

                VStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(AutonomoTheme.accent)
                        .frame(width: 72, height: 72)
                        .background(AutonomoTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text(L10n.string("auth.title"))
                        .font(.system(size: 26, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(L10n.string("auth.subtitle"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await accountController.signInWithApple() }
                    } label: {
                        Label(L10n.string("auth.apple"), systemImage: "apple.logo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!accountController.accountIsAvailable || accountController.isAuthenticating)

                    Button {
                        Task { await accountController.signInWithGoogle() }
                    } label: {
                        Label(L10n.string("auth.google"), systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!accountController.accountIsAvailable || accountController.isAuthenticating)
                }

                if !accountController.accountIsAvailable {
                    Text(L10n.string("auth.unavailable"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 32)
            }
            .padding(24)
            .navigationTitle(L10n.string("app.name"))
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
