import SwiftUI
import VisionKit

struct PronoteQRScannerView: View {
    @Environment(\.dismiss) private var dismiss

    let onCodeScanned: (String) -> Void

    @State private var scannerUnavailable = false
    @State private var scannerError: String?
    @State private var didScan = false

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable(
                        didScan: $didScan,
                        onCodeScanned: onCodeScanned,
                        onError: { scannerError = $0 }
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    unavailableView
                }
            }
            .navigationTitle("Scanner le QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
            .alert("Scanner indisponible", isPresented: $scannerUnavailable) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text(scannerError ?? "La caméra de cet iPhone ne peut pas être utilisée pour scanner le QR code.")
            }
        }
        .onAppear {
            if !DataScannerViewController.isSupported || !DataScannerViewController.isAvailable {
                scannerUnavailable = true
            }
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Scanner indisponible", systemImage: "camera.fill")
        } description: {
            Text("Autorise l’accès à la caméra dans Réglages si nécessaire, puis réessaie.")
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var didScan: Bool
    let onCodeScanned: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onError: onError)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !didScan, !uiViewController.isScanning else { return }

        do {
            try uiViewController.startScanning()
        } catch {
            onError(error.localizedDescription)
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCodeScanned: (String) -> Void
        let onError: (String) -> Void
        private var hasDeliveredCode = false

        init(onCodeScanned: @escaping (String) -> Void,
             onError: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
            self.onError = onError
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !hasDeliveredCode else { return }

            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadString,
                      !payload.isEmpty else {
                    continue
                }

                hasDeliveredCode = true
                dataScanner.stopScanning()
                onCodeScanned(payload)
                return
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onError(error.localizedDescription)
        }
    }
}
