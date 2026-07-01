import SwiftUI

struct AccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountController.self) private var accountController

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let user = accountController.currentUser {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.headline)
                                if let emailAddress = user.emailAddress {
                                    Text(emailAddress)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(AutonomoTheme.accent)
                        }
                    } else {
                        Text(L10n.string("account.temporary"))
                    }
                } header: {
                    Text(L10n.string("account.signedIn"))
                }

                Section(L10n.string("settings.links")) {
                    LinkRow(title: L10n.string("settings.support"), systemImage: "lifepreserver", url: AppConfig.supportURL)
                    LinkRow(title: L10n.string("settings.privacy"), systemImage: "hand.raised", url: AppConfig.privacyURL)
                    LinkRow(title: L10n.string("settings.terms"), systemImage: "doc.text", url: AppConfig.termsURL)
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await accountController.signOut()
                            dismiss()
                        }
                    } label: {
                        Label(L10n.string("account.signOut"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle(L10n.string("shell.account"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("auth.close")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LinkRow: View {
    let title: String
    let systemImage: String
    let url: URL?

    var body: some View {
        if let url {
            Link(destination: url) {
                Label(title, systemImage: systemImage)
            }
        }
    }
}
