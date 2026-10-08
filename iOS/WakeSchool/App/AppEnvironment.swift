import Foundation
import SwiftData

@MainActor
final class AppEnvironment {
    let preferences: PreferencesStore
    let secrets: SecretStore
    let repository: SchoolRepository
    private(set) var sync: SchoolSyncService

    init(
        preferences: PreferencesStore,
        secrets: SecretStore,
        repository: SchoolRepository,
        provider: SchoolDataProvider
    ) {
        self.preferences = preferences
        self.secrets = secrets
        self.repository = repository
        self.sync = SchoolSyncService(
            provider: provider,
            repository: repository,
            preferences: preferences
        )
    }

    static func live() throws -> AppEnvironment {
        let preferences = PreferencesStore()
        let container = try SwiftDataSchoolRepository.makeContainer()
        let secrets = KeychainSecretStore()

        return AppEnvironment(
            preferences: preferences,
            secrets: secrets,
            repository: SwiftDataSchoolRepository(container: container),
            provider: makeProvider(
                for: preferences.dataSource,
                secrets: secrets
            )
        )
    }

    func reloadProvider() {
        let provider = Self.makeProvider(
            for: preferences.dataSource,
            secrets: secrets
        )

        sync = SchoolSyncService(
            provider: provider,
            repository: repository,
            preferences: preferences
        )
    }

    static func makeProvider(
        for source: DataSourceKind,
        secrets: SecretStore? = nil
    ) -> SchoolDataProvider {

        switch source {

        case .demo:
            return DemoSchoolDataProvider()

        case .pronote:
            guard let secrets,
                  let credentials = try? CredentialsStore(store: secrets).load()
            else {
                return PronoteSchoolDataProvider(
                    client: UnavailablePronoteClient()
                )
            }

            let options = PronoteLoginOptions(
                useENT: false,
                mobileUUID: credentials.mobileUUID,
                clientIdentifier: credentials.mobileUUID,
                mobileToken: credentials.usesMobileToken
                    ? credentials.password
                    : nil,
                qrLogin: credentials.usesMobileToken
            )

            return PronoteSchoolDataProvider(
                client: LivePronoteClient(
                    credentials: credentials,
                    options: options
                )
            )
        }
    }
}