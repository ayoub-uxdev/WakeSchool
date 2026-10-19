import Foundation

/// Une période scolaire (trimestre, semaine, etc.) pour laquelle l'emploi du temps
/// a été ou doit être récupéré. Permet le chargement progressif sans tout télécharger
/// à chaque synchronisation, et préserve les périodes déjà en cache.
struct SchoolPeriod: Identifiable, Codable, Hashable {
    /// Identifiant stable de la période (ID PRONOTE ou identifiant généré).
    let id: String
    /// Libellé d'affichage (ex. « Trimestre 1 », « Semaine du 12 octobre »).
    var title: String
    /// Début de la période (inclus).
    var startDate: Date
    /// Fin de la période (inclus).
    var endDate: Date
    /// True si l'emploi du temps de cette période a été récupéré avec succès en totalité.
    /// Une période non marquée complète ne doit pas être interprétée comme vide.
    var isTimetableComplete: Bool = false
}
