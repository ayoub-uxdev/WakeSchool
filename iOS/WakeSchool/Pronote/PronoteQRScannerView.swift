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
    ) -> ScannerContainerViewController {
        let scanner = DataScannerViewController(
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

        scanner.delegate = context.coordinator

        return ScannerContainerViewController(scanner: scanner) {
            [weak coordinator = context.coordinator] scanner in
            coordinator?.startScanning(scanner)
        }
    }

    func updateUIViewController(
        _ uiViewController: ScannerContainerViewController,
        context: Context
    ) {}

    static func dismantleUIViewController(
        _ uiViewController: ScannerContainerViewController,
        coordinator: Coordinator
    ) {
        if uiViewController.scanner.isScanning {
            uiViewController.scanner.stopScanning()
        }
    }

    final class ScannerContainerViewController: UIViewController {
        let scanner: DataScannerViewController
        private let onDidAppear: (DataScannerViewController) -> Void

        init(
            scanner: DataScannerViewController,
            onDidAppear: @escaping (DataScannerViewController) -> Void
        ) {
            self.scanner = scanner
            self.onDidAppear = onDidAppear
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(scanner)
            view.addSubview(scanner.view)
            scanner.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scanner.view.leadingAnchor.constraint(
                    equalTo: view.leadingAnchor
                ),
                scanner.view.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor
                ),
                scanner.view.topAnchor.constraint(
                    equalTo: view.topAnchor
                ),
                scanner.view.bottomAnchor.constraint(
                    equalTo: view.bottomAnchor
                )
            ])
            scanner.didMove(toParent: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onDidAppear(scanner)
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
