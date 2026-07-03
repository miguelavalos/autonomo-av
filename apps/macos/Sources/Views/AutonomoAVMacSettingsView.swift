import SwiftUI

struct AutonomoAVMacSettingsView: View {
    var body: some View {
        TabView {
            Form {
                SettingsValueRow(title: "Environment", value: AppConfig.environmentName)
                SettingsValueRow(title: "Queue", value: AppConfig.localIntakeRootURL.lastPathComponent)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                SettingsLinkRow(title: "Support", url: AppConfig.supportURL)
                SettingsLinkRow(title: "Privacy", url: AppConfig.privacyURL)
                SettingsLinkRow(title: "Terms", url: AppConfig.termsURL)
                SettingsLinkRow(title: "Account", url: AppConfig.accountManagementURL)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Links", systemImage: "link")
            }
        }
        .frame(width: 460, height: 260)
        .scenePadding()
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let url: URL?

    var body: some View {
        if let url {
            Link(title, destination: url)
        } else {
            HStack {
                Text(title)
                Spacer()
                Text("Not configured")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
