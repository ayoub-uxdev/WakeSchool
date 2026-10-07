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
        let secrets = KeychainSecretStore()
        return AppEnvironment(preferences: preferences,
                              secrets: secrets,
                              repository: SwiftDataSchoolRepository(container: container),
                              provider: makeProvider(for: preferences.dataSource, secrets: secrets))
    }

    static func makeProvider(for source: DataSourceKind, secrets: SecretStore? = nil) -> SchoolDataProvider {
        switch source {
        case .demo:
            return DemoSchoolDataProvider()
        case .pronote:
            guard let secrets,
                  let credentials = try? CredentialsStore(store: secrets).load() else {
                return PronoteSchoolDataProvider(client: UnavailablePronoteClient())
            }
            return PronoteSchoolDataProvider(client: LivePronoteClient(credentials: credentials))
        }
    }
}
