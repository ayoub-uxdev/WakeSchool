import SwiftUI

struct PronoteLoginView: View {
    @EnvironmentObject private var dataStore: SchoolDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showingScanner = false
    @State private var scannedQRCode: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    qrSection
                    pinSection

                    if let errorMessage {
                        errorView(message: errorMessage)
                    }

                    connectButton

                    Text("Le QR code et le jeton PRONOTE sont utilisés uniquement pour connecter cet iPhone. Les données sensibles restent dans le Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("PRONOTE")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingScanner) {
                PronoteQRScannerView { value in
                    showingScanner = false
                    scannedQRCode = value
                    errorMessage = nil
                }
            }
        }
        .interactiveDismissDisabled(isConnecting)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 54))
                .symbolRenderingMode(.hierarchical)

            Text("Connexion à PRONOTE")
                .font(.title.bold())

            Text("Scanne le QR code généré dans PRONOTE, puis saisis le code à 4 chiffres choisi lors de sa création.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var qrSection: some View {
        VStack(spacing: 12) {
            Button {
                errorMessage = nil
                showingScanner = true
            } label: {
                Label(
                    scannedQRCode == nil ? "Scanner le QR code" : "Scanner un nouveau QR code",
                    systemImage: "qrcode.viewfinder"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting)

            HStack(spacing: 8) {
                Image(systemName: scannedQRCode == nil ? "qrcode" : "checkmark.circle.fill")
                Text(scannedQRCode == nil ? "Aucun QR code scanné" : "QR code scanné")
            }
            .font(.subheadline)
            .foregroundStyle(scannedQRCode == nil ? .secondary : .green)
        }
    }

    private var pinSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code de vérification")
                .font(.headline)

            TextField("1234", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.title2.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .onChange(of: pin) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    pin = String(digits.prefix(4))
                }

            Text("Ce code est celui demandé par PRONOTE au moment où tu génères le QR code.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.subheadline)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectButton: some View {
        Button {
            Task { await connect() }
        } label: {
            Group {
                if isConnecting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Connexion...")
                            .fontWeight(.semibold)
                    }
                } else {
                    Text("Se connecter à PRONOTE")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isConnecting || !canConnect)
    }

    private var canConnect: Bool {
        scannedQRCode != nil && pin.count == 4
    }

    private func connect() async {
        guard let scannedQRCode, canConnect else { return }

        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let result = try await LivePronoteClient.loginWithQRCode(
                qrText: scannedQRCode,
                pin: pin
            )

            try CredentialsStore(store: dataStore.environmentSecrets).save(result.credentials)
            dataStore.setDataSource(.pronote)
            dataStore.reloadProvider()
            await dataStore.refresh()

            if let error = dataStore.errorMessage {
                throw PronoteLoginViewError.connectionFailed(error)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum PronoteLoginViewError: Error, LocalizedError {
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return message
        }
    }
}

#Preview {
    PronoteLoginView()
        .environmentObject(
            SchoolDataStore(
                environment: AppEnvironment.inMemory()
            )
        )
}
