import SwiftUI
import WidgetKit

/// Données affichées par le widget.
///
/// L'extension ne connaît pas PRONOTE : elle lit un instantané minimal préparé
/// par l'application principale dans les UserDefaults du App Group.
struct WidgetEntry: TimelineEntry {
    let date: Date
    /// État explicite des données du widget.
    let state: WidgetDataState

    /// Placeholder utilisé par le système durant le chargement / prévisualisation.
    static var placeholder: WidgetEntry {
        WidgetEntry(
            date: Date(),
            state: .neverSynced
        )
    }
}

/// État des données du widget, distingué explicitement pour ne jamais
/// présenter des données manquantes comme des vacances ou une absence certaine.
enum WidgetDataState: Equatable {
    /// Aucune synchronisation n'a encore été effectuée depuis l'installation.
    case neverSynced
    /// Synchronisation effectuée avec succès, mais aucun cours futur connu
    /// dans le cache (emploi du temps vide, tous les cours sont passés ou annulés).
    case syncedNoFutureCourses
    /// Un prochain cours est disponible.
    case hasNextCourse(WidgetCourse)
}
