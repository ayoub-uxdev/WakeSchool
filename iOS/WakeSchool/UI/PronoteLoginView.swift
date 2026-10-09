import SwiftUI

struct PronoteLoginView: View {
    @EnvironmentObject private var dataStore: SchoolDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var accountKind: PronoteAccountKind = .student
    @State private var loginMethod: LoginMethod = .qrCode
    @State private var credentialsMethod: CredentialsMethod = .entHDF
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showingScanner = false
    @State private var scannedQRCode: String?
    @State private var showingENTBrowser = false
    @State private var entLoginURL: URL?
    @State private var entMobileURL: URL?
    @State private var entMobileUUID: String?
    @State private var entCurrentHost = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    loginMethodPicker

                    if loginMethod == .qrCode {
                        qrSection
                        pinSection
                    } else if credentialsMethod == .entHDF {
                        entSection
                    } else {
                        credentialsSection
                    }

                    if let errorMessage {
                        errorView(message: errorMessage)
                    }

                    connectButton

                    Text(credentialStorageNote)
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
        .sheet(isPresented: $showingENTBrowser) {
            if let entLoginURL, let entMobileURL, let entMobileUUID {
                NavigationStack {
                    PronoteENTLoginWebView(
                        url: entLoginURL,
                        mobileURL: entMobileURL,
                        mobileUUID: entMobileUUID,
                        onLogin: { username, mobileToken in
                            showingENTBrowser = false
                            Task {
                                await finishENTLogin(
                                    username: username,
                                    mobileToken: mobileToken
                                )
                            }
                        },
                        onHostChange: { host in
                            entCurrentHost = host
                        },
                        onError: { message in
                            showingENTBrowser = false
                            errorMessage = message
                        }
                    )
                    .navigationTitle("Connexion ENT HDF")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Annuler") {
                                showingENTBrowser = false
                            }
                        }
                    }
                    .safeAreaInset(edge: .top) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                            Text(entCurrentHost.isEmpty ? entLoginURL.host ?? "" : entCurrentHost)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.bar)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isConnecting)
    }

    private var loginMethodPicker: some View {
        Picker("Méthode de connexion", selection: $loginMethod) {
            Text("QR code").tag(LoginMethod.qrCode)
            Text("Identifiants").tag(LoginMethod.credentials)
        }
        .pickerStyle(.segmented)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 54))
                .symbolRenderingMode(.hierarchical)

            Text("Connexion à PRONOTE")
                .font(.title.bold())

            Text(headerDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var headerDescription: String {
        if loginMethod == .qrCode {
            return "Scanne le QR code généré dans PRONOTE, puis saisis le code à 4 chiffres choisi lors de sa création."
        }
        if credentialsMethod == .entHDF {
            return "Connecte-toi sur la page officielle de ton établissement. WakeSchool ne lit pas et ne conserve pas ton mot de passe ENT."
        }
        return "Saisis l’adresse du serveur et les identifiants directs de ton compte PRONOTE."
    }

    private var credentialStorageNote: String {
        if loginMethod == .credentials && credentialsMethod == .entHDF {
            return "Le mot de passe ENT n’est pas enregistré. Seul le jeton de connexion PRONOTE est conservé dans le Keychain."
        }
        return "Les données sensibles sont conservées uniquement dans le Keychain de cet iPhone. La connexion ENT par QR code reste également disponible."
    }

    private var credentialsMethodPicker: some View {
        Picker("Type de connexion", selection: $credentialsMethod) {
            Text("ENT HDF").tag(CredentialsMethod.entHDF)
            Text("PRONOTE direct").tag(CredentialsMethod.directPronote)
        }
        .pickerStyle(.segmented)
    }

    private var entSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connexion sécurisée par l’ENT")
                .font(.headline)

            credentialsMethodPicker

            TextField("Lien PRONOTE de l’établissement", text: $serverURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Picker("Type de compte", selection: $accountKind) {
                ForEach(PronoteAccountKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.menu)

            Text("La page officielle s’ouvrira ici. Saisis tes identifiants ENT uniquement sur cette page ; WakeSchool ne les enregistre pas.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connexion directe PRONOTE")
                .font(.headline)

            credentialsMethodPicker

            TextField("Adresse du serveur PRONOTE", text: $serverURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Picker("Type de compte", selection: $accountKind) {
                ForEach(PronoteAccountKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.menu)

            TextField("Identifiant PRONOTE", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            SecureField("Mot de passe PRONOTE", text: $password)
                .textFieldStyle(.roundedBorder)

            Text("Ce mode utilise les identifiants directs du compte PRONOTE. Les identifiants sont conservés dans le Keychain de cet iPhone.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .foregroundStyle(scannedQRCode == nil ? Color.secondary : Color.green)
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
                    Text(
                        loginMethod == .credentials && credentialsMethod == .entHDF
                            ? "Continuer avec l’ENT HDF"
                            : "Se connecter à PRONOTE"
                    )
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
        switch loginMethod {
        case .qrCode:
            return scannedQRCode != nil && pin.count == 4
        case .credentials:
            if credentialsMethod == .entHDF {
                return !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.isEmpty
        }
    }

    private func connect() async {
        guard canConnect else { return }

        if loginMethod == .credentials && credentialsMethod == .entHDF {
            do {
                let loginURLs = try PronoteENTLoginWebView.loginURLs(
                    from: serverURL,
                    accountKind: accountKind
                )
                entLoginURL = loginURLs.bootstrapURL
                entMobileURL = loginURLs.mobileURL
                entCurrentHost = loginURLs.bootstrapURL.host ?? ""
                serverURL = PronoteHTTPTransport.rootURL(from: loginURLs.mobileURL).absoluteString
                entMobileUUID = try PronoteMobileIdentity.sharedUUID()
                errorMessage = nil
                showingENTBrowser = true
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let result: PronoteQRLoginResult
            switch loginMethod {
            case .qrCode:
                guard let scannedQRCode else { return }
                result = try await LivePronoteClient.loginWithQRCode(
                    qrText: scannedQRCode,
                    pin: pin
                )
            case .credentials:
                result = try await LivePronoteClient.loginWithCredentials(
                    serverURL: serverURL,
                    username: username,
                    password: password,
                    accountKind: accountKind
                )
            }

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

    private func finishENTLogin(username: String, mobileToken: String) async {
        guard let entMobileUUID else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let result = try await LivePronoteClient.loginWithENTMobileToken(
                serverURL: serverURL,
                username: username,
                mobileToken: mobileToken,
                accountKind: accountKind,
                mobileUUID: entMobileUUID
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

private enum LoginMethod: Hashable {
    case qrCode
    case credentials
}

private enum CredentialsMethod: Hashable {
    case entHDF
    case directPronote
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
