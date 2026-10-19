import SwiftUI
import WidgetKit

/// Point d'entrée de l'extension Widget « Prochain cours ».
@main
struct WakeSchoolWidget: Widget {
    let kind: String = "WakeSchoolWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Prochain cours")
        .description("Affiche le prochain cours synchronisé depuis PRONOTE.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
