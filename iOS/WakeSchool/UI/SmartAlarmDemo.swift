import Foundation

/// Erreurs possibles lors de la construction des données de démonstration.
enum SmartAlarmDemoError: LocalizedError, Equatable {
    /// Impossible de construire l'heure du premier cours pour le jour demandé.
    case invalidFirstClassDate

    var errorDescription: String? {
        switch self {
        case .invalidFirstClassDate:
            return "Impossible de déterminer l'heure du premier cours de démonstration."
        }
    }
}

/// Données de démonstration de l'écran « Réveil intelligent ».
/// Les horaires sont calculés par `WakeTimeCalculator` : aucune règle de calcul ici.
enum SmartAlarmDemo {
    static let firstClassHour = 8
    static let firstClassMinute = 0
    static let travelMinutes = 25
    static let preparationMinutes = 40
    static let safetyMarginMinutes = 10

    /// Paramètres de démonstration pour le jour `day` (premier cours à 08:00).
    static func input(for day: Date, calendar: Calendar = .current) throws -> WakeTimeInput {
        guard let start = calendar.date(bySettingHour: firstClassHour,
                                        minute: firstClassMinute,
                                        second: 0,
                                        of: day) else {
            throw SmartAlarmDemoError.invalidFirstClassDate
        }
        return WakeTimeInput(firstClassStart: start,
                             travelMinutes: travelMinutes,
                             preparationMinutes: preparationMinutes,
                             safetyMarginMinutes: safetyMarginMinutes)
    }

    /// Réveil recommandé pour le jour `day`, calculé par `WakeTimeCalculator`.
    static func recommendation(for day: Date,
                               calendar: Calendar = .current) -> Result<WakeTimeRecommendation, Error> {
        Result { try WakeTimeCalculator.recommend(try input(for: day, calendar: calendar)) }
    }
}