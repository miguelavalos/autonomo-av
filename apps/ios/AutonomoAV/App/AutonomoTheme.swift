import AVSettingsFoundation
import SwiftUI

enum AutonomoTheme {
    static let ink = Color(red: 0.082, green: 0.098, blue: 0.290)
    static let graphite = Color(red: 0.290, green: 0.290, blue: 0.322)
    static let accent = Color(red: 0.427, green: 0.745, blue: 0.271)
    static let accentDeep = Color(red: 0.190, green: 0.435, blue: 0.133)
    static let background = Color(red: 0.984, green: 0.969, blue: 0.922)
    static let surface = Color(red: 1.000, green: 0.992, blue: 0.953)
    static let surfaceMuted = Color(red: 0.957, green: 0.929, blue: 0.835)
    static let border = ink.opacity(0.12)
    static let shadow = ink.opacity(0.08)
}

struct AutonomoLaunchStateView: View {
    var body: some View {
        AVConfiguredSplashScreen()
    }
}

struct AutonomoAviBriefCard: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("AviAutonomoAssistant")
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 66)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AutonomoTheme.ink)
                Text(detail)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AutonomoTheme.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AutonomoTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AutonomoTheme.border, lineWidth: 1)
        }
    }
}
