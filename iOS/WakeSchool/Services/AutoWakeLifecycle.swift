import Foundation

/// Alarme automatique AutoWake, mémorisée séparément des alarmes manuelles
/// (SmartAlarmView) : deux clés distinctes, deux vies indépendantes.
/// AutoWake n'annule JAMAIS une alarme manuelle — il ne manipule que son propre
/// identifiant persisté ici.
struct ScheduledAutoWakeAlarm: Codable, Equatable {
    let id: UUID
    let fireDate: Date
    /// Jour visé (clé stable YYYY-MM-DD) pour détecter un changement de jour cible.
    let targetDayKey: String
    /// True si l'heure provient du choix personnalisé de l'utilisateur.
    let isCustom: Bool
}

protocol AutoWakeAlarmStoring: AnyObject {
    var current: ScheduledAutoWakeAlarm? { get set }
}

/// Persistance UserDefaults de l'alarme automatique AutoWake.
/// Clé distincte de `alarm.scheduled` (alarmes manuelles SmartAlarmView).
final class UserDefaultsAutoWakeAlarmStore: AutoWakeAlarmStoring {
    private let defaults: UserDefaults
    private static let key = "autowake.scheduledAlarm"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: ScheduledAutoWakeAlarm? {
        get {
            guard let data = defaults.data(forKey: Self.key) else { return nil }
            return try? JSONDecoder().decode(ScheduledAutoWakeAlarm.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }
}

final class InMemoryAutoWakeAlarmStore: AutoWakeAlarmStoring {
    var current: ScheduledAutoWakeAlarm?
    init(current: ScheduledAutoWakeAlarm? = nil) { self.current = current }
}

/// Gestion du cycle de vie de l'alarme automatique AutoWake.
///
/// Règles :
/// - l'alarme automatique vit dans son propre store (jamais d'interaction avec
///   une alarme manuelle de SmartAlarmView) ;
/// - une alarme n'est JAMAIS considérée comme programmée si AlarmKit échoue ;
/// - désactivation, changement d'heure personnalisée, changement de préférences
///   ou disparition/annulation du premier cours entraînent soit une
///   reprogrammation, soit l'annulation de l'alarme automatique.
@MainActor
final class AutoWakeLifecycle {
    private let alarmScheduler: AlarmScheduling
    private let store: AutoWakeAlarmStoring

    init(alarmScheduler: AlarmScheduling, store: AutoWakeAlarmStoring) {
        self.alarmScheduler = alarmScheduler
        self.store = store
    }

    /// Alarme automatique actuellement mémorisée (pour l'UI).
    var current: ScheduledAutoWakeAlarm? { store.current }

    /// Programme ou reprogramme l'alarme automatique pour `plan`.
    /// Retourne l'alarme mémorisée, ou nil si AlarmKit a échoué (aucune
    /// inscription partielle : le store n'est PAS mis à jour en cas d'échec).
    @discardableResult
    func schedule(plan: AutoWakePlan) async -> ScheduledAutoWakeAlarm? {
        let fireDate = plan.recommendation.wakeTime
        guard fireDate > Date() else { return nil }

        do {
            let newID = try await alarmScheduler.schedule(at: fireDate)
            // Annulation de l'ANCIENNE alarme automatique uniquement (store AutoWake),
            // et seulement après le succès de la nouvelle programmation.
            if let previous = store.current, previous.id != newID {
                try? alarmScheduler.cancel(id: previous.id)
            }
            let scheduled = ScheduledAutoWakeAlarm(id: newID,
                                                   fireDate: fireDate,
                                                   targetDayKey: plan.targetDayKey(calendar: .current),
                                                   isCustom: plan.isCustom)
            store.current = scheduled
            return scheduled
        } catch {
            // Échec AlarmKit : le store n'est pas touché (l'alarme n'existe pas).
            return nil
        }
    }

    /// Annule l'alarme automatique existante, si elle est encore connue du système.
    func cancel() {
        guard let alarm = store.current else { return }
        try? alarmScheduler.cancel(id: alarm.id)
        store.current = nil
    }

    /// Désactivation d'AutoWake : annule l'alarme automatique (pas les autres).
    func disable() { cancel() }

    /// Si le plan courant ne correspond plus à l'alarme mémorisée
    /// (cours annulé, disparu, déplacé, préférences changées), annule l'alarme
    /// obsolète. Retourne true si une annulation a eu lieu.
    @discardableResult
    func reconcile(plan: AutoWakePlan?) -> Bool {
        guard let alarm = store.current else { return false }
        let needsCancel: Bool
        if let plan, plan.recommendation.wakeTime > Date() {
            needsCancel = false // un plan valide existe : la reprogrammation s'en charge
        } else {
            needsCancel = true // plus de plan valide : alarme obsolète
        }
        if needsCancel {
            cancel()
        }
        return needsCancel
    }
}

extension AutoWakePlan {
    /// Clé stable du jour visé (YYYY-MM-DD) pour la persistance.
    func targetDayKey(calendar: Calendar) -> String {
        WakeNotification.dayKey(targetDay, calendar: calendar)
    }
}
