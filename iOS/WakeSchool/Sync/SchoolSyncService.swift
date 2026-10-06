import Foundation

/// Orchestre provider -> repository. Si le provider échoue (hors ligne, erreur Pronote...),
/// le cache local reste intact et l'erreur est propagée.
@MainActor
final class SchoolSyncService {
    private let provider: SchoolDataProvider
    private let repository: SchoolRepository
    private let preferences: PreferencesStore
    private let now: () -> Date

    init(provider: SchoolDataProvider,
         repository: SchoolRepository,
         preferences: PreferencesStore,
         now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.repository = repository
        self.preferences = preferences
        self.now = now
    }

    /// Données déjà présentes sur l'appareil (fonctionne hors ligne).
    func loadCached() throws -> SchoolSnapshot {
        try repository.loadSnapshot()
    }

    /// Récupère les données, les persiste, puis renvoie l'état local à jour.
    @discardableResult
    func sync() async throws -> SchoolSnapshot {
        let fresh = try await provider.snapshot()
        try repository.save(fresh)
        preferences.lastSyncDate = now()
        return try repository.loadSnapshot()
    }
}
