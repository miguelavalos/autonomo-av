import AppKit
import OSLog

private let shareExtensionLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.avalsys.autonomoav.mac.share",
    category: "ShareExtension"
)

final class ShareViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "Autonomo AV Inbox")
    private let detailLabel = NSTextField(labelWithString: "Preparing shared items...")
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        inspectSharedItems()
    }

    private func configureView() {
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0

        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 0

        doneButton.target = self
        doneButton.action = #selector(finish)

        let stack = NSStackView(views: [titleLabel, detailLabel, doneButton])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
        ])
    }

    private func inspectSharedItems() {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        let attachments = providers.compactMap(AutonomoAVShareAttachment.init(provider:))
        shareExtensionLogger.info(
            "Share extension inspected providers=\(providers.count, privacy: .public) compatible=\(attachments.count, privacy: .public)"
        )

        if attachments.isEmpty {
            shareExtensionLogger.info("Share extension found no compatible attachments")
            detailLabel.stringValue = "No compatible items were found."
            return
        }

        guard AutonomoAVAccessSnapshotStore.loadFreshProSnapshot() != nil else {
            shareExtensionLogger.info("Share extension blocked because no fresh Pro access snapshot was available")
            detailLabel.stringValue = "Open Autonomo AV, sign in, and activate Pro before sending documents."
            return
        }

        let pendingURL: URL
        do {
            pendingURL = try AutonomoAVShareExtensionInboxWriter.preparePendingURL()
        } catch {
            shareExtensionLogger.error("Share extension could not open pending inbox")
            detailLabel.stringValue = "The shared inbox could not be opened."
            return
        }

        doneButton.isEnabled = false
        detailLabel.stringValue = "Saving \(attachments.count) item(s)..."
        shareExtensionLogger.info("Share extension save started count=\(attachments.count, privacy: .public)")
        save(attachments, to: pendingURL)
    }

    private func save(
        _ attachments: [AutonomoAVShareAttachment],
        to pendingURL: URL,
        index: Int = 0,
        savedCount: Int = 0,
        failedCount: Int = 0
    ) {
        guard index < attachments.count else {
            doneButton.isEnabled = true
            if savedCount == 0 {
                detailLabel.stringValue = "No compatible items could be saved."
            } else if failedCount == 0 {
                detailLabel.stringValue = "\(savedCount) item(s) saved."
            } else {
                detailLabel.stringValue = "\(savedCount) item(s) saved and \(failedCount) failed."
            }
            shareExtensionLogger.info(
                "Share extension save completed saved=\(savedCount, privacy: .public) failed=\(failedCount, privacy: .public)"
            )
            return
        }

        let attachment = attachments[index]
        if attachment.isFileURL {
            attachment.provider.loadItem(forTypeIdentifier: attachment.typeIdentifier, options: nil) { [weak self] item, _ in
                guard let self else { return }
                let fileURL = AutonomoAVShareAttachment.fileURL(from: item)
                let didSave: Bool
                if let fileURL {
                    do {
                        try AutonomoAVShareExtensionInboxWriter.copyFileURL(
                            from: fileURL,
                            suggestedName: attachment.suggestedName,
                            to: pendingURL
                        )
                        didSave = true
                    } catch {
                        shareExtensionLogger.error("Share extension file URL attachment copy failed")
                        didSave = false
                    }
                } else {
                    shareExtensionLogger.error("Share extension file URL attachment did not resolve to a file URL")
                    didSave = false
                }

                DispatchQueue.main.async {
                    self.save(
                        attachments,
                        to: pendingURL,
                        index: index + 1,
                        savedCount: savedCount + (didSave ? 1 : 0),
                        failedCount: failedCount + (didSave ? 0 : 1)
                    )
                }
            }
            return
        }

        attachment.provider.loadFileRepresentation(forTypeIdentifier: attachment.typeIdentifier) { [weak self] temporaryURL, _ in
            guard let self else { return }

            if let temporaryURL {
                let didSave: Bool
                do {
                    try AutonomoAVShareExtensionInboxWriter.copyTemporaryFile(
                        from: temporaryURL,
                        suggestedName: attachment.suggestedName,
                        typeIdentifier: attachment.typeIdentifier,
                        to: pendingURL
                    )
                    didSave = true
                } catch {
                    shareExtensionLogger.error(
                        "Share extension temporary file copy failed type=\(attachment.typeIdentifier, privacy: .public)"
                    )
                    didSave = false
                }
                DispatchQueue.main.async {
                    self.save(
                        attachments,
                        to: pendingURL,
                        index: index + 1,
                        savedCount: savedCount + (didSave ? 1 : 0),
                        failedCount: failedCount + (didSave ? 0 : 1)
                    )
                }
                return
            }

            attachment.provider.loadDataRepresentation(forTypeIdentifier: attachment.typeIdentifier) { [weak self] data, _ in
                guard let self else { return }
                let didSave: Bool
                if let data {
                    do {
                        try AutonomoAVShareExtensionInboxWriter.writeData(
                            data,
                            suggestedName: attachment.suggestedName,
                            typeIdentifier: attachment.typeIdentifier,
                            to: pendingURL
                        )
                        didSave = true
                    } catch {
                        shareExtensionLogger.error(
                            "Share extension data write failed type=\(attachment.typeIdentifier, privacy: .public)"
                        )
                        didSave = false
                    }
                } else {
                    shareExtensionLogger.error(
                        "Share extension data representation missing type=\(attachment.typeIdentifier, privacy: .public)"
                    )
                    didSave = false
                }

                DispatchQueue.main.async {
                    self.save(
                        attachments,
                        to: pendingURL,
                        index: index + 1,
                        savedCount: savedCount + (didSave ? 1 : 0),
                        failedCount: failedCount + (didSave ? 0 : 1)
                    )
                }
            }
        }
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
