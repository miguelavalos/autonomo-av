import AVPaywallFoundation
import SwiftUI

struct AutonomoProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AccountController.self) private var accountController
    @Environment(AutonomoAccessController.self) private var accessController

    let startSignInFlow: () -> Void

    @State private var redeemCode = ""
    @State private var redeemStatusMessage: String?
    @State private var isRedeemingCode = false
    @State private var isShowingRedeemCodeSheet = false
    @State private var isRestoringPurchases = false

    var body: some View {
        AVPaywallSheetScaffold(
            navigationTitle: L10n.string("paywall.navigationTitle"),
            closeTitle: L10n.string("paywall.close"),
            backgroundStyle: AnyShapeStyle(AutonomoTheme.background),
            onClose: { dismiss() }
        ) {
            AVPaywallHeader(
                eyebrow: L10n.string("paywall.eyebrow"),
                title: L10n.string("paywall.title"),
                subtitle: L10n.string("paywall.subtitle")
            )

            AVPaywallOfferCard(
                title: L10n.string("paywall.scene.title"),
                detail: L10n.string("paywall.scene.detail"),
                primaryButtonTitle: primaryButtonTitle,
                primaryButtonIsDisabled: primaryButtonIsDisabled,
                primaryAccessibilityIdentifier: "paywall.purchase",
                primaryAction: primaryAction
            ) {
                Image("AviAutonomoAssistant")
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .background(AutonomoTheme.surfaceMuted, in: Circle())
            }

            subscriptionTermsRow
            subscriptionStatusRow
            AVPaywallBenefitList(items: benefitItems)
            footerLinks
        }
        .task(id: accountController.currentUser?.id) {
            await accessController.refreshAccess(for: accountController.currentUser)
            await accessController.loadMonthlySubscriptionOffer(for: accountController.currentUser)
        }
        .onChange(of: accessController.accessMode) { _, mode in
            if mode == .signedInPro {
                dismiss()
            }
        }
        .sheet(isPresented: $isShowingRedeemCodeSheet) {
            redeemCodeSheet
        }
    }

    @ViewBuilder
    private var subscriptionTermsRow: some View {
        if accountController.currentUser != nil, let offer = accessController.subscriptionOffer {
            AVPaywallStatusRow(
                systemImage: "calendar.badge.clock",
                message: L10n.string("paywall.subscriptionTerms", offer.localizedPrice)
            )
            .accessibilityIdentifier("paywall.subscriptionTerms")
        }
    }

    @ViewBuilder
    private var subscriptionStatusRow: some View {
        if accessController.isWaitingForSubscriptionReconciliation {
            AVPaywallStatusRow(systemImage: "arrow.triangle.2.circlepath", message: reconciliationStatusMessage)
        } else if accessController.isRefreshingAccess {
            AVPaywallStatusRow(systemImage: "arrow.triangle.2.circlepath", message: L10n.string("paywall.status.refreshingAccess"))
        } else if let error = accessController.subscriptionError?.errorDescription {
            AVPaywallStatusRow(systemImage: "exclamationmark.triangle", message: error)
        }
    }

    private func primaryAction() {
        guard accountController.currentUser != nil else {
            dismiss()
            startSignInFlow()
            return
        }

        Task { await accessController.purchaseMonthlyPro(for: accountController.currentUser) }
    }

    private var primaryButtonTitle: String {
        guard accountController.currentUser != nil else {
            return L10n.string("paywall.signIn")
        }
        if accessController.isSubscriptionOperationInProgress {
            return L10n.string("paywall.purchase.loading")
        }
        if accessController.isRefreshingAccess || accessController.isWaitingForSubscriptionReconciliation {
            return L10n.string("paywall.purchase.refreshingAccess")
        }
        guard let offer = accessController.subscriptionOffer else {
            return L10n.string("paywall.purchase.loadingOffer")
        }
        return L10n.string("paywall.purchase.price", offer.localizedPrice)
    }

    private var primaryButtonIsDisabled: Bool {
        if accountController.currentUser == nil {
            return !accountController.accountIsAvailable
        }
        return accessController.isRefreshingAccess ||
            accessController.isSubscriptionOperationInProgress ||
            accessController.subscriptionOffer == nil
    }

    private var restoreTitle: String {
        isRestoringPurchases
            ? L10n.string("paywall.restore.loading")
            : L10n.string("paywall.restore")
    }

    private var normalizedRedeemCode: String {
        redeemCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var redeemButtonIsDisabled: Bool {
        normalizedRedeemCode.isEmpty ||
            isRedeemingCode ||
            accessController.isSubscriptionOperationInProgress
    }

    private var reconciliationStatusMessage: String {
        switch accessController.subscriptionReconciliationSource {
        case .redeemCode:
            L10n.string("paywall.status.redeemingCode")
        case .purchase, .restore, .none:
            L10n.string("paywall.status.refreshingAccess")
        }
    }

    private var benefitItems: [AVPaywallBenefitItem] {
        [
            AVPaywallBenefitItem(
                id: "inbox",
                systemImage: "tray.and.arrow.down.fill",
                title: L10n.string("paywall.benefit.inbox.title"),
                detail: L10n.string("paywall.benefit.inbox.detail")
            ),
            AVPaywallBenefitItem(
                id: "classification",
                systemImage: "sparkles",
                title: L10n.string("paywall.benefit.ai.title"),
                detail: L10n.string("paywall.benefit.ai.detail")
            ),
            AVPaywallBenefitItem(
                id: "priority",
                systemImage: "flag.checkered",
                title: L10n.string("paywall.benefit.priority.title"),
                detail: L10n.string("paywall.benefit.priority.detail")
            )
        ]
    }

    private var legalLinkItems: [AVPaywallLegalLink] {
        var links: [AVPaywallLegalLink] = []
        if let termsURL = AppConfig.termsURL {
            links.append(AVPaywallLegalLink(title: L10n.string("paywall.terms"), accessibilityIdentifier: "paywall.terms") {
                openURL(termsURL)
            })
        }
        if let privacyURL = AppConfig.privacyURL {
            links.append(AVPaywallLegalLink(title: L10n.string("paywall.privacy"), accessibilityIdentifier: "paywall.privacy") {
                openURL(privacyURL)
            })
        }
        return links
    }

    private var footerLinks: some View {
        VStack(spacing: 8) {
            Text(L10n.string("paywall.legal.renewal"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AutonomoTheme.graphite)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    footerButton(
                        L10n.string("paywall.redeemCode"),
                        accessibilityIdentifier: "paywall.redeemCode",
                        action: showRedeemCodeSheet
                    )
                    footerSeparator

                    restoreFooterButton
                }
                .frame(maxWidth: .infinity, alignment: .center)

                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    ForEach(Array(legalLinkItems.enumerated()), id: \.element.id) { item in
                        if item.offset > 0 {
                            footerSeparator
                        }
                        footerButton(
                            item.element.title,
                            accessibilityIdentifier: item.element.accessibilityIdentifier,
                            action: item.element.action
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(AutonomoTheme.accentDeep)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func footerButton(_ title: String, accessibilityIdentifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var footerSeparator: some View {
        Text("·")
            .foregroundStyle(AutonomoTheme.graphite.opacity(0.72))
    }

    private var restoreFooterButton: some View {
        Button {
            restorePreviousPurchases()
        } label: {
            HStack(spacing: 4) {
                if isRestoringPurchases {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(AutonomoTheme.accentDeep)
                }

                Text(restoreTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .disabled(accountController.currentUser == nil || accessController.isSubscriptionOperationInProgress)
        .accessibilityIdentifier("paywall.restore")
    }

    private var redeemCodeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(title: L10n.string("paywall.redeem.title"), detail: L10n.string("paywall.redeem.detail"))

                    HStack(spacing: 10) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(AutonomoTheme.accentDeep)

                        TextField(L10n.string("paywall.redeem.placeholder"), text: $redeemCode)
                            .keyboardType(.asciiCapable)
                            .textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: redeemCode) { _, newValue in
                                let sanitized = sanitizedRedeemCodeInput(newValue)
                                if sanitized != newValue {
                                    redeemCode = sanitized
                                }
                            }
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AutonomoTheme.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .background(AutonomoTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AutonomoTheme.border, lineWidth: 1)
                            }
                            .accessibilityIdentifier("paywall.redeemCode.field")

                        Button(action: claimRedeemCode) {
                            ZStack {
                                if isRedeemingCode {
                                    ProgressView()
                                        .tint(AutonomoTheme.ink)
                                } else {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 17, weight: .black))
                                        .foregroundStyle(AutonomoTheme.ink)
                                }
                            }
                            .frame(width: 46, height: 46)
                            .background(
                                redeemButtonIsDisabled ? AutonomoTheme.border : AutonomoTheme.accent,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        }
                        .disabled(redeemButtonIsDisabled)
                        .accessibilityLabel(L10n.string("paywall.redeem.claim"))
                        .accessibilityIdentifier("paywall.redeemCode.claim")
                    }

                    Text(L10n.string("paywall.redeem.note"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AutonomoTheme.graphite)
                        .fixedSize(horizontal: false, vertical: true)

                    if let redeemStatusMessage {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AutonomoTheme.graphite)

                            Text(redeemStatusMessage)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AutonomoTheme.graphite)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                        .accessibilityIdentifier("paywall.redeemCode.status")
                    }
                }
                .padding(18)
                .background(AutonomoTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(20)
            }
            .background(AutonomoTheme.background.ignoresSafeArea())
            .navigationTitle(L10n.string("paywall.redeem.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("paywall.close")) {
                        isShowingRedeemCodeSheet = false
                    }
                    .accessibilityIdentifier("paywall.redeemCode.done")
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("paywall.redeemCode.sheet")
    }

    private func sectionHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(AutonomoTheme.ink)

            Text(detail)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AutonomoTheme.graphite)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func showRedeemCodeSheet() {
        guard !accessController.isSubscriptionOperationInProgress else { return }
        if accountController.currentUser != nil {
            redeemStatusMessage = nil
            isShowingRedeemCodeSheet = true
        } else {
            dismiss()
            startSignInFlow()
        }
    }

    private func claimRedeemCode() {
        guard !normalizedRedeemCode.isEmpty, !isRedeemingCode else { return }
        let code = normalizedRedeemCode
        isRedeemingCode = true
        redeemStatusMessage = nil

        Task {
            do {
                try await accessController.claimPromotionCode(code, for: accountController.currentUser)
                redeemStatusMessage = L10n.string("paywall.redeem.redeemed")
                redeemCode = ""
                isShowingRedeemCodeSheet = false
            } catch {
                redeemStatusMessage = error.localizedDescription
            }
            isRedeemingCode = false
        }
    }

    private func sanitizedRedeemCodeInput(_ code: String) -> String {
        var sanitized = ""
        for character in code {
            switch character {
            case " ", "\n", "\t":
                continue
            case "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}", "\u{2018}", "\u{2019}":
                sanitized.append("-")
            case _ where isASCIIAlphanumeric(character) || character == "-" || character == "_":
                sanitized.append(character)
            default:
                continue
            }
        }
        return sanitized.uppercased()
    }

    private func isASCIIAlphanumeric(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value else {
            return false
        }
        return (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
    }

    private func restorePreviousPurchases() {
        guard accountController.currentUser != nil else { return }
        guard !isRestoringPurchases, !accessController.isSubscriptionOperationInProgress else { return }

        isRestoringPurchases = true
        Task {
            await accessController.restorePurchases(for: accountController.currentUser)
            isRestoringPurchases = false
        }
    }
}
