import Foundation
import SwiftUI

/// État partagé par les écrans.
/// Charge le cache local, déclenche la synchronisation et relaie les actions utilisateur
/// vers les couches Sync / Storage.
@MainActor
final class SchoolDataStore: ObservableObject {
    @Published private(set) var snapshot: SchoolSnapshot = .empty
    @Published private(set) var isSyncing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSync: Date?

    private let environment: AppEnvironment
    private var hasStarted = false

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - Exposition contrôlée de l'environnement

    /// Permet aux écrans de connexion d'enregistrer les identifiants
    /// sans exposer directement l'environnement complet.
    var environmentSecrets: SecretStore {
        environment.secrets
    }

    var wakeSettings: WakeSettings {
        environment.preferences.wakeSettings
    }

    var dataSource: DataSourceKind {
        environment.preferences.dataSource
    }

    // MARK: - Démarrage

    /// Affiche immédiatement le cache local puis synchronise.
    /// Ne s'exécute qu'une seule fois.
    func start() async {
        guard !hasStarted else { return }

        hasStarted = true

        do {
            snapshot = try environment.sync.loadCached()
        } catch {
            errorMessage = error.localizedDescription
        }

        lastSync = environment.preferences.lastSyncDate

        await refresh()
    }

    // MARK: - Synchronisation

    /// Synchronise avec le provider actuel.
    ///
    /// Si la synchronisation échoue, les données locales restent affichées.
    func refresh() async {
        guard !isSyncing else { return }

        isSyncing = true
        defer {
            isSyncing = false
        }

        do {
            snapshot = try await environment.sync.sync()
            lastSync = environment.preferences.lastSyncDate
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Source de données

    /// Change la source de données puis reconstruit le provider.
    ///
    /// Exemple :
    /// Demo → PRONOTE
    func setDataSource(_ source: DataSourceKind) {
        environment.preferences.dataSource = source
        environment.reloadProvider()

        errorMessage = nil
    }

    /// Reconnecte le provider actuel.
    ///
    /// Utile après l'enregistrement de nouvelles identifiants PRONOTE.
    func reloadProvider() {
        environment.reloadProvider()
        errorMessage = nil
    }

    // MARK: - Devoirs

    /// Marque un devoir comme terminé / non terminé.
    /// L'état est persisté localement.
    func setHomework(_ id: UUID, done: Bool) {
        do {
            try environment.repository.setHomework(id, done: done)
            snapshot = try environment.sync.loadCached()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}