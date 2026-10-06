import Foundation

/// Paramètres du calcul de l'heure de réveil recommandée.
/// Les durées sont exprimées en secondes.
struct WakeTimeInput: Equatable {
    /// Début du premier cours de la journée.
    var firstClassStart: Date
    /// Temps de trajet entre le domicile et l'établissement.
    var travelTime: TimeInterval
    /// Temps de préparation entre le réveil et le départ.
    var preparationTime: TimeInterval
    /// Marge de sécurité (retard de bus, imprévus), appliquée avant le début du cours.
    var safetyMargin: TimeInterval
}

extension WakeTimeInput {
    /// Variante pratique avec des durées en minutes.
    init(firstClassStart: Date,
         travelMinutes: Int,
         preparationMinutes: Int,
         safetyMarginMinutes: Int) {
        self.init(firstClassStart: firstClassStart,
                  travelTime: TimeInterval(travelMinutes) * 60,
                  preparationTime: TimeInterval(preparationMinutes) * 60,
                  safetyMargin: TimeInterval(safetyMarginMinutes) * 60)
    }
}

/// Résultat du calcul. `wakeTime` est la date que `AlarmManager.schedule(at:)` pourra utiliser.
struct WakeTimeRecommendation: Equatable {
    /// Heure de réveil recommandée.
    let wakeTime: Date
    /// Heure de départ de la maison (réveil + préparation).
    let departureTime: Date
    /// Début du premier cours pris en compte.
    let firstClassStart: Date

    /// Durée totale entre le réveil et le début du cours.
    var totalLeadTime: TimeInterval {
        firstClassStart.timeIntervalSince(wakeTime)
    }
}

enum WakeTimeError: LocalizedError, Equatable {
    /// Une durée est négative ou n'est pas un nombre fini.
    case invalidDuration
    /// Aucun cours (non annulé) trouvé pour la journée demandée.
    case noCourse

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "Les durées de trajet, de préparation et de marge doivent être positives ou nulles."
        case .noCourse:
            return "Aucun cours trouvé pour cette journée."
        }
    }
}

/// Calcul de l'heure de réveil recommandée.
/// Logique pure : aucune dépendance à AlarmKit ni à l'état de l'application.
///
/// Règle : départ = début du cours − trajet − marge de sécurité ; réveil = départ − préparation.
enum WakeTimeCalculator {

    static func recommend(_ input: WakeTimeInput) throws -> WakeTimeRecommendation {
        let durations = [input.travelTime, input.preparationTime, input.safetyMargin]
        guard durations.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw WakeTimeError.invalidDuration
        }

        let departure = input.firstClassStart
            .addingTimeInterval(-(input.travelTime + input.safetyMargin))
        let wake = departure.addingTimeInterval(-input.preparationTime)

        return WakeTimeRecommendation(wakeTime: wake,
                                      departureTime: departure,
                                      firstClassStart: input.firstClassStart)
    }

    /// Début du premier cours non annulé du jour `day`, ou nil s'il n'y en a pas.
    static func firstCourseStart(in entries: [TimetableEntry],
                                 on day: Date,
                                 calendar: Calendar = .current) -> Date? {
        entries
            .filter { !$0.isCancelled && calendar.isDate($0.start, inSameDayAs: day) }
            .map(\.start)
            .min()
    }

    /// Calcule le réveil recommandé pour le jour `day` à partir de l'emploi du temps.
    static func recommend(for day: Date,
                          entries: [TimetableEntry],
                          travelTime: TimeInterval,
                          preparationTime: TimeInterval,
                          safetyMargin: TimeInterval,
                          calendar: Calendar = .current) throws -> WakeTimeRecommendation {
        guard let start = firstCourseStart(in: entries, on: day, calendar: calendar) else {
            throw WakeTimeError.noCourse
        }
        return try recommend(WakeTimeInput(firstClassStart: start,
                                           travelTime: travelTime,
                                           preparationTime: preparationTime,
                                           safetyMargin: safetyMargin))
    }
}