import AVFoundation
import SwiftUI
import VisionKit

struct PronoteQRScannerView: View {
    @Environment(\.dismiss) private var dismiss

    let onCodeScanned: (String) -> Void

    @State private var isCheckingCameraPermission = true
    @State private var cameraPermissionGranted = false
    @State private var scannerUnavailable = false
    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isCheckingCameraPermission {
                    ProgressView("Préparation de la caméra...")
                } else if cameraPermissionGranted &&
                    DataScannerViewController.isSupported &&
                    DataScannerViewController.isAvailable {
                    DataScannerRepresentable(
                        onCodeScanned: onCodeScanned,
                        onError: { message in
                            scannerError = message
                            scannerUnavailable = true
                        }
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
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Scanner indisponible",
                isPresented: $scannerUnavailable
            ) {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(
                    scannerError
                        ?? "Autorise l’accès à la caméra dans Réglages, puis réessaie."
                )
            }
        }
        .task {
            await prepareScanner()
        }
    }

    @MainActor
    private func prepareScanner() async {
        let authorizationStatus =
            AVCaptureDevice.authorizationStatus(for: .video)

        switch authorizationStatus {
        case .authorized:
            cameraPermissionGranted = true
        case .notDetermined:
            cameraPermissionGranted =
                await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            cameraPermissionGranted = false
        @unknown default:
            cameraPermissionGranted = false
        }

        isCheckingCameraPermission = false

        if !cameraPermissionGranted {
            scannerUnavailable = true
        } else if !DataScannerViewController.isSupported ||
            !DataScannerViewController.isAvailable {
            scannerUnavailable = true
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label(
                "Scanner indisponible",
                systemImage: "camera.fill"
            )
        } description: {
            Text(
                "Autorise l’accès à la caméra dans Réglages si nécessaire, puis réessaie."
            )
        }
    }
}

private struct DataScannerRepresentable:
    UIViewControllerRepresentable {

    let onCodeScanned: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCodeScanned: onCodeScanned,
            onError: onError
        )
    }

    func makeUIViewController(
        context: Context
    ) -> DataScannerViewController {
        let controller =
            LifecycleDataScannerViewController(
                recognizedDataTypes: [
                    .barcode(symbologies: [.qr])
                ],
                qualityLevel: .balanced,
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: true,
                isPinchToZoomEnabled: true,
                isGuidanceEnabled: true,
                isHighlightingEnabled: true
            )

        controller.delegate = context.coordinator
        controller.onDidAppear = { [weak coordinator = context.coordinator] scanner in
            coordinator?.startScanning(scanner)
        }

        return controller
    }

    func updateUIViewController(
        _ uiViewController: DataScannerViewController,
        context: Context
    ) {}

    static func dismantleUIViewController(
        _ uiViewController: DataScannerViewController,
        coordinator: Coordinator
    ) {
        if uiViewController.isScanning {
            uiViewController.stopScanning()
        }
    }

    private final class LifecycleDataScannerViewController:
        DataScannerViewController {

        var onDidAppear: ((DataScannerViewController) -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onDidAppear?(self)
        }
    }

    final class Coordinator:
        NSObject,
        DataScannerViewControllerDelegate {

        let onCodeScanned: (String) -> Void
        let onError: (String) -> Void

        private var hasDeliveredCode = false
        private var isStartingOrScanning = false

        init(
            onCodeScanned: @escaping (String) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onCodeScanned = onCodeScanned
            self.onError = onError
        }

        func startScanning(_ scanner: DataScannerViewController) {
            guard !isStartingOrScanning, !hasDeliveredCode else {
                return
            }

            guard DataScannerViewController.isSupported,
                DataScannerViewController.isAvailable
            else {
                onError(
                    "La caméra de cet iPhone ne peut pas être utilisée pour scanner le QR code."
                )
                return
            }

            isStartingOrScanning = true

            do {
                try scanner.startScanning()
            } catch {
                isStartingOrScanning = false
                onError(error.localizedDescription)
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasDeliveredCode else {
                return
            }

            for item in addedItems {
                guard case .barcode(let barcode) = item,
                    let payload = barcode.payloadStringValue,
                    !payload.isEmpty
                else {
                    continue
                }

                hasDeliveredCode = true

                if dataScanner.isScanning {
                    dataScanner.stopScanning()
                }

                onCodeScanned(payload)
                return
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error:
                DataScannerViewController.ScanningUnavailable
        ) {
            onError(error.localizedDescription)
        }
    }
}
