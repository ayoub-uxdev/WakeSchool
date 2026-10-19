import Foundation
import SwiftUI
import WidgetKit

/// Fournit les entrées de timeline du widget à partir des UserDefaults partagés.
///
/// L'extension reçoit une liste limitée de cours futurs (encodée en JSON) et
/// sélectionne elle-même le prochain cours non annulé dont l'heure de début est
/// strictement postérieure à maintenant. Ainsi, même si WakeSchool n'a pas été
/// rouvert entre-temps, le widget affiche le cours suivant dès que le cours
/// courant est terminé.
struct Provider: TimelineProvider {
    typealias Entry = WidgetEntry

    private let groupIdentifier = "group.com.ayoub.wakeschool"

    func placeholder(in context: Context) -> WidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = makeEntry()
        // Rafraîchissement toutes les heures ; l'application déclenche aussi un
        // rechargement immédiat après chaque synchronisation réussie.
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func makeEntry() -> WidgetEntry {
        let defaults = UserDefaults(suiteName: groupIdentifier)
        guard let defaults else {
            return WidgetEntry(date: Date(), state: .neverSynced)
        }

        // Aucun cours n'a jamais été écrit : première utilisation, pas encore
        // de synchronisation réussie.
        guard defaults.bool(forKey: widgetHasEverSyncedKey) else {
            return WidgetEntry(date: Date(), state: .neverSynced)
        }

        // Décode la liste limitée de cours futurs préparée par l'application.
        var futureCourses: [WidgetCourse] = []
        if let data = defaults.data(forKey: widgetCoursesJsonKey),
           let decoded = try? JSONDecoder().decode([WidgetCourse].self, from: data) {
            futureCourses = decoded
        }

        let now = Date()
        let next = futureCourses.first { !$0.isCancelled && $0.startDate > now }

        if let next {
            return WidgetEntry(date: Date(), state: .hasNextCourse(next))
        }
        return WidgetEntry(date: Date(), state: .syncedNoFutureCourses)
    }

    // MARK: - Clés de partage (synchronisées avec l'application principale)

    private let widgetHasEverSyncedKey = "widget_has_ever_synced"
    private let widgetCoursesJsonKey = "widget_courses_json"
}
