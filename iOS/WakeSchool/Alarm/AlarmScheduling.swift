import Foundation

/// Abstraction d'AlarmKit utilisée par la logique de l'écran « Réveil intelligent ».
/// `AlarmManager` (le seul point d'entrée AlarmKit) l'implémente ; les tests utilisent un faux.
@MainActor
protocol AlarmScheduling: AnyObject {
    /// Programme une alarme à `date` et retourne son identifiant.
    func schedule(at date: Date) async throws -> UUID
    func cancel(id: UUID) throws
    /// true si le système connaît encore l'alarme `id`.
    func isScheduled(id: UUID) throws -> Bool
}

/// Alarme WakeSchool programmée, mémorisée pour être retrouvée au prochain lancement.
struct ScheduledAlarm: Codable, Equatable {
    let id: UUID
    let fireDate: Date
}

protocol ScheduledAlarmStoring: AnyObject {
    var current: ScheduledAlarm? { get set }
}

final class UserDefaultsScheduledAlarmStore: ScheduledAlarmStoring {
    private let defaults: UserDefaults
    private let key = "alarm.scheduled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: ScheduledAlarm? {
        get {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(ScheduledAlarm.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

final class InMemoryScheduledAlarmStore: ScheduledAlarmStoring {
    var current: ScheduledAlarm?
    init(current: ScheduledAlarm? = nil) { self.current = current }
}
