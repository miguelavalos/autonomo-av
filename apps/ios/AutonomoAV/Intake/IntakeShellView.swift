import SwiftUI
import UniformTypeIdentifiers

struct IntakeShellView: View {
    @Environment(IntakeStore.self) private var intakeStore
    let proAccessIsUnlocked: Bool
    let showProPaywall: () -> Void

    @State private var isFileImporterPresented = false
    @State private var isScannerPresented = false
    @State private var scannerAlertIsPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    IntakeSummaryHeader(
                        needsReviewCount: intakeStore.needsReviewCount,
                        pendingCount: intakeStore.pendingOrFailedItems.count,
                        isUploading: intakeStore.isUploading
                    )

                    if proAccessIsUnlocked {
                        HStack(spacing: 12) {
                            IntakeActionButton(
                                title: L10n.string("intake.primary.scan"),
                                systemImage: "doc.viewfinder"
                            ) {
                                if DocumentScannerView.isSupported {
                                    isScannerPresented = true
                                } else {
                                    scannerAlertIsPresented = true
                                }
                            }

                            IntakeActionButton(
                                title: L10n.string("intake.primary.files"),
                                systemImage: "folder"
                            ) {
                                isFileImporterPresented = true
                            }
                        }

                        AutonomoAviBriefCard(
                            title: L10n.string("intake.avi.title"),
                            detail: L10n.string("intake.avi.detail")
                        )

                        if !intakeStore.pendingOrFailedItems.isEmpty {
                            IntakeSectionHeader(title: L10n.string("intake.pending"))
                            VStack(spacing: 10) {
                                ForEach(intakeStore.pendingOrFailedItems) { item in
                                    LocalIntakeRow(item: item) {
                                        Task { await intakeStore.retry(item) }
                                    }
                                }
                            }
                        }

                        IntakeSectionHeader(title: L10n.string("intake.recent"))
                        VStack(spacing: 10) {
                            if intakeStore.remoteDocuments.isEmpty {
                                EmptyIntakeView()
                            } else {
                                ForEach(intakeStore.remoteDocuments) { document in
                                    RemoteDocumentRow(document: document)
                                }
                            }
                        }
                    } else {
                        LockedIntakeView(showProPaywall: showProPaywall)
                        AutonomoAviBriefCard(
                            title: L10n.string("intake.locked.avi.title"),
                            detail: L10n.string("intake.locked.avi.detail")
                        )
                    }
                }
                .padding(18)
                .safeAreaPadding(.bottom, 88)
            }
            .background(AutonomoTheme.background.ignoresSafeArea())
            .navigationTitle(L10n.string("shell.title"))
            .toolbar {
                if proAccessIsUnlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await intakeStore.refreshRemoteDocuments()
                                await intakeStore.uploadPending()
                            }
                        } label: {
                            Label(L10n.string("shell.refresh"), systemImage: "arrow.clockwise")
                        }
                        .disabled(intakeStore.isRefreshingRemoteDocuments || intakeStore.isUploading)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await intakeStore.importFiles(from: urls) }
            case .failure(let error):
                intakeStore.lastErrorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $isScannerPresented) {
            DocumentScannerView { pages in
                Task { await intakeStore.importScannedPages(pages) }
            }
        }
        .alert(L10n.string("intake.scan.unavailable.title"), isPresented: $scannerAlertIsPresented) {
            Button(L10n.string("auth.close"), role: .cancel) {}
        } message: {
            Text(L10n.string("intake.scan.unavailable.message"))
        }
        .alert(L10n.string("intake.import.failed.title"), isPresented: storeErrorIsPresented) {
            Button(L10n.string("auth.close"), role: .cancel) {
                intakeStore.lastErrorMessage = nil
            }
        } message: {
            Text(intakeStore.lastErrorMessage ?? L10n.string("intake.import.failed.message"))
        }
    }

    private var storeErrorIsPresented: Binding<Bool> {
        Binding(
            get: { intakeStore.lastErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    intakeStore.lastErrorMessage = nil
                }
            }
        )
    }
}

struct LockedIntakeView: View {
    let showProPaywall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image("AviAutonomoAssistant")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("intake.locked.title"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AutonomoTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.string("intake.locked.detail"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AutonomoTheme.graphite)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                LockedBenefitRow(systemImage: "tray.and.arrow.down.fill", text: L10n.string("intake.locked.benefit.inbox"))
                LockedBenefitRow(systemImage: "sparkles", text: L10n.string("intake.locked.benefit.ai"))
                LockedBenefitRow(systemImage: "flag.checkered", text: L10n.string("intake.locked.benefit.priority"))
            }

            Button(action: showProPaywall) {
                Label(L10n.string("intake.locked.cta"), systemImage: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(AutonomoTheme.ink)
        }
        .padding(16)
        .background(AutonomoTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AutonomoTheme.accent.opacity(0.4), lineWidth: 1.5)
        }
    }
}

