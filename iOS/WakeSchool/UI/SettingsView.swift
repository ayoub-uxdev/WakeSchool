import SwiftUI
import UIKit

/// Écran « Réglages » de WakeSchool.
///
/// Regroupe : le compte scolaire (connexion PRONOTE), le réveil et les
/// autorisations, l'apparence, les données & le diagnostic, et les informations
/// « À propos ». Toutes les valeurs affichées proviennent de `SchoolDataStore`
/// (elle-même alimentée par Sync / Storage) — aucune donnée n'est inventée.
///
/// L'écran utilise des composants SwiftUI natifs (`Form`) afin de respecter
/// automatiquement le thème clair / sombre demandé dans « Apparence ».
struct SettingsView: View {
    @EnvironmentObject private var store: SchoolDataStore
    @Environment(\.openURL) private var openURL

    @StateObject private var alarmController = SmartAlarmController.live()
    @State private var alarmStatus: WakeAlarmAuthorizationStatus = .notDetermined
    @State private var showingLogin = false

    private var summary: SchoolDataStore.PronoteConnectionSummary { store.connectionSummary }
    private var isPronote: Bool { store.dataSource == .pronote }

    var body: some View {
        // Poussé depuis MoreView : le NavigationStack est fourni par le parent.
        Form {
            accountSection
            if let error = store.errorMessage {
                errorSection(error)
            }
            alarmSection
            appearanceSection
            dataSection
            aboutSection
        }
        .navigationTitle("Réglages")
        .tint(WakeTheme.accent)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            alarmStatus = AlarmManager.shared.authorizationStatus()
            alarmController.refresh()
        }
        .onChange(of: store.dataSource) { _, _ in
            alarmController.refresh()
        }
        .sheet(isPresented: $showingLogin) {
            PronoteLoginView()
                .environmentObject(store)
        }
    }

    private var appearance: AppearancePreference { store.appearance }

    // MARK: - Compte scolaire

    private var accountSection: some View {
        Section {
            connectionStatusRow

            if isPronote && summary.isConfigured {
                if let accountKind = summary.accountKind {
                    SettingsRow(symbol: "person.crop.circle",
                                title: "Type de compte",
                                value: accountKind.displayName,
                                tint: .blue)
                }
                if let serverHost = summary.serverHost {
                    SettingsRow(symbol: "server.rack",
                                title: "Serveur",
                                value: serverHost,
                                tint: .blue)
                }
                if let method = summary.method {
                    SettingsRow(symbol: "key.horizontal",
                                title: "Méthode",
                                value: method,
                                tint: .blue)
                }
            }

            lastSyncRow

            Button {
                Task { await store.refresh() }
            } label: {
                HStack {
                    Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if store.isSyncing {
                        ProgressView()
                    }
                }
            }
            .disabled(store.isSyncing)

            Button {
                showingLogin = true
            } label: {
                Label(isPronote ? "Reconnecter PRONOTE" : "Se connecter à PRONOTE",
                      systemImage: "qrcode.viewfinder")
            }
        } header: {
            Label("Compte scolaire", systemImage: "graduationcap.fill")
        } footer: {
            Text("WakeSchool se connecte directement à PRONOTE. Tes identifiants restent dans le trousseau de l'iPhone et ne sont jamais envoyés ailleurs.")
        }
    }

    private var connectionStatusRow: some View {
        HStack(spacing: 14) {
            Image(systemName: isPronote ? "checkmark.seal.fill" : "wand.and.stars")
                .font(.body.weight(.semibold))
                .foregroundStyle(isPronote ? Color.green : Color.gray)
                .frame(width: 30, height: 30)
                .background(Circle().fill((isPronote ? Color.green : Color.gray).opacity(0.18)))
            VStack(alignment: .leading, spacing: 2) {
                Text(isPronote ? "Connecté à PRONOTE" : "Mode démonstration")
                    .font(.body.weight(.semibold))
                Text(isPronote && summary.isConfigured
                     ? "Données de ton établissement"
                     : "Données d'exemple — aucune donnée réelle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var lastSyncRow: some View {
        SettingsRow(symbol: "clock.arrow.circlepath",
                    title: "Dernière synchronisation",
                    value: store.lastSync.map { Self.dateTime($0) } ?? "Jamais",
                    tint: .green)
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dernière synchronisation en échec")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Réveil et notifications

    private var alarmSection: some View {
        Section {
            SettingsRow(symbol: alarmStatus.systemImage,
                        title: "Autorisation des alarmes",
                        value: alarmStatus.label,
                        tint: alarmStatus.tint)

            if let alarm = alarmController.scheduledAlarm {
                SettingsRow(symbol: "alarm.fill",
                            title: "Réveil programmé",
                            value: "\(DateLabels.time(alarm.fireDate)) · \(DateLabels.dayTitle(alarm.fireDate))",
                            tint: .orange)
            } else {
                SettingsRow(symbol: "alarm",
                            title: "Réveil programmé",
                            value: "Aucun",
                            tint: .gray)
            }

            SettingsRow(symbol: "car.fill",
                        title: "Temps de trajet",
                        value: "\(store.wakeSettings.travelMinutes) min",
                        tint: .purple)
            SettingsRow(symbol: "figure.walk",
                        title: "Temps de préparation",
                        value: "\(store.wakeSettings.preparationMinutes) min",
                        tint: .purple)
            SettingsRow(symbol: "shield.lefthalf.filled",
                        title: "Marge de sécurité",
                        value: "\(store.wakeSettings.safetyMarginMinutes) min",
                        tint: .purple)

            Button {
                openAppSettings()
            } label: {
                Label("Ouvrir les Réglages système", systemImage: "gearshape")
            }
        } header: {
            Label("Réveil et notifications", systemImage: "alarm.fill")
        } footer: {
            Text("Le trajet, la préparation et la marge se règlent dans l'onglet Réveil.")
        }
    }

    // MARK: - Apparence

    private var appearanceSection: some View {
        Section {
            Picker(selection: Binding(
                get: { store.appearance },
                set: { store.setAppearance($0) }
            )) {
                ForEach(AppearancePreference.allCases) { preference in
                    Label(preference.displayName, systemImage: preference.systemImage)
                        .tag(preference)
                }
            } label: {
                Label("Apparence", systemImage: "circle.lefthalf.filled")
            }
        } header: {
            Label("Apparence", systemImage: "paintbrush.fill")
        } footer: {
            Text("Le mode clair s'applique à cet écran et aux éléments système de WakeSchool.")
        }
    }

    // MARK: - Données et diagnostic

    private var dataSection: some View {
        Section {
            SettingsRow(symbol: "internaldrive",
                        title: "Source des données",
                        value: isPronote ? "PRONOTE" : "Démonstration",
                        tint: isPronote ? .green : .gray)

            SettingsRow(symbol: "tray.full",
                        title: "Données en cache",
                        value: "\(store.snapshot.timetable.count) cours · \(store.snapshot.homework.count) devoirs · \(store.snapshot.grades.count) notes",
                        tint: .blue)

            if isPronote, let diagnostics = store.syncDiagnostics {
                NavigationLink {
                    PronoteDiagnosticsView(diagnostics: diagnostics)
                } label: {
                    Label("Diagnostic PRONOTE", systemImage: "stethoscope")
                }
            }
        } header: {
            Label("Données et diagnostic", systemImage: "internaldrive.fill")
        }
    }

    // MARK: - À propos

    private var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "graduationcap.fill")
                    .font(.title2)
                    .foregroundStyle(WakeTheme.accent)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(WakeTheme.accent.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(WakeAppInfo.displayName)
                        .font(.headline)
                    Text("Assistant scolaire intelligent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SettingsRow(symbol: "tag", title: "Version", value: WakeAppInfo.version, tint: .gray)
            SettingsRow(symbol: "hammer", title: "Build", value: WakeAppInfo.build, tint: .gray)
        } header: {
            Label("À propos", systemImage: "info.circle.fill")
        }
    }

    // MARK: - Utilitaires

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private static func dateTime(_ date: Date) -> String {
        "\(DateLabels.dayTitle(date)) · \(DateLabels.time(date))"
    }
}


// MARK: - Préférence d'apparence -> ColorScheme

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Informations de version de l'application

enum WakeAppInfo {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "WakeSchool"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

// MARK: - Ligne de réglage standard

private struct SettingsRow: View {
    let symbol: String
    let title: String
    var value: String? = nil
    var tint: Color = WakeTheme.accent

    var body: some View {
        Label {
            HStack(spacing: 12) {
                Text(title)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }
}


// MARK: - Diagnostic PRONOTE détaillé

/// Écran détaillant le diagnostic de la dernière synchronisation PRONOTE.
/// Lecture seule : n'effectue aucun appel réseau et n'affiche aucun secret.
struct PronoteDiagnosticsView: View {
    let diagnostics: PronoteSyncDiagnostics

    var body: some View {
        Form {
            Section("Connexion") {
                diagRow("Authentification réussie", diagnostics.authenticationSucceeded ? "oui" : "non")
                diagRow("Paramètres utilisateur récupérés", diagnostics.userParametersRetrieved ? "oui" : "non")
                diagRow("Ressource élève identifiée", diagnostics.studentResourceIdentified ? "oui" : "non")
                diagRow("Période scolaire identifiée", diagnostics.schoolPeriodIdentified ? "oui" : "non")
            }

            datasetSection("Cours", diagnostics.timetable)
            datasetSection("Devoirs", diagnostics.homework)
            datasetSection("Notes", diagnostics.grades)

            if let stage = diagnostics.errorStage, let code = diagnostics.errorCode {
                Section("Erreur") {
                    diagRow("Étape", stage)
                    diagRow("Code", code)
                }
            }
        }
        .navigationTitle("Diagnostic PRONOTE")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func datasetSection(_ title: String, _ data: PronoteDatasetDiagnostics) -> some View {
        Section(title) {
            diagRow("Appel", data.callStatus.rawValue)
            diagRow("Bruts / convertis", "\(data.rawCount) / \(data.convertedCount)")
            diagRow("Enregistrés / affichés", "\(data.savedCount) / \(data.displayedCount)")
            if !data.rejectedCounts.isEmpty {
                let categories = data.rejectedCounts
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: " · ")
                diagRow("Ignorés par catégorie", categories)
            }
            if let stage = data.errorStage, let code = data.errorCode {
                diagRow("Erreur", "\(stage) · \(code)")
            }
        }
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    // La vue est poussée depuis MoreView : le preview simule ce contexte.
    NavigationStack {
        SettingsView()
    }
    .environmentObject(
        SchoolDataStore(
            environment: AppEnvironment.inMemory()
            )
        )
}

