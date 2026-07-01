import SwiftUI
import UIKit
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    let onComplete: ([ScannedDocumentPage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, dismiss: dismiss)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let onComplete: ([ScannedDocumentPage]) -> Void
        let dismiss: DismissAction

        init(onComplete: @escaping ([ScannedDocumentPage]) -> Void, dismiss: DismissAction) {
            self.onComplete = onComplete
            self.dismiss = dismiss
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [ScannedDocumentPage] = []
            for index in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: index)
                guard let data = image.jpegData(compressionQuality: 0.88) else { continue }
                pages.append(ScannedDocumentPage(
                    fileName: "scan-\(Int(Date().timeIntervalSince1970))-\(index + 1).jpg",
                    data: data
                ))
            }
            onComplete(pages)
            dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            dismiss()
        }
    }
}