private struct LockedBenefitRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AutonomoTheme.accentDeep)
                .frame(width: 24, height: 24)

            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AutonomoTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct IntakeSummaryHeader: View {
    let needsReviewCount: Int
    let pendingCount: Int
    let isUploading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Image("AutonomoHeaderWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 230, maxHeight: 48, alignment: .leading)
                        .accessibilityLabel(L10n.string("app.name"))
                    Text(L10n.string("shell.title"))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AutonomoTheme.ink)
                }
                Spacer()
                if isUploading {
                    ProgressView()
                        .tint(AutonomoTheme.accent)
                }
            }

            HStack(spacing: 10) {
                MetricChip(value: "\(pendingCount)", label: L10n.string("intake.pending"), systemImage: "arrow.up.doc")
                MetricChip(value: "\(needsReviewCount)", label: L10n.string("intake.needsReview"), systemImage: "exclamationmark.magnifyingglass")
            }
        }
        .padding(16)
        .background(AutonomoTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AutonomoTheme.border, lineWidth: 1)
        }
    }
}

struct IntakeActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(AutonomoTheme.ink)
    }
}

struct IntakeSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AutonomoTheme.graphite)
            .textCase(.uppercase)
            .tracking(0)
    }
}

struct LocalIntakeRow: View {
    let item: LocalIntakeItem
    let retry: () -> Void

    var body: some View {
        IntakeRowShell(
            title: item.fileName,
            subtitle: item.errorMessage ?? item.mimeType,
            statusText: item.status.displayText,
            statusSystemImage: statusSystemImage,
            statusTint: statusTint
        ) {
            if item.status == .failed {
                Button(action: retry) {
                    Label(L10n.string("intake.retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var statusSystemImage: String {
        switch item.status {
        case .pending:
            return "clock"
        case .uploading:
            return "arrow.up.circle"
        case .uploaded:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var statusTint: Color {
        switch item.status {
        case .pending:
            return .secondary
        case .uploading:
            return .blue
        case .uploaded:
            return .green
        case .failed:
            return .red
        }
    }
}

struct RemoteDocumentRow: View {
    let document: AutonomoDocumentSummary

    var body: some View {
        IntakeRowShell(
            title: document.title ?? document.fileName ?? document.id,
            subtitle: subtitle,
            statusText: document.status.displayText,
            statusSystemImage: statusSystemImage,
            statusTint: statusTint
        )
    }

    private var subtitle: String {
        [document.source?.rawValue, document.mimeType]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var statusSystemImage: String {
        switch document.status {
        case .uploaded, .queued:
            return "tray.full"
        case .processing:
            return "gearshape.2"
        case .drafted:
            return "doc.badge.gearshape"
        case .needsReview:
            return "exclamationmark.magnifyingglass"
        case .reviewed:
            return "checkmark.seal"
        case .duplicate:
            return "doc.on.doc"
        case .ignored:
            return "archivebox"
        case .failed, .quarantined:
            return "exclamationmark.triangle"
        }
    }

    private var statusTint: Color {
        switch document.status {
        case .uploaded, .queued:
            return .blue
        case .processing, .drafted:
            return .purple
        case .needsReview:
            return .orange
        case .reviewed:
            return .green
        case .duplicate, .ignored:
            return .secondary
        case .failed, .quarantined:
            return .red
        }
    }
}

struct IntakeRowShell<Trailing: View>: View {
    let title: String
    let subtitle: String
    let statusText: String
    let statusSystemImage: String
    let statusTint: Color
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String,
        statusText: String,
        statusSystemImage: String,
        statusTint: Color,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusText = statusText
        self.statusSystemImage = statusSystemImage
        self.statusTint = statusTint
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusSystemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(statusTint)
                .frame(width: 36, height: 36)
                .background(statusTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle.isEmpty ? statusText : subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
            }

            Spacer(minLength: 8)
            trailing()
        }
        .padding(12)
        .background(AutonomoTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AutonomoTheme.border, lineWidth: 1)
        }
    }
}

struct MetricChip: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(AutonomoTheme.accentDeep)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AutonomoTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct EmptyIntakeView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("AutonomoBrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 74, height: 74)
                .accessibilityHidden(true)
            Text(L10n.string("intake.empty.title"))
                .font(.headline)
                .foregroundStyle(AutonomoTheme.ink)
            Text(L10n.string("intake.empty.detail"))
                .font(.subheadline)
                .foregroundStyle(AutonomoTheme.graphite)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(AutonomoTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AutonomoTheme.border, lineWidth: 1)
        }
    }
}

#Preview {
    IntakeShellView(proAccessIsUnlocked: false, showProPaywall: {})
        .environment(IntakeStore(
            client: AutonomoAPIClient(baseURLProvider: { nil }, tokenProvider: { nil })
        ))
}
