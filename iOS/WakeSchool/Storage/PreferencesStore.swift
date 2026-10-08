import Foundation

/// Préférences simples (UserDefaults). Aucun secret ici : voir `SecretStore`.
final class PreferencesStore {
    private enum Key {
        static let dataSource = "dataSource"
        static let travelMinutes = "wake.travelMinutes"
        static let preparationMinutes = "wake.preparationMinutes"
        static let safetyMarginMinutes = "wake.safetyMarginMinutes"
        static let lastSyncDate = "sync.lastDate"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var dataSource: DataSourceKind {
        get {
            defaults.string(forKey: Key.dataSource)
                .flatMap(DataSourceKind.init(rawValue:))
                ?? .demo
        }
        set {
            defaults.set(
                newValue.rawValue,
                forKey: Key.dataSource
            )
        }
    }

    var wakeSettings: WakeSettings {
        get {
            let fallback = WakeSettings.default

            return WakeSettings(
                travelMinutes:
                    defaults.object(
                        forKey: Key.travelMinutes
                    ) as? Int
                    ?? fallback.travelMinutes,

                preparationMinutes:
                    defaults.object(
                        forKey: Key.preparationMinutes
                    ) as? Int
                    ?? fallback.preparationMinutes,

                safetyMarginMinutes:
                    defaults.object(
                        forKey: Key.safetyMarginMinutes
                    ) as? Int
                    ?? fallback.safetyMarginMinutes
            )
        }

        set {
            defaults.set(
                newValue.travelMinutes,
                forKey: Key.travelMinutes
            )

            defaults.set(
                newValue.preparationMinutes,
                forKey: Key.preparationMinutes
            )

            defaults.set(
                newValue.safetyMarginMinutes,
                forKey: Key.safetyMarginMinutes
            )
        }
    }

    var lastSyncDate: Date? {
        get {
            defaults.object(
                forKey: Key.lastSyncDate
            ) as? Date
        }

        set {
            defaults.set(
                newValue,
                forKey: Key.lastSyncDate
            )
        }
    }
}