import AVPaywallFoundation
import SwiftUI

struct AutonomoProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AccountController.self) private var accountController
    @Environment(AutonomoAccessController.self) private var accessController

    let startSignInFlow: () -> Void

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
            } restoreButton: {
                if accountController.currentUser != nil {
                    AVPaywallRestoreButton(
                        title: restoreTitle,
                        isDisabled: accessController.isSubscriptionOperationInProgress
                    ) {
                        Task { await accessController.restorePurchases(for: accountController.currentUser) }
                    }
                } else {
                    EmptyView()
                }
            }

            subscriptionTermsRow
            subscriptionStatusRow
            AVPaywallBenefitList(items: benefitItems)
            AVPaywallLegalLinks(links: legalLinkItems)
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
            AVPaywallStatusRow(systemImage: "arrow.triangle.2.circlepath", message: L10n.string("paywall.status.refreshingAccess"))
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
        accessController.isSubscriptionOperationInProgress
            ? L10n.string("paywall.restore.loading")
            : L10n.string("paywall.restore")
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
}
