import Foundation
import SwiftData

/// Point de câblage des couches. Choisit le provider selon les préférences ;
/// les Views ne changent pas quand on passe de la démo à Pronote.
/// Pas encore branché sur l'UI (prévu dans le lot suivant).
@MainActor
final class AppEnvironment {
    let preferences: PreferencesStore
    let secrets: SecretStore
    let repository: SchoolRepository
    let sync: SchoolSyncService

    init(preferences: PreferencesStore,
         secrets: SecretStore,
         repository: SchoolRepository,
         provider: SchoolDataProvider) {
        self.preferences = preferences
        self.secrets = secrets
        self.repository = repository
        self.sync = SchoolSyncService(provider: provider, repository: repository, preferences: preferences)
    }

    static func live() throws -> AppEnvironment {
        let preferences = PreferencesStore()
        let container = try SwiftDataSchoolRepository.makeContainer()
        return AppEnvironment(preferences: preferences,
                              secrets: KeychainSecretStore(),
                              repository: SwiftDataSchoolRepository(container: container),
                              provider: makeProvider(for: preferences.dataSource))
    }

    static func makeProvider(for source: DataSourceKind) -> SchoolDataProvider {
        switch source {
        case .demo:
            return DemoSchoolDataProvider()
        case .pronote:
            // Remplacer UnavailablePronoteClient par le vrai client quand il existera.
            return PronoteSchoolDataProvider(client: UnavailablePronoteClient())
        }
    }
}
