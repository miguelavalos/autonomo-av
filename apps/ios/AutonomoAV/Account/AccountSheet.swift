import SwiftUI

struct AccountScreen: View {
    @Environment(AccountController.self) private var accountController
    @Environment(AutonomoAccessController.self) private var accessController
    let showProPaywall: () -> Void

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

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(planTitle)
                                .font(.headline)
                            Text(planDetail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(AutonomoTheme.accentDeep)
                    }

                    if !accessController.hasProAccess {
                        Button(action: showProPaywall) {
                            Label(L10n.string("profile.pro.viewOffer"), systemImage: "sparkles")
                        }
                    }
                } header: {
                    Text(L10n.string("profile.pro.title"))
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await accountController.signOut()
                        }
                    } label: {
                        Label(L10n.string("account.signOut"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle(L10n.string("tab.account"))
            .scrollContentBackground(.hidden)
            .background(AutonomoTheme.background.ignoresSafeArea())
        }
    }

    private var planTitle: String {
        accessController.hasProAccess
            ? L10n.string("profile.pro.active.title")
            : L10n.string("profile.pro.ready.title")
    }

    private var planDetail: String {
        accessController.hasProAccess
            ? L10n.string("profile.pro.active.detail")
            : L10n.string("profile.pro.ready.detail")
    }
}

struct AccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AccountScreen(showProPaywall: {})
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("auth.close")) {
                        dismiss()
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
