import Foundation

// MARK: - Absences et retards (vie scolaire)

/// Nature d'un évènement de vie scolaire.
enum AttendanceKind: String, Codable, CaseIterable, Hashable {
    case absence
    case delay

    var displayName: String {
        switch self {
        case .absence: return "Absence"
        case .delay: return "Retard"
        }
    }

    var systemImage: String {
        switch self {
        case .absence: return "person.fill.xmark"
        case .delay: return "clock.fill"
        }
    }
}

/// Évènement de vie scolaire (absence ou retard) tel que fourni par PRONOTE.
///
/// Tous les champs sont optionnels ou tolérants : PRONOTE ne renseigne pas
/// toujours la justification, le motif ou la durée. Aucune valeur n'est inventée.
struct AttendanceEvent: Identifiable, Codable, Hashable {
    /// Identifiant stable, dérivé de l'identifiant PRONOTE lorsqu'il existe.
    let id: UUID
    var kind: AttendanceKind
    /// Début de l'absence, ou date/heure du retard.
    var start: Date
    /// Fin de l'absence si PRONOTE la fournit (nil pour un retard ponctuel).
    var end: Date?
    /// Durée en minutes si elle peut être déterminée (depuis `hours`/`minutes` ou `end - start`).
    var durationMinutes: Int?
    /// true si l'évènement a été justifié auprès de la vie scolaire.
    var isJustified: Bool
    /// Justification libre (retard) si fournie.
    var justification: String?
    /// Motif(s) éventuels fournis par PRONOTE.
    var reasons: [String]
    /// Nom de la matière concernée si PRONOTE l'associe à l'évènement.
    var subjectName: String?

    init(id: UUID,
         kind: AttendanceKind,
         start: Date,
         end: Date? = nil,
         durationMinutes: Int? = nil,
         isJustified: Bool = false,
         justification: String? = nil,
         reasons: [String] = [],
         subjectName: String? = nil) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.isJustified = isJustified
        self.justification = justification
        self.reasons = reasons
        self.subjectName = subjectName
    }
}
