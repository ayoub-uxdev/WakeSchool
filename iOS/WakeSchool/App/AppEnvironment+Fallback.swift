import Foundation

extension AppEnvironment {
    /// Environnement réel (SwiftData sur disque). Si le stockage ne peut pas s'ouvrir,
    /// l'application reste utilisable avec un stockage en mémoire plutôt que de planter.
    static func liveOrFallback() -> AppEnvironment {
        if let environment = try? live() { return environment }
        return inMemory()
    }

    /// Environnement sans persistance disque (secours, tests, previews).
    static func inMemory(provider: SchoolDataProvider = DemoSchoolDataProvider(),
                         preferences: PreferencesStore = PreferencesStore()) -> AppEnvironment {
        guard let container = try? SwiftDataSchoolRepository.makeContainer(inMemory: true) else {
            preconditionFailure("Impossible de créer le stockage SwiftData en mémoire.")
        }
        return AppEnvironment(preferences: preferences,
                              secrets: InMemorySecretStore(),
                              repository: SwiftDataSchoolRepository(container: container),
                              provider: provider)
    }
}
