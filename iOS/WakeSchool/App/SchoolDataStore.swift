import Foundation
import SwiftUI

/// État partagé par les écrans. Ne contient aucune logique métier :
/// il charge le cache, déclenche la synchronisation et relaie les actions de l'utilisateur
/// vers les couches Sync / Storage du LOT 1. Les calculs sont faits par les Services.
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

    var wakeSettings: WakeSettings { environment.preferences.wakeSettings }
    var dataSource: DataSourceKind { environment.preferences.dataSource }

    /// Affiche tout de suite le cache local, puis synchronise. Ne s'exécute qu'une fois.
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

    /// Synchronise avec le provider. En cas d'échec, les données locales restent affichées.
    func refresh() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            snapshot = try await environment.sync.sync()
            lastSync = environment.preferences.lastSyncDate
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Marque un devoir terminé / non terminé. L'état est persisté localement.
    func setHomework(_ id: UUID, done: Bool) {
        do {
            try environment.repository.setHomework(id, done: done)
            snapshot = try environment.sync.loadCached()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
