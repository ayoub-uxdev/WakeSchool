import Foundation

/// Préférences simples (UserDefaults). Aucun secret ici : voir `SecretStore`.
final class PreferencesStore {
    private enum Key {
        static let dataSource = "dataSource"
        static let appearance = "appearance"
        static let travelMinutes = "wake.travelMinutes"
        static let preparationMinutes = "wake.preparationMinutes"
        static let safetyMarginMinutes = "wake.safetyMarginMinutes"
        static let lastSyncDate = "sync.lastDate"
        static let wakeAlarmEnabled = "wake.alarmEnabled"
        static let customWakeMinutes = "wake.customMinutes"
        static let wakeConfirmation = "wake.confirmation"
        static let knownGradeIDs = "sync.knownGradeIDs"
        static let knownExamIDs = "sync.knownExamIDs"
        /// Marqueur de référence de détection : true dès la première synchronisation
        /// réussie. Ne JAMAIS déduire « premier lancement » d'un ensemble vide
        /// (un utilisateur peut n'avoir réellement aucune note au départ).
        static let changeDetectionBaseline = "sync.changeBaseline"
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

    var appearance: AppearancePreference {
        get {
            defaults.string(forKey: Key.appearance)
                .flatMap(AppearancePreference.init(rawValue:))
                ?? .system
        }
        set {
            defaults.set(
                newValue.rawValue,
                forKey: Key.appearance
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

    // MARK: - Réveil automatique (LOT 8)

    /// Réveil automatique activé : le réveil suit l'emploi du temps.
    var wakeAlarmEnabled: Bool {
        get { defaults.object(forKey: Key.wakeAlarmEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.wakeAlarmEnabled) }
    }

    /// Heure de réveil personnalisée (minutes depuis minuit), nil = calcul AutoWake.
    var customWakeMinutes: Int? {
        get { defaults.object(forKey: Key.customWakeMinutes) as? Int }
        set { defaults.set(newValue, forKey: Key.customWakeMinutes) }
    }

    /// Paramètres de la confirmation quotidienne (21 h par défaut).
    var wakeConfirmation: WakeConfirmationSettings {
        get {
            guard let data = defaults.data(forKey: Key.wakeConfirmation),
                  let settings = try? JSONDecoder().decode(WakeConfirmationSettings.self, from: data) else {
                return .default
            }
            return settings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.wakeConfirmation)
            }
        }
    }

    // MARK: - Détection des nouveautés (ids connus)

    /// Identifiants des notes déjà vues (dont ABS) : évite les notifications répétées.
    var knownGradeIDs: Set<UUID> {
        get {
            guard let data = defaults.data(forKey: Key.knownGradeIDs) else { return [] }
            return (try? JSONDecoder().decode(Set<UUID>.self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.knownGradeIDs)
            }
        }
    }

    /// Identifiants des contrôles déjà vus.
    var knownExamIDs: Set<UUID> {
        get {
            guard let data = defaults.data(forKey: Key.knownExamIDs) else { return [] }
            return (try? JSONDecoder().decode(Set<UUID>.self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.knownExamIDs)
            }
        }
    }

    /// True dès que la première synchronisation a établi la référence.
    /// Persistant et explicite : un ensemble d'ids vide ne signifie PAS
    /// « premier lancement ».
    var hasChangeDetectionBaseline: Bool {
        get { defaults.bool(forKey: Key.changeDetectionBaseline) }
        set { defaults.set(newValue, forKey: Key.changeDetectionBaseline) }
    }
}