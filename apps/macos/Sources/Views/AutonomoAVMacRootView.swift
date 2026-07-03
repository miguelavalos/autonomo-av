import SwiftUI

struct AutonomoAVMacRootView: View {
    let model: AutonomoAVMacModel
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            AutonomoAVMacSidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } detail: {
            VStack(spacing: 0) {
                AutonomoAVMacHeaderView(model: model)

                Divider()

                if model.hasProAccess {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            AutonomoAVMacDropZone(
                                isTargeted: isDropTargeted,
                                importAction: {
                                    Task { await model.pickAndImportFiles(source: .macosFiles) }
                                }
                            )
                            .dropDestination(for: URL.self) { urls, _ in
                                Task {
                                    await model.importFiles(urls, source: .macosDragDrop)
                                }
                                return true
                            } isTargeted: { targeted in
                                isDropTargeted = targeted
                            }

                            AutonomoAVMacLocalQueueView(model: model)

                            if !model.remoteDocuments.isEmpty {
                                AutonomoAVMacRemoteInboxView(documents: model.remoteDocuments)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    AutonomoAVMacAccessGateView(model: model)
                }
            }
            .background(.background)
        }
    }
}

private struct AutonomoAVMacHeaderView: View {
    let model: AutonomoAVMacModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Autonomo AV")
                    .font(.title2.weight(.semibold))
                Text(model.hasProAccess ? "\(model.pendingCount) pending · \(model.failedCount) failed" : model.accessStatusText)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await model.refreshRemoteDocuments() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(!model.hasProAccess || model.isRefreshingRemoteDocuments)

            Button {
                Task { await model.uploadPending() }
            } label: {
                Label("Upload Pending", systemImage: "arrow.up.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasUploadableItems || !model.hasProAccess || model.isUploading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

private struct AutonomoAVMacAccessGateView: View {
    let model: AutonomoAVMacModel

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(detail)
            } actions: {
                HStack(spacing: 10) {
                    if model.accountIsSignedIn {
                        if let url = AppConfig.accountManagementURL {
                            Link(destination: url) {
                                Label("Manage Pro", systemImage: "creditcard")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button {
                            Task { await model.refreshAccess() }
                        } label: {
                            Label("Refresh Access", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isRefreshingAccess)
                    } else {
                        Button {
                            Task { await model.signInWithApple() }
                        } label: {
                            Label("Sign in with Apple", systemImage: "apple.logo")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.accountController.isAuthenticating)

                        Button {
                            Task { await model.signInWithGoogle() }
                        } label: {
                            Label("Sign in with Google", systemImage: "person.badge.key")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.accountController.isAuthenticating)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var title: String {
        model.accountIsSignedIn ? "Autonomo AV Pro required" : "Sign in to Autonomo AV"
    }

    private var detail: String {
        model.accountIsSignedIn
            ? "Activate Pro before sending documents to the intake queue."
            : "Sign in first, then activate Pro to send documents."
    }

    private var systemImage: String {
        model.accountIsSignedIn ? "lock.fill" : "person.crop.circle.badge.plus"
    }
}

private struct AutonomoAVMacDropZone: View {
    let isTargeted: Bool
    let importAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            VStack(spacing: 4) {
                Text("Documents")
                    .font(.headline)
                Text("PDF, JPEG, PNG, WebP, HEIC, HEIF")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: importAction) {
                Label("Choose Files", systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
        }
    }
}

private struct AutonomoAVMacLocalQueueView: View {
    let model: AutonomoAVMacModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Local Queue")
                    .font(.headline)
                Spacer()
                Text("\(model.localItems.count) item(s)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if model.localItems.isEmpty {
                ContentUnavailableView("No documents", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.localItems) { item in
                        AutonomoAVMacQueueRow(item: item) {
                            Task { await model.retry(item) }
                        }
                        if item.id != model.localItems.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.16))
                }
            }
        }
    }
}

private struct AutonomoAVMacQueueRow: View {
    let item: LocalIntakeItem
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.status.macSystemImage)
                .font(.title3)
                .foregroundStyle(item.status == .failed ? Color.red : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(item.source.macDisplayText) · \(item.mimeType) · \(item.byteSize.macByteCountText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let errorMessage = item.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.status.macDisplayText)
                    .font(.caption.weight(.semibold))
                Text(item.updatedAt.macShortDateTimeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 116, alignment: .trailing)

            if item.status == .failed {
                Button(action: retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Retry upload")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct AutonomoAVMacRemoteInboxView: View {
    let documents: [AutonomoDocumentSummary]
    private var visibleDocuments: [AutonomoDocumentSummary] {
        Array(documents.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Documents")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(visibleDocuments, id: \.id) { document in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(document.fileName ?? document.title ?? document.id)
                                .lineLimit(1)
                            Text("\(document.source?.macDisplayText ?? "Unknown") · \(document.mimeType ?? "Unknown")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(document.status.displayText)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if document.id != visibleDocuments.last?.id {
                        Divider()
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.16))
            }
        }
    }
}
