import SwiftUI
import UniformTypeIdentifiers

struct IntakeShellView: View {
    @Environment(AccountController.self) private var accountController
    @Environment(IntakeStore.self) private var intakeStore
    @State private var isFileImporterPresented = false
    @State private var isScannerPresented = false
    @State private var isAccountPresented = false
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
                }
                .padding(18)
            }
            .background(AutonomoTheme.background.ignoresSafeArea())
            .navigationTitle(L10n.string("shell.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isAccountPresented = true
                    } label: {
                        Label(L10n.string("shell.account"), systemImage: "person.crop.circle")
                    }
                }
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
        .sheet(isPresented: $isAccountPresented) {
            AccountSheet()
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

struct IntakeSummaryHeader: View {
    let needsReviewCount: Int
    let pendingCount: Int
    let isUploading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("app.name"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(L10n.string("shell.title"))
                        .font(.system(size: 34, weight: .bold))
                }
                Spacer()
                if isUploading {
                    ProgressView()
                }
            }

            HStack(spacing: 10) {
                MetricChip(value: "\(pendingCount)", label: L10n.string("intake.pending"), systemImage: "arrow.up.doc")
                MetricChip(value: "\(needsReviewCount)", label: L10n.string("intake.needsReview"), systemImage: "exclamationmark.magnifyingglass")
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .tint(AutonomoTheme.accent)
    }
}

struct IntakeSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
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
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .foregroundStyle(AutonomoTheme.accent)
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
        .background(AutonomoTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct EmptyIntakeView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(L10n.string("intake.empty.title"))
                .font(.headline)
            Text(L10n.string("intake.empty.detail"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AutonomoTheme.border, lineWidth: 1)
        }
    }
}

#Preview {
    IntakeShellView()
        .environment(AccountController(
            accountService: PreviewAccountService(),
            profileResolver: PreviewAccountResolver()
        ))
        .environment(IntakeStore(
            client: AutonomoAPIClient(baseURLProvider: { nil }, tokenProvider: { nil })
        ))
}
