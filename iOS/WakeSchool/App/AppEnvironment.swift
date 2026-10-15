import Foundation
import SwiftData

@MainActor
final class AppEnvironment {
    let preferences: PreferencesStore
    let secrets: SecretStore
    let repository: SchoolRepository
    private(set) var sync: SchoolSyncService
    /// Centre de notifications (historique local), partagé par tous les écrans.
    let notificationCenter: NotificationCenterStore
    /// Règles de notification personnalisées.
    let notificationRules: NotificationRulesStore
    /// Cycle de vie de l'alarme automatique AutoWake (store isolé des alarmes manuelles).
    let autoWakeLifecycle: AutoWakeLifecycle
    /// Orchestrateur des notifications (autorisation, planification, détection).
    let notifications: NotificationOrchestrator

    init(
        preferences: PreferencesStore,
        secrets: SecretStore,
        repository: SchoolRepository,
        provider: SchoolDataProvider
    ) {
        self.preferences = preferences
        self.secrets = secrets
        self.repository = repository
        let centerStore = NotificationCenterStore()
        let rulesStore = NotificationRulesStore()
        self.notificationCenter = centerStore
        self.notificationRules = rulesStore
        let lifecycle = AutoWakeLifecycle(
            alarmScheduler: AlarmManager.shared,
            store: UserDefaultsAutoWakeAlarmStore()
        )
        self.autoWakeLifecycle = lifecycle
        self.notifications = NotificationOrchestrator(
            scheduler: SystemNotificationScheduler(),
            center: centerStore,
            rules: rulesStore,
            preferences: preferences,
            alarmScheduler: AlarmManager.shared,
            autoWakeLifecycle: lifecycle
        )
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

            let options = PronoteLoginOptions.automaticReconnection(
                for: credentials
            )

            return PronoteSchoolDataProvider(
                client: LivePronoteClient(
                    credentials: credentials,
                    options: options,
                    onCredentialsUpdated: { updatedCredentials in
                        try CredentialsStore(store: secrets).save(updatedCredentials)
                    }
                )
            )
        }
    }
}