import SwiftUI

struct PronoteLoginView: View {
    @EnvironmentObject private var dataStore: SchoolDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""

    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    credentialsForm

                    if let errorMessage {
                        errorView(message: errorMessage)
                    }

                    connectButton

                    Text("Tes identifiants sont stockés uniquement dans le Keychain de l’iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("PRONOTE")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(isConnecting)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 54))
                .symbolRenderingMode(.hierarchical)

            Text("Connexion à PRONOTE")
                .font(.title.bold())

            Text("Connecte ton compte PRONOTE pour importer ton emploi du temps, tes devoirs et tes notes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Formulaire

    private var credentialsForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Adresse PRONOTE")
                    .font(.headline)

                TextField(
                    "https://.../pronote",
                    text: $serverURL
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Identifiant")
                    .font(.headline)

                TextField(
                    "Identifiant PRONOTE",
                    text: $username
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Mot de passe")
                    .font(.headline)

                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField(
                                "Mot de passe",
                                text: $password
                            )
                        } else {
                            SecureField(
                                "Mot de passe",
                                text: $password
                            )
                        }
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(
                            systemName: showPassword
                                ? "eye.slash"
                                : "eye"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.35))
                )
            }
        }
    }

    // MARK: - Erreur

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

    // MARK: - Bouton

    private var connectButton: some View {
        Button {
            Task {
                await connect()
            }
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
                    Text("Se connecter")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isConnecting || !canConnect)
    }

    // MARK: - Validation

    private var canConnect: Bool {
        !serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty &&
        !username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty &&
        !password.isEmpty
    }

    // MARK: - Connexion

    private func connect() async {
        guard canConnect else {
            return
        }

        isConnecting = true
        errorMessage = nil

        let credentials = PronoteCredentials(
            serverURL: serverURL
                .trimmingCharacters(in: .whitespacesAndNewlines),
            username: username
                .trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )

        do {
            // 1. On teste réellement les identifiants.
            let client = LivePronoteClient(
                credentials: credentials
            )

            _ = try await client.profile()

            // 2. Seulement si l'authentification réussit,
            //    on sauvegarde les identifiants.
            try CredentialsStore(
                store: dataStore.environmentSecrets
            ).save(credentials)

            // 3. On bascule WakeSchool sur PRONOTE.
            dataStore.setDataSource(.pronote)

            // 4. On recharge les données avec le nouveau provider.
            await dataStore.refresh()

            // 5. Si la synchronisation échoue,
            //    on affiche l'erreur au lieu de fermer silencieusement.
            if let error = dataStore.errorMessage {
                throw PronoteLoginViewError.connectionFailed(error)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
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