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

/// Préférence d'apparence de l'interface.
/// Persistée dans `PreferencesStore`. Le mapping vers `ColorScheme` reste une
/// responsabilité de l'UI (ce modèle reste volontairement sans dépendance SwiftUI).
enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Automatique"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
