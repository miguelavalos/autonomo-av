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

        let attachments = providers.compactMap(AutonomoAVShareAttachment.init(provider:))

        if attachments.isEmpty {
            detailLabel.text = "No se encontraron elementos compatibles para enviar."
            return
        }

        guard let pendingURL = try? AutonomoAVShareExtensionInboxWriter.preparePendingURL() else {
            detailLabel.text = "No se pudo abrir la bandeja compartida. Abre Autonomo AV para revisar la configuracion de la app."
            return
        }

        doneButton.isEnabled = false
        detailLabel.text = "Guardando \(attachments.count) elemento(s) en la bandeja de entrada..."
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
                detailLabel.text = "No se pudo guardar ningun elemento compatible."
            } else if failedCount == 0 {
                detailLabel.text = "\(savedCount) elemento(s) guardados. Abre Autonomo AV para subirlos con tu sesion."
            } else {
                detailLabel.text = "\(savedCount) elemento(s) guardados y \(failedCount) fallidos. Abre Autonomo AV para subir los elementos guardados."
            }
            return
        }

        let attachment = attachments[index]
        if attachment.isFileURL {
            attachment.provider.loadItem(forTypeIdentifier: attachment.typeIdentifier, options: nil) { [weak self] item, _ in
                guard let self else { return }
                let fileURL = AutonomoAVShareAttachment.fileURL(from: item)
                let didSave: Bool
                if let fileURL {
                    didSave = (try? AutonomoAVShareExtensionInboxWriter.copyFileURL(
                        from: fileURL,
                        suggestedName: attachment.suggestedName,
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
            return
        }

        attachment.provider.loadFileRepresentation(forTypeIdentifier: attachment.typeIdentifier) { [weak self] temporaryURL, _ in
            guard let self else { return }

            if let temporaryURL {
                let didSave = (try? AutonomoAVShareExtensionInboxWriter.copyTemporaryFile(
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
                    didSave = (try? AutonomoAVShareExtensionInboxWriter.writeData(
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
