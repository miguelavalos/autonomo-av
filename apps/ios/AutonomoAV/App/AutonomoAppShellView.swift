import SwiftUI

enum AutonomoRootTab: String, CaseIterable, Identifiable {
    case home
    case settings
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            L10n.string("tab.home")
        case .settings:
            L10n.string("tab.settings")
        case .account:
            L10n.string("tab.account")
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "tray.full"
        case .settings:
            "gearshape"
        case .account:
            "person.crop.circle"
        }
    }
}

struct AutonomoAppShellView: View {
    @Environment(AutonomoAccessController.self) private var accessController
    @State private var selectedTab: AutonomoRootTab = .home
    @State private var isShowingProPaywall = false

    var body: some View {
        TabView(selection: $selectedTab) {
            IntakeShellView(
                proAccessIsUnlocked: accessController.hasProAccess,
                showProPaywall: showProPaywall
            )
            .tabItem {
                Label(AutonomoRootTab.home.title, systemImage: AutonomoRootTab.home.systemImage)
            }
            .tag(AutonomoRootTab.home)

            SettingsScreen()
                .tabItem {
                    Label(AutonomoRootTab.settings.title, systemImage: AutonomoRootTab.settings.systemImage)
                }
                .tag(AutonomoRootTab.settings)

            AccountScreen(showProPaywall: showProPaywall)
                .tabItem {
                    Label(AutonomoRootTab.account.title, systemImage: AutonomoRootTab.account.systemImage)
                }
                .tag(AutonomoRootTab.account)
        }
        .tint(AutonomoTheme.ink)
        .sheet(isPresented: $isShowingProPaywall) {
            AutonomoProPaywallView(startSignInFlow: {})
        }
    }

    private func showProPaywall() {
        isShowingProPaywall = true
    }
}

struct SettingsScreen: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.string("settings.intake.title"))
                                .font(.headline)
                            Text(L10n.string("settings.intake.detail"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .foregroundStyle(AutonomoTheme.accentDeep)
                    }
                }

                Section(L10n.string("settings.links")) {
                    LinkRow(title: L10n.string("settings.support"), systemImage: "lifepreserver", url: AppConfig.supportURL)
                    LinkRow(title: L10n.string("settings.privacy"), systemImage: "hand.raised", url: AppConfig.privacyURL)
                    LinkRow(title: L10n.string("settings.terms"), systemImage: "doc.text", url: AppConfig.termsURL)
                }
            }
            .navigationTitle(L10n.string("tab.settings"))
            .scrollContentBackground(.hidden)
            .background(AutonomoTheme.background.ignoresSafeArea())
        }
    }
}
