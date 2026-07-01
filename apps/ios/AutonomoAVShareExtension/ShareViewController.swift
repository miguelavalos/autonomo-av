import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        inspectSharedItems()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        titleLabel.text = "Enviar a Autonomo AV Inbox"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        detailLabel.text = "Preparando elementos compartidos..."
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = .secondaryLabel
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0

        doneButton.setTitle("Cerrar", for: .normal)
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, doneButton])
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func inspectSharedItems() {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        let attachments = providers.compactMap(ShareAttachment.init(provider:))

        if attachments.isEmpty {
            detailLabel.text = "No se encontraron elementos compatibles para enviar."
            return
        }

        guard let pendingURL = try? ShareExtensionInbox.preparePendingURL() else {
            detailLabel.text = "No se pudo abrir la bandeja compartida. Abre Autonomo AV para revisar la configuracion de la app."
            return
        }

        doneButton.isEnabled = false
        detailLabel.text = "Guardando \(attachments.count) elemento(s) en la bandeja de entrada..."
        save(attachments, to: pendingURL)
    }

    private func save(
        _ attachments: [ShareAttachment],
        to pendingURL: URL,
        index: Int = 0,
        savedCount: Int = 0,
        failedCount: Int = 0
    ) {
        guard index < attachments.count else {
            doneButton.isEnabled = true
            if savedCount == 0 {
                detailLabel.text = "No se pudo guardar ningun elemento compatible."
            } else if failedCount == 0 {
                detailLabel.text = "\(savedCount) elemento(s) guardados. Abre Autonomo AV para subirlos con tu sesion."
            } else {
                detailLabel.text = "\(savedCount) elemento(s) guardados y \(failedCount) fallidos. Abre Autonomo AV para subir los elementos guardados."
            }
            return
        }

        let attachment = attachments[index]
        attachment.provider.loadFileRepresentation(forTypeIdentifier: attachment.typeIdentifier) { [weak self] temporaryURL, _ in
            guard let self else { return }

            if let temporaryURL {
                let didSave = (try? ShareExtensionInbox.copyTemporaryFile(
                    from: temporaryURL,
                    suggestedName: attachment.suggestedName,
                    typeIdentifier: attachment.typeIdentifier,
                    to: pendingURL
                )) != nil
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
                    didSave = (try? ShareExtensionInbox.writeData(
                        data,
                        suggestedName: attachment.suggestedName,
                        typeIdentifier: attachment.typeIdentifier,
                        to: pendingURL
                    )) != nil
                } else {
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

private struct ShareAttachment: @unchecked Sendable {
    let provider: NSItemProvider
    let typeIdentifier: String
    let suggestedName: String?

    init?(provider: NSItemProvider) {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            typeIdentifier = UTType.pdf.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            typeIdentifier = UTType.image.identifier
        } else {
            return nil
        }

        self.provider = provider
        self.suggestedName = provider.suggestedName
    }
}

private enum ShareExtensionInbox {
    enum InboxError: Error {
        case missingAppGroup
    }

    static func preparePendingURL(fileManager: FileManager = .default) throws -> URL {
        guard let rootURL = appGroupRootURL(fileManager: fileManager) else {
            throw InboxError.missingAppGroup
        }

        let pendingURL = rootURL.appending(path: "ShareInbox/Pending", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        return pendingURL
    }

    static func copyTemporaryFile(
        from temporaryURL: URL,
        suggestedName: String?,
        typeIdentifier: String,
        to pendingURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let destination = uniqueDestinationURL(
            suggestedName: suggestedName ?? temporaryURL.lastPathComponent,
            typeIdentifier: typeIdentifier,
            pendingURL: pendingURL,
            fileManager: fileManager
        )
        try fileManager.copyItem(at: temporaryURL, to: destination)
    }

    static func writeData(
        _ data: Data,
        suggestedName: String?,
        typeIdentifier: String,
        to pendingURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let destination = uniqueDestinationURL(
            suggestedName: suggestedName,
            typeIdentifier: typeIdentifier,
            pendingURL: pendingURL,
            fileManager: fileManager
        )
        try data.write(to: destination, options: [.atomic])
    }

    private static func appGroupRootURL(fileManager: FileManager) -> URL? {
        guard let identifier = appGroupIdentifier() else {
            return nil
        }
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    private static func appGroupIdentifier(bundle: Bundle = .main) -> String? {
        if let configured = bundle.object(forInfoDictionaryKey: "AUTONOMOAV_APP_GROUP_IDENTIFIER") as? String {
            let identifier = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if !identifier.isEmpty, identifier != "$(AUTONOMOAV_APP_GROUP_IDENTIFIER)" {
                return identifier
            }
        }

        guard let bundleIdentifier = bundle.bundleIdentifier else {
            return nil
        }

        let containingBundleIdentifier: String
        if bundleIdentifier.hasSuffix(".share") {
            containingBundleIdentifier = String(bundleIdentifier.dropLast(".share".count))
        } else {
            containingBundleIdentifier = bundleIdentifier
        }
        return "group.\(containingBundleIdentifier)"
    }

    private static func uniqueDestinationURL(
        suggestedName: String?,
        typeIdentifier: String,
        pendingURL: URL,
        fileManager: FileManager
    ) -> URL {
        let fileName = sanitizedFileName(suggestedName, typeIdentifier: typeIdentifier)
        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension

        var candidate = pendingURL.appending(path: fileName)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let suffixedName: String
            if pathExtension.isEmpty {
                suffixedName = "\(baseName)-\(suffix)"
            } else {
                suffixedName = "\(baseName)-\(suffix).\(pathExtension)"
            }
            candidate = pendingURL.appending(path: suffixedName)
            suffix += 1
        }
        return candidate
    }

    private static func sanitizedFileName(_ suggestedName: String?, typeIdentifier: String) -> String {
        let fallbackExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "dat"
        let fallbackName = "shared-\(UUID().uuidString).\(fallbackExtension)"
        let rawName = suggestedName?.isEmpty == false ? suggestedName ?? fallbackName : fallbackName
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        let sanitized = rawName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            return fallbackName
        }
        if (sanitized as NSString).pathExtension.isEmpty {
            return "\(sanitized).\(fallbackExtension)"
        }
        return sanitized
    }
}
