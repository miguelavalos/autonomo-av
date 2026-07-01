import MobileCoreServices
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private var discoveredItemCount = 0

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

        discoveredItemCount = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) ||
                provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ||
                provider.hasItemConformingToTypeIdentifier(kUTTypeItem as String)
        }.count

        if discoveredItemCount == 0 {
            detailLabel.text = "No se encontraron elementos compatibles para enviar."
        } else {
            detailLabel.text = "\(discoveredItemCount) elemento(s) listos para la bandeja de entrada. La subida directa desde la extension se conectara cuando el puente seguro de cuenta este disponible."
        }
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
