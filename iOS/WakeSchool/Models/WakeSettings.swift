import Foundation

/// Préférences de l'utilisateur pour le calcul du réveil (en minutes).
struct WakeSettings: Codable, Equatable {
    var travelMinutes: Int
    var preparationMinutes: Int
    var safetyMarginMinutes: Int

    static let `default` = WakeSettings(travelMinutes: 25,
                                        preparationMinutes: 40,
                                        safetyMarginMinutes: 10)

    var travelTime: TimeInterval { TimeInterval(travelMinutes) * 60 }
    var preparationTime: TimeInterval { TimeInterval(preparationMinutes) * 60 }
    var safetyMargin: TimeInterval { TimeInterval(safetyMarginMinutes) * 60 }
}

/// Source de données choisie par l'utilisateur.
enum DataSourceKind: String, Codable, Equatable {
    case demo
    case pronote
}
